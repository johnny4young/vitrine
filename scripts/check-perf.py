#!/usr/bin/env python3
"""Warn-only comparison of one CI row's performance medians with a committed baseline.

`make perf` prints a `PERF-JSON` line per scenario; CI keeps them as
`perf-measurements.jsonl`. The suite's own budgets compare each p95 with a fixed target,
so a scenario that drifts from 180 ms to 290 ms under a 300 ms target leaves no trace.
This script compares the run's medians with the platform's recorded medians instead.

Shared runners vary by up to about 40% from one run to the next, and a slow machine slows
every scenario together, so an absolute comparison flags slow machines rather than slow
code. The comparison therefore scales the baseline by the run's overall speed (the median
of every scenario's measured-to-baseline ratio) and reports a scenario only when it is
more than DRIFT_RATIO times that expectation and at least DRIFT_MIN_MS slower. Backtested
on 24 passing main-branch row runs, that rule raised 3 warnings. It never fails the job.

Refresh a baseline from recent passing main runs with `--record`, one `--source` per file.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
DRIFT_RATIO = 1.5
DRIFT_MIN_MS = 25.0
# A few-millisecond scenario turns timer jitter into large ratios; it is still printed,
# but neither judged nor allowed to move the run's speed factor.
MIN_BASELINE_MS = 5.0
# With fewer comparable scenarios the median ratio is not a meaningful speed estimate.
MIN_SCENARIOS_FOR_FACTOR = 4


@dataclass
class Comparison:
    factor: float
    rows: list[dict[str, Any]] = field(default_factory=list)
    drifted: list[str] = field(default_factory=list)
    missing: list[str] = field(default_factory=list)
    unrecorded: list[str] = field(default_factory=list)


def parse_measurements(text: str, source: str) -> dict[str, float]:
    medians: dict[str, float] = {}
    for number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
            label, median = record["label"], record["median_ms"]
        except (json.JSONDecodeError, KeyError, TypeError) as error:
            raise ValueError(f"{source}:{number}: not a PERF-JSON record ({error})") from error
        if not isinstance(label, str) or isinstance(median, bool) or not isinstance(median, (int, float)):
            raise ValueError(f"{source}:{number}: label must be text and median_ms a number")
        if label in medians:
            raise ValueError(f"{source}:{number}: duplicate scenario {label!r}")
        medians[label] = float(median)
    return medians


def validate_baseline(baseline: Any) -> dict[str, float]:
    if not isinstance(baseline, dict) or baseline.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError(f"baseline must be a schemaVersion {SCHEMA_VERSION} object")
    for key in ("platform", "runnerLabel"):
        if not isinstance(baseline.get(key), str) or not baseline[key]:
            raise ValueError(f"baseline needs a non-empty {key}")
    sources = baseline.get("sources")
    if not isinstance(sources, list) or not sources or not all(isinstance(s, str) for s in sources):
        raise ValueError("baseline needs the list of runs it was recorded from")
    medians = baseline.get("medians")
    if not isinstance(medians, dict) or not medians:
        raise ValueError("baseline needs a non-empty medians object")
    for label, value in medians.items():
        if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
            raise ValueError(f"baseline median for {label!r} must be a non-negative number")
    return {label: float(value) for label, value in medians.items()}


def compare(measured: dict[str, float], baseline: dict[str, float]) -> Comparison:
    comparable = sorted(
        label for label in measured if baseline.get(label, 0.0) >= MIN_BASELINE_MS)
    ratios = [measured[label] / baseline[label] for label in comparable]
    factor = statistics.median(ratios) if len(ratios) >= MIN_SCENARIOS_FOR_FACTOR else 1.0
    result = Comparison(factor=factor)
    result.missing = sorted(set(baseline) - set(measured))
    result.unrecorded = sorted(set(measured) - set(baseline))
    for label in sorted(set(measured) & set(baseline)):
        expected = baseline[label] * factor
        row = {"label": label, "baseline": baseline[label], "expected": expected,
               "measured": measured[label], "ratio": None, "status": "too fast to judge"}
        if label in comparable:
            row["ratio"] = measured[label] / expected if expected else None
            drifted = (
                row["ratio"] is not None
                and row["ratio"] > DRIFT_RATIO
                and measured[label] - expected >= DRIFT_MIN_MS)
            row["status"] = "slower than expected" if drifted else "ok"
            if drifted:
                result.drifted.append(label)
        result.rows.append(row)
    return result


def annotations(result: Comparison) -> list[str]:
    lines = []
    for row in result.rows:
        if row["status"] == "slower than expected":
            lines.append(
                f"::warning title=Performance drift::{row['label']} median "
                f"{row['measured']:.0f} ms is {row['ratio']:.2f}x the {row['expected']:.0f} ms "
                f"expected on this run (baseline {row['baseline']:.0f} ms x run speed "
                f"{result.factor:.2f})")
    for label in result.missing:
        lines.append(
            f"::warning title=Performance baseline::{label} has a baseline but was not measured")
    for label in result.unrecorded:
        lines.append(
            f"::notice title=Performance baseline::{label} has no baseline yet; record one "
            "once it has run on main")
    return lines


def summary(result: Comparison, platform: str) -> str:
    lines = [
        f"### Performance vs. baseline ({platform})",
        "",
        f"Run speed factor: {result.factor:.2f} (median measured/baseline ratio). A scenario is "
        f"flagged above {DRIFT_RATIO}x its expected median and at least {DRIFT_MIN_MS:.0f} ms slower.",
        "",
        "| Scenario | Baseline | Expected | Measured | Ratio | Status |",
        "|---|---:|---:|---:|---:|---|",
    ]
    for row in result.rows:
        ratio = f"{row['ratio']:.2f}x" if row["ratio"] is not None else "-"
        lines.append(
            f"| {row['label']} | {row['baseline']:.0f} ms | {row['expected']:.0f} ms | "
            f"{row['measured']:.0f} ms | {ratio} | {row['status']} |")
    return "\n".join(lines) + "\n"


def record(files: list[Path], sources: list[str], platform: str, runner_label: str) -> dict[str, Any]:
    if not files:
        raise ValueError("record needs at least one measurements file")
    if len(sources) != len(files):
        raise ValueError(f"record needs one --source per file ({len(files)} files, {len(sources)} sources)")
    collected: dict[str, list[float]] = {}
    for path in files:
        for label, median in parse_measurements(path.read_text(encoding="utf-8"), str(path)).items():
            collected.setdefault(label, []).append(median)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "platform": platform,
        "runnerLabel": runner_label,
        "metric": "median of each run's median_ms",
        "sources": sources,
        "medians": {label: round(statistics.median(values), 1) for label, values in sorted(collected.items())},
    }


def self_test() -> None:
    baseline = {"a": 100.0, "b": 200.0, "c": 50.0, "d": 1000.0, "tiny": 3.0}

    same = compare(dict(baseline), baseline)
    assert same.factor == 1.0 and not same.drifted and not same.missing and not same.unrecorded

    # A uniformly slow runner is not a regression.
    slow = compare({label: value * 1.4 for label, value in baseline.items()}, baseline)
    assert abs(slow.factor - 1.4) < 1e-9 and not slow.drifted

    # One scenario doubling on an otherwise steady run is.
    doubled = compare({**baseline, "b": 400.0}, baseline)
    assert doubled.drifted == ["b"], doubled.drifted

    # The same doubling on a runner that is 1.4x slow overall stays under the ratio...
    scaled = {label: value * 1.4 for label, value in baseline.items()}
    assert not compare({**scaled, "b": 400.0}, baseline).drifted
    # ...while tripling on that runner is still reported.
    assert compare({**scaled, "b": 600.0}, baseline).drifted == ["b"]

    # The absolute floor: 50 -> 75 is 1.5x exactly and +25 ms, 50 -> 76 is past both.
    assert not compare({**baseline, "c": 75.0}, baseline).drifted
    assert compare({**baseline, "c": 76.0}, baseline).drifted == ["c"]
    # A large ratio that is still only a few milliseconds is not reported.
    small = {"a": 10.0, "b": 12.0, "c": 14.0, "d": 16.0}
    assert not compare({**small, "a": 30.0}, small).drifted

    # Sub-5 ms scenarios are printed but never judged and never move the factor.
    tiny = compare({**baseline, "tiny": 300.0}, baseline)
    assert tiny.factor == 1.0 and not tiny.drifted
    assert next(row for row in tiny.rows if row["label"] == "tiny")["status"] == "too fast to judge"

    # Too few comparable scenarios: no speed estimate, so compare against the raw baseline.
    few = compare({"a": 150.0, "b": 200.0}, {"a": 100.0, "b": 200.0})
    assert few.factor == 1.0

    gaps = compare({"a": 100.0, "b": 200.0, "c": 50.0, "new": 9.0}, baseline)
    assert gaps.missing == ["d", "tiny"] and gaps.unrecorded == ["new"]
    notes = annotations(gaps)
    assert any(line.startswith("::warning title=Performance baseline::d ") for line in notes)
    assert any(line.startswith("::notice title=Performance baseline::new ") for line in notes)
    warning = annotations(doubled)[0]
    assert warning.startswith("::warning title=Performance drift::b median 400 ms is 2.00x")
    assert "| b | 200 ms | 200 ms | 400 ms | 2.00x | slower than expected |" in summary(doubled, "x")

    assert parse_measurements('{"label":"a","median_ms":12,"p95_ms":20,"samples":7}\n\n', "t") == {"a": 12.0}
    for bad in ('{"label":"a"}', "not json", '{"label":"a","median_ms":true}', '{"label":1,"median_ms":2}',
                '{"label":"a","median_ms":1}\n{"label":"a","median_ms":2}'):
        try:
            parse_measurements(bad, "t")
        except ValueError:
            pass
        else:
            raise AssertionError(f"accepted malformed measurements: {bad!r}")

    recorded = {
        "schemaVersion": 1, "platform": "p", "runnerLabel": "r", "sources": ["s"],
        "medians": {"a": 1, "b": 2.5},
    }
    assert validate_baseline(recorded) == {"a": 1.0, "b": 2.5}
    for broken in ({**recorded, "schemaVersion": 2}, {**recorded, "sources": []},
                   {**recorded, "medians": {}}, {**recorded, "medians": {"a": -1}},
                   {**recorded, "runnerLabel": ""}):
        try:
            validate_baseline(broken)
        except ValueError:
            pass
        else:
            raise AssertionError(f"accepted a broken baseline: {broken!r}")

    with tempfile.TemporaryDirectory() as directory:
        folder = Path(directory)
        runs = []
        for index, median in enumerate((10, 20, 40)):
            path = folder / f"run{index}.jsonl"
            path.write_text(json.dumps({"label": "a", "median_ms": median}) + "\n", encoding="utf-8")
            runs.append(path)
        made = record(runs, ["one", "two", "three"], "macOS", "macos-x")
        assert made["medians"] == {"a": 20} and made["sources"] == ["one", "two", "three"]
        assert validate_baseline(made) == {"a": 20.0}
        assert record(runs[:2], ["one", "two"], "macOS", "macos-x")["medians"] == {"a": 15.0}
        try:
            record(runs, ["one"], "macOS", "macos-x")
        except ValueError:
            pass
        else:
            raise AssertionError("record accepted a source count that does not match the files")

        # The CI entry point returns 0 in every case, and says why it compared nothing.
        baseline_path = folder / "baseline.json"
        baseline_path.write_text(json.dumps(made), encoding="utf-8")
        out: list[str] = []
        assert run_check(folder / "absent.jsonl", baseline_path, summary_path=None, out=out) == 0
        assert out == ["::warning title=Performance drift::no measurements to compare; did the perf step run?"]
        out = []
        assert run_check(runs[0], runs[1], summary_path=None, out=out) == 0
        assert len(out) == 1 and out[0].startswith("::warning title=Performance drift::comparison did not run:")
        out = []
        summary_file = folder / "summary.md"
        assert run_check(runs[2], baseline_path, summary_path=str(summary_file), out=out) == 0
        # 2.00x, but only 20 ms slower: under the absolute floor, so not reported.
        assert "| a | 20 ms | 20 ms | 40 ms | 2.00x | ok |" in out[-1], out[-1]
        assert "### Performance vs. baseline (macOS)" in summary_file.read_text(encoding="utf-8")


def run_check(measurements: Path, baseline_path: Path, summary_path: str | None, out: list[str] | None = None) -> int:
    emit = out.append if out is not None else print
    try:
        baseline_document = json.loads(baseline_path.read_text(encoding="utf-8"))
        baseline = validate_baseline(baseline_document)
        if not measurements.is_file() or not measurements.read_text(encoding="utf-8").strip():
            emit("::warning title=Performance drift::no measurements to compare; did the perf step run?")
            return 0
        measured = parse_measurements(measurements.read_text(encoding="utf-8"), str(measurements))
        result = compare(measured, baseline)
    except Exception as error:  # Warn-only: a broken comparison must not fail the build job.
        emit(f"::warning title=Performance drift::comparison did not run: {error}")
        return 0
    for line in annotations(result):
        emit(line)
    table = summary(result, baseline_document["platform"])
    emit(table)
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(table)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--measurements", type=Path, help="perf-measurements.jsonl from one CI row")
    parser.add_argument("--baseline", type=Path, help="scripts/perf-baselines/<platform>.json")
    parser.add_argument("--record", type=Path, metavar="OUTPUT", help="write a baseline from FILES")
    parser.add_argument("--platform", help="with --record: the platform name, e.g. 'macOS 15 Sequoia'")
    parser.add_argument("--runner-label", help="with --record: the runner label, e.g. macos-15")
    parser.add_argument("--source", action="append", default=[], help="with --record: one per file, in order")
    parser.add_argument("files", nargs="*", type=Path, help="with --record: measurements files")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        print("check-perf self-test passed")
        return 0
    if args.record:
        if not args.platform or not args.runner_label:
            parser.error("--record needs --platform and --runner-label")
        document = record(args.files, args.source, args.platform, args.runner_label)
        args.record.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        print(f"recorded {len(document['medians'])} scenarios from {len(args.files)} runs to {args.record}")
        return 0
    if args.measurements is None or args.baseline is None:
        parser.error("--measurements and --baseline are required")
    return run_check(args.measurements, args.baseline, os.environ.get("GITHUB_STEP_SUMMARY"))


if __name__ == "__main__":
    sys.exit(main())
