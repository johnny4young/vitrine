#!/usr/bin/env python3
"""Fail-closed production and changed-line coverage guard for Vitrine."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable


PRODUCTION_TARGETS = {
    "Vitrine.app",
    "libVitrineDomain.a",
    "libVitrineRendering.a",
    "vitrine-cli",
    "VitrineMenuBarHelper",
}
CRITICAL_PREFIXES = (
    "VitrineDomain/",
    "VitrineRendering/Editor/",
    "VitrineRendering/Export/",
    "VitrineRendering/Models/",
    "VitrineRendering/Rendering/",
    "VitrineRendering/Support/",
    "VitrineRendering/Terminal/",
    "Vitrine/Models/",
    "Vitrine/CLI/",
    "Vitrine/Pro/",
    "Vitrine/Terminal/",
    "Vitrine/Rendering/",
)
NONVISUAL_WEB_FILES = {
    "HTMLRenderer.swift",
    "NetworkCapability.swift",
    "PrivateNetworkBlockRules.swift",
    "ResponsiveBoardComposer.swift",
    "URLLoadCoordinator.swift",
    "URLRenderer.swift",
    "URLSnapshotEngine.swift",
    "WebLoadWaiter.swift",
    "WebSessionAvailability.swift",
    "WebSessionStore.swift",
    "WebSnapshotConfig.swift",
    "WebSnapshotPresentation.swift",
    "WebURLValidation.swift",
}
DATA_ONLY_FILES = {
    # A declarative help-text wrapper. The executable schema interpolation is
    # attributed to CLIArgumentSchema.swift, so xccov emits no entry for this file.
    "Vitrine/CLI/CLIUsage.swift",
    # A three-case input enum with no executable lines; xccov intentionally emits no file entry.
    "VitrineRendering/Rendering/CaptureInput.swift",
    # Static OSLog category/signpost declarations likewise have no executable source lines.
    "VitrineRendering/Support/RenderingLog.swift",
}
HUNK_HEADER = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


class CoverageError(RuntimeError):
    """A malformed input or failed coverage policy."""


@dataclass(frozen=True)
class DiffCoverage:
    covered: int
    executable: int
    missed: tuple[str, ...]

    @property
    def ratio(self) -> float:
        return 1.0 if self.executable == 0 else self.covered / self.executable


def run(command: list[str], cwd: Path, *, require_output: bool = True) -> str:
    completed = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "no diagnostics"
        raise CoverageError(f"command failed ({' '.join(command)}): {detail}")
    if require_output and not completed.stdout.strip():
        raise CoverageError(f"command returned no data: {' '.join(command)}")
    return completed.stdout


def parse_json(raw: str, source: str) -> Any:
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise CoverageError(f"{source} did not contain valid JSON: {error}") from error


def load_json(path: Path, description: str) -> Any:
    try:
        return parse_json(path.read_text(encoding="utf-8"), str(path))
    except OSError as error:
        raise CoverageError(f"could not read {description} {path}: {error}") from error


def production_coverage(report: Any) -> tuple[int, int, float, dict[str, Any]]:
    if not isinstance(report, dict) or not isinstance(report.get("targets"), list):
        raise CoverageError("xccov report JSON has no targets array")
    targets = {
        target.get("name"): target
        for target in report["targets"]
        if isinstance(target, dict) and target.get("name") in PRODUCTION_TARGETS
    }
    missing = sorted(PRODUCTION_TARGETS - targets.keys())
    if missing:
        raise CoverageError(f"xccov report is missing production targets: {', '.join(missing)}")
    try:
        executable = sum(int(target["executableLines"]) for target in targets.values())
        covered = sum(int(target["coveredLines"]) for target in targets.values())
    except (KeyError, TypeError, ValueError) as error:
        raise CoverageError("xccov production target counts are malformed") from error
    if executable <= 0 or covered < 0 or covered > executable:
        raise CoverageError("xccov production target counts are inconsistent")
    return covered, executable, covered / executable, targets


def validate_baseline(baseline: Any) -> dict[str, Any]:
    if not isinstance(baseline, dict) or baseline.get("schemaVersion") != 1:
        raise CoverageError("coverage baseline schemaVersion must be 1")
    revision = baseline.get("sourceRevision")
    coverage = baseline.get("productionLineCoverage")
    if not isinstance(revision, str) or re.fullmatch(r"[0-9a-f]{40}", revision) is None:
        raise CoverageError("coverage baseline sourceRevision must be a full Git SHA")
    if not isinstance(coverage, (int, float)) or not 0 <= coverage <= 1:
        raise CoverageError("coverage baseline productionLineCoverage must be between 0 and 1")
    covered = baseline.get("coveredLines")
    executable = baseline.get("executableLines")
    if not isinstance(covered, int) or not isinstance(executable, int):
        raise CoverageError("coverage baseline must record integer coveredLines and executableLines")
    if executable <= 0 or covered < 0 or covered > executable:
        raise CoverageError("coverage baseline line counts are inconsistent")
    if abs(covered / executable - float(coverage)) > 1e-12:
        raise CoverageError("coverage baseline ratio does not match its recorded line counts")
    return baseline


def load_baseline(path: Path) -> dict[str, Any]:
    return validate_baseline(load_json(path, "coverage baseline"))


def is_critical(path: str) -> bool:
    if not path.endswith(".swift"):
        return False
    if path in DATA_ONLY_FILES:
        return False
    if path.startswith(CRITICAL_PREFIXES):
        return True
    if path.startswith("Vitrine/WebRendering/"):
        return Path(path).name in NONVISUAL_WEB_FILES
    return False


def parse_changed_lines(diff: str) -> dict[str, set[int]]:
    changed: dict[str, set[int]] = {}
    current: str | None = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            candidate = line[6:]
            current = candidate if is_critical(candidate) else None
            if current is not None:
                changed.setdefault(current, set())
            continue
        if current is None:
            continue
        match = HUNK_HEADER.match(line)
        if match:
            start = int(match.group(1))
            count = int(match.group(2) or "1")
            changed[current].update(range(start, start + count))
    return {path: lines for path, lines in changed.items() if lines}


def find_report_path(targets: dict[str, Any], relative_path: str) -> str:
    suffix = "/" + relative_path
    candidates: list[str] = []
    for target in targets.values():
        files = target.get("files")
        if not isinstance(files, list):
            raise CoverageError("xccov target JSON has no files array")
        for file in files:
            if isinstance(file, dict) and isinstance(file.get("path"), str):
                file_path = file["path"]
                if file_path.endswith(suffix):
                    candidates.append(file_path)
    if not candidates:
        raise CoverageError(f"xccov report has no production entry for changed file {relative_path}")
    return sorted(candidates, key=lambda value: ("/Vitrine.app/" not in value, len(value)))[0]


def line_counts(archive: Any, report_path: str) -> dict[int, tuple[bool, int]]:
    if not isinstance(archive, dict):
        raise CoverageError(f"xccov archive JSON for {report_path} is not an object")
    records = archive.get(report_path)
    if records is None and len(archive) == 1:
        records = next(iter(archive.values()))
    if not isinstance(records, list):
        raise CoverageError(f"xccov archive JSON has no line records for {report_path}")
    result: dict[int, tuple[bool, int]] = {}
    for record in records:
        if not isinstance(record, dict) or not isinstance(record.get("line"), int):
            raise CoverageError(f"xccov archive contains a malformed line record for {report_path}")
        executable = record.get("isExecutable") is True
        count = record.get("executionCount", 0)
        if not isinstance(count, int) or count < 0:
            raise CoverageError(f"xccov archive contains an invalid execution count for {report_path}")
        result[record["line"]] = (executable, count)
    return result


def changed_line_coverage(
    changed: dict[str, set[int]],
    targets: dict[str, Any],
    archive_loader: Callable[[str], Any],
) -> DiffCoverage:
    executable = 0
    covered = 0
    missed: list[str] = []
    for relative_path, changed_lines in sorted(changed.items()):
        report_path = find_report_path(targets, relative_path)
        counts = line_counts(archive_loader(report_path), report_path)
        for line in sorted(changed_lines):
            is_executable, execution_count = counts.get(line, (False, 0))
            if not is_executable:
                continue
            executable += 1
            if execution_count > 0:
                covered += 1
            else:
                missed.append(f"{relative_path}:{line}")
    return DiffCoverage(covered=covered, executable=executable, missed=tuple(missed))


def self_test() -> None:
    report = {
        "targets": [
            {"name": name, "coveredLines": 8, "executableLines": 10, "files": []}
            for name in sorted(PRODUCTION_TARGETS)
        ]
    }
    assert production_coverage(report)[:3] == (40, 50, 0.8)
    assert is_critical("Vitrine/Models/Theme.swift")
    assert is_critical("VitrineDomain/Models/Theme.swift")
    assert is_critical("VitrineRendering/Rendering/RenderBudget.swift")
    assert is_critical("VitrineRendering/Models/SnapshotConfig.swift")
    assert not is_critical("Vitrine/CLI/CLIUsage.swift")
    assert not is_critical("VitrineRendering/Rendering/CaptureInput.swift")
    assert not is_critical("VitrineRendering/Support/RenderingLog.swift")
    assert not is_critical("VitrineRendering/Canvas/SnapshotCanvas.swift")
    assert not is_critical("VitrineRendering/DesignSystem/BrandMark.swift")
    assert is_critical("Vitrine/WebRendering/PrivateNetworkBlockRules.swift")
    assert is_critical("Vitrine/WebRendering/WebURLValidation.swift")
    assert not is_critical("Vitrine/WebRendering/WebSnapshotEditorView.swift")
    assert not is_critical("Vitrine/Editor/EditorView.swift")
    parsed = parse_changed_lines(
        "diff --git a/Vitrine/Models/A.swift b/Vitrine/Models/A.swift\n"
        "+++ b/Vitrine/Models/A.swift\n@@ -1 +2,3 @@\n"
        "diff --git a/Vitrine/Editor/B.swift b/Vitrine/Editor/B.swift\n"
        "+++ b/Vitrine/Editor/B.swift\n@@ -1 +1 @@\n"
    )
    assert parsed == {"Vitrine/Models/A.swift": {2, 3, 4}}
    source_path = "/checkout/Vitrine/Models/A.swift"
    result = changed_line_coverage(
        parsed,
        {"Vitrine.app": {"files": [{"path": source_path}]}},
        lambda _: {
            source_path: [
                {"line": 2, "isExecutable": True, "executionCount": 1},
                {"line": 3, "isExecutable": False},
                {"line": 4, "isExecutable": True, "executionCount": 0},
            ]
        },
    )
    assert result == DiffCoverage(covered=1, executable=2, missed=("Vitrine/Models/A.swift:4",))
    assert result.ratio == 0.5
    baseline = {
        "schemaVersion": 1,
        "sourceRevision": "a" * 40,
        "productionLineCoverage": 0.8,
        "coveredLines": 8,
        "executableLines": 10,
    }
    assert validate_baseline(baseline)["productionLineCoverage"] == 0.8
    try:
        parse_json("not-json", "fixture")
    except CoverageError:
        pass
    else:
        raise AssertionError("invalid xccov JSON must fail closed")
    print("coverage guard self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--result-bundle", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--repository-root", type=Path, default=Path.cwd())
    parser.add_argument("--base-ref")
    parser.add_argument("--minimum-diff-coverage", type=float, default=0.80)
    parser.add_argument("--maximum-overall-drop-points", type=float, default=1.0)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0
    if args.result_bundle is None or args.baseline is None:
        parser.error("--result-bundle and --baseline are required")
    if not 0 <= args.minimum_diff_coverage <= 1:
        raise CoverageError("minimum diff coverage must be between 0 and 1")

    root = args.repository_root.resolve()
    baseline = load_baseline(args.baseline)
    report_raw = run(
        ["xcrun", "xccov", "view", "--report", "--json", str(args.result_bundle)], root)
    report = parse_json(report_raw, "xccov report")
    covered, executable, ratio, targets = production_coverage(report)
    floor = float(baseline["productionLineCoverage"]) - args.maximum_overall_drop_points / 100
    print(
        f"Production coverage: {covered}/{executable} = {ratio:.2%} "
        f"(baseline {float(baseline['productionLineCoverage']):.2%}, floor {floor:.2%})")
    if ratio + 1e-12 < floor:
        raise CoverageError("production line coverage dropped by more than 1 percentage point")

    base_ref = args.base_ref or baseline["sourceRevision"]
    diff = run(
        ["git", "diff", "--unified=0", "--no-color", "--diff-filter=AMR", f"{base_ref}...HEAD"],
        root,
        require_output=False,
    )
    changed = parse_changed_lines(diff)

    def archive_loader(report_path: str) -> Any:
        raw = run(
            [
                "xcrun",
                "xccov",
                "view",
                "--archive",
                "--file",
                report_path,
                "--json",
                str(args.result_bundle),
            ],
            root,
        )
        return parse_json(raw, f"xccov archive for {report_path}")

    diff_result = changed_line_coverage(changed, targets, archive_loader)
    print(
        f"Critical diff coverage: {diff_result.covered}/{diff_result.executable} "
        f"= {diff_result.ratio:.2%} across {len(changed)} changed files")
    if diff_result.ratio + 1e-12 < args.minimum_diff_coverage:
        sample = ", ".join(diff_result.missed[:20])
        remainder = len(diff_result.missed) - min(len(diff_result.missed), 20)
        if remainder:
            sample += f", and {remainder} more"
        raise CoverageError(
            f"critical changed-line coverage is below {args.minimum_diff_coverage:.0%}; "
            f"uncovered executable lines: {sample}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CoverageError as error:
        print(f"coverage guard failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
