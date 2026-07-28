#!/usr/bin/env python3
"""Measure Vitrine build and test boundaries without mutating tracked content."""

from __future__ import annotations

import argparse
import json
import math
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Sequence


DEFAULT_INCREMENTAL_FILE = Path("Vitrine/Models/SnapshotConfig.swift")
DEFAULT_OUTPUT = Path("build/metrics/build-boundaries.json")
DEFAULT_WORK_ROOT = Path("build/BuildBoundaryMetrics")
HOST_BACKED_TEST = "VitrineTests/ModelTests"
COMPARABLE_ENVIRONMENT_KEYS = ("macos", "architecture", "processor_count", "xcode")


@dataclass(frozen=True)
class Measurement:
    label: str
    seconds: float
    command: list[str]
    log: str


def percentile(values: Sequence[float], fraction: float) -> float:
    """Return a nearest-rank percentile for a non-empty sample."""
    if not values:
        raise ValueError("cannot summarize an empty sample")
    ordered = sorted(values)
    index = max(0, math.ceil(fraction * len(ordered)) - 1)
    return ordered[index]


def summary(values: Sequence[float]) -> dict[str, object]:
    """Produce stable JSON-ready statistics for a metric."""
    if not values:
        raise ValueError("cannot summarize an empty sample")
    return {
        "samples_seconds": [round(value, 3) for value in values],
        "median_seconds": round(statistics.median(values), 3),
        "p95_seconds": round(percentile(values, 0.95), 3),
    }


def reduction_percent(baseline: float, candidate: float) -> float:
    """Return the percentage by which candidate is lower than baseline."""
    if baseline <= 0:
        raise ValueError("baseline must be positive")
    return round((baseline - candidate) / baseline * 100, 1)


def compare_metric_reports(
    baseline_metrics: dict[str, object], candidate_metrics: dict[str, object]
) -> dict[str, dict[str, float]]:
    """Compare medians shared by two schema-compatible metric maps."""
    comparison: dict[str, dict[str, float]] = {}
    for name in sorted(set(baseline_metrics) & set(candidate_metrics)):
        baseline = baseline_metrics[name]
        candidate = candidate_metrics[name]
        if not isinstance(baseline, dict) or not isinstance(candidate, dict):
            continue
        baseline_median = baseline.get("median_seconds")
        candidate_median = candidate.get("median_seconds")
        if not isinstance(baseline_median, (int, float)) or not isinstance(
            candidate_median, (int, float)
        ):
            continue
        comparison[name] = {
            "baseline_median_seconds": float(baseline_median),
            "candidate_median_seconds": float(candidate_median),
            "reduction_percent": reduction_percent(
                float(baseline_median), float(candidate_median)
            ),
        }
    if not comparison:
        raise ValueError("baseline report has no compatible metrics")
    return comparison


def environment_mismatches(
    baseline: dict[str, object], candidate: dict[str, object]
) -> list[str]:
    """Return environment fields that make timing comparisons unreliable."""
    return [
        key
        for key in COMPARABLE_ENVIRONMENT_KEYS
        if baseline.get(key) != candidate.get(key)
    ]


def checked_output(command: Sequence[str], cwd: Path, env: dict[str, str]) -> str:
    completed = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return completed.stdout.strip()


def run_timed(
    *,
    label: str,
    command: Sequence[str],
    cwd: Path,
    env: dict[str, str],
    log_path: Path,
) -> Measurement:
    """Run one command, preserving complete output and wall-clock duration."""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"==> {label}", flush=True)
    print("    " + " ".join(command), flush=True)
    started = time.perf_counter()
    with log_path.open("w", encoding="utf-8") as log:
        completed = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
        )
    elapsed = time.perf_counter() - started
    if completed.returncode != 0:
        raise RuntimeError(
            f"{label} failed with exit code {completed.returncode}; see {log_path}"
        )
    print(f"    {elapsed:.3f}s", flush=True)
    return Measurement(label, elapsed, list(command), str(log_path))


def executed_test_count(log: str) -> int:
    """Return the largest XCTest or Swift Testing completion count in a log."""
    counts = [
        int(match)
        for match in re.findall(r"(?:Executed|Test run with) (\d+) tests?", log)
    ]
    return max(counts, default=0)


def require_executed_tests(log_path: Path) -> None:
    if executed_test_count(log_path.read_text(encoding="utf-8", errors="replace")) < 1:
        raise RuntimeError(f"focused test filter executed no tests; see {log_path}")


def build_timing_summary(log: str) -> dict[str, dict[str, float | int]]:
    """Parse xcodebuild's aggregate task timing table."""
    timings: dict[str, dict[str, float | int]] = {}
    for name, tasks, seconds in re.findall(
        r"^(.+?) \((\d+) tasks?\) \| ([0-9.]+) seconds$",
        log,
        flags=re.MULTILINE,
    ):
        timings[name] = {
            "task_count": int(tasks),
            "aggregate_seconds": float(seconds),
        }
    return timings


def git_output(root: Path, *arguments: str) -> str:
    return subprocess.run(
        ["git", *arguments],
        cwd=root,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ).stdout.strip()


def developer_environment() -> dict[str, str]:
    env = dict(os.environ)
    if "DEVELOPER_DIR" not in env:
        default = Path("/Applications/Xcode.app/Contents/Developer")
        if default.is_dir():
            env["DEVELOPER_DIR"] = str(default)
    return env


def xcode_command(
    *,
    derived_data: Path,
    package_cache: Path,
    action: str,
    extra: Sequence[str] = (),
) -> list[str]:
    return [
        "xcodebuild",
        "-project",
        "Vitrine.xcodeproj",
        "-scheme",
        "Vitrine",
        "-configuration",
        "Debug",
        "-destination",
        "platform=macOS",
        "-derivedDataPath",
        str(derived_data),
        "-clonedSourcePackagesDirPath",
        str(package_cache),
        "-disableAutomaticPackageResolution",
        "CODE_SIGNING_ALLOWED=NO",
        "-showBuildTimingSummary",
        *extra,
        action,
    ]


def create_hostless_probe(root: Path, destination: Path) -> None:
    """Create a temporary package over representative Foundation-only code."""
    sources = destination / "Sources" / "VitrineCoreProbe"
    tests = destination / "Tests" / "VitrineCoreProbeTests"
    sources.mkdir(parents=True, exist_ok=True)
    tests.mkdir(parents=True, exist_ok=True)

    for relative in [
        Path("Vitrine/Terminal/ANSIParser.swift"),
        Path("Vitrine/Terminal/CharacterWidth.swift"),
        Path("Vitrine/Terminal/TerminalGrid.swift"),
    ]:
        shutil.copy2(root / relative, sources / relative.name)

    (destination / "Package.swift").write_text(
        """// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VitrineCoreProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "VitrineCoreProbe"),
        .testTarget(name: "VitrineCoreProbeTests", dependencies: ["VitrineCoreProbe"]),
    ]
)
""",
        encoding="utf-8",
    )
    (tests / "HostlessProbeTests.swift").write_text(
        """import XCTest

@testable import VitrineCoreProbe

final class HostlessProbeTests: XCTestCase {
    func testDetectsANSI() {
        XCTAssertTrue(ANSIParser.containsANSI("\\u{1B}[32mok"))
    }

    func testParsesStyledText() {
        XCTAssertEqual(ANSIParser.parse("\\u{1B}[32mok\\u{1B}[0m").map(\\.text), ["ok"])
    }

    func testWideCharacterWidth() {
        XCTAssertEqual(CharacterWidth.displayWidth("界".unicodeScalars.first!), 2)
    }

    func testCombiningCharacterWidth() {
        XCTAssertEqual(CharacterWidth.displayWidth("\\u{0301}".unicodeScalars.first!), 0)
    }
}
""",
        encoding="utf-8",
    )


def run_self_test() -> int:
    assert percentile([1.0], 0.95) == 1.0
    assert percentile([3.0, 1.0, 2.0], 0.5) == 2.0
    assert percentile([3.0, 1.0, 2.0], 0.95) == 3.0
    assert summary([2.0, 1.0, 4.0]) == {
        "samples_seconds": [2.0, 1.0, 4.0],
        "median_seconds": 2.0,
        "p95_seconds": 4.0,
    }
    assert reduction_percent(10.0, 7.5) == 25.0
    assert compare_metric_reports(
        {"build": {"median_seconds": 10.0}},
        {"build": {"median_seconds": 8.0}},
    ) == {
        "build": {
            "baseline_median_seconds": 10.0,
            "candidate_median_seconds": 8.0,
            "reduction_percent": 20.0,
        }
    }
    assert environment_mismatches(
        {"macos": "26.5", "architecture": "arm64"},
        {"macos": "26.6", "architecture": "arm64"},
    ) == ["macos"]
    assert executed_test_count("Executed 4 tests\nTest run with 0 tests") == 4
    assert executed_test_count("unrelated output") == 0
    assert build_timing_summary(
        "Build Timing Summary\n\nSwiftCompile (47 tasks) | 103.831 seconds\n"
    ) == {
        "SwiftCompile": {
            "task_count": 47,
            "aggregate_seconds": 103.831,
        }
    }
    try:
        summary([])
    except ValueError:
        pass
    else:
        raise AssertionError("empty samples must fail")
    print("Build-boundary metric helpers passed.")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--runs",
        type=int,
        default=3,
        help="number of samples per measured operation (default: 3)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"JSON report path (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--work-root",
        type=Path,
        default=DEFAULT_WORK_ROOT,
        help=f"ignored working directory (default: {DEFAULT_WORK_ROOT})",
    )
    parser.add_argument(
        "--incremental-file",
        type=Path,
        default=DEFAULT_INCREMENTAL_FILE,
        help="source file whose timestamp triggers the representative incremental build",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        help="previous JSON report whose medians are compared with this run",
    )
    parser.add_argument(
        "--allow-environment-mismatch",
        action="store_true",
        help="compare a baseline from a different machine/toolchain despite timing drift",
    )
    parser.add_argument(
        "--keep-derived-data",
        action="store_true",
        help="retain temporary DerivedData directories after measurement",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="validate metric helpers without invoking Xcode",
    )
    return parser.parse_args()


def validate_inputs(arguments: argparse.Namespace, root: Path) -> None:
    if arguments.runs < 1:
        raise ValueError("--runs must be at least 1")
    incremental_file = (root / arguments.incremental_file).resolve()
    try:
        incremental_file.relative_to(root)
    except ValueError as error:
        raise ValueError("--incremental-file must stay inside the repository") from error
    if not incremental_file.is_file() or incremental_file.suffix != ".swift":
        raise ValueError("--incremental-file must name an existing Swift source")


def validate_generated_paths(root: Path, output: Path, work_root: Path) -> None:
    """Keep recursive cleanup and generated reports inside the ignored build tree."""
    build_root = (root / "build").resolve()
    for label, path in [("--work-root", work_root), ("--output", output)]:
        try:
            path.relative_to(build_root)
        except ValueError as error:
            raise ValueError(f"{label} must stay inside {build_root}") from error
    if work_root == build_root:
        raise ValueError("--work-root must be a child of the build directory")
    if output.suffix != ".json":
        raise ValueError("--output must name a JSON file")


def prepare_packages(
    *, root: Path, cache: Path, env: dict[str, str], log_path: Path
) -> Measurement:
    cache.mkdir(parents=True, exist_ok=True)
    return run_timed(
        label="Resolve exact package dependencies",
        command=[
            "xcodebuild",
            "-resolvePackageDependencies",
            "-project",
            "Vitrine.xcodeproj",
            "-scheme",
            "Vitrine",
            "-clonedSourcePackagesDirPath",
            str(cache),
        ],
        cwd=root,
        env=env,
        log_path=log_path,
    )


def machine_metadata(root: Path, env: dict[str, str]) -> dict[str, object]:
    status = git_output(root, "status", "--porcelain")
    xcode_version = checked_output(["xcodebuild", "-version"], root, env).splitlines()
    return {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "commit": git_output(root, "rev-parse", "HEAD"),
        "branch": git_output(root, "branch", "--show-current"),
        "working_tree_clean": not bool(status),
        "macos": platform.mac_ver()[0],
        "architecture": platform.machine(),
        "processor_count": os.cpu_count(),
        "xcode": xcode_version,
        "python": platform.python_version(),
    }


def measure(arguments: argparse.Namespace) -> dict[str, object]:
    root = Path(__file__).resolve().parent.parent
    validate_inputs(arguments, root)
    env = developer_environment()
    output = (root / arguments.output).resolve()
    work_root = (root / arguments.work_root).resolve()
    incremental_file = (root / arguments.incremental_file).resolve()
    baseline_report: dict[str, object] | None = None
    environment = machine_metadata(root, env)

    validate_generated_paths(root, output, work_root)
    if arguments.baseline:
        baseline_path = (root / arguments.baseline).resolve()
        if not baseline_path.is_file():
            raise ValueError("--baseline must name an existing JSON report")
        loaded = json.loads(baseline_path.read_text(encoding="utf-8"))
        if not isinstance(loaded, dict) or loaded.get("schema_version") != 1:
            raise ValueError("--baseline must use build-boundary schema version 1")
        baseline_report = loaded
        baseline_environment = baseline_report.get("environment")
        if not isinstance(baseline_environment, dict):
            raise ValueError("--baseline report is missing environment provenance")
        mismatches = environment_mismatches(baseline_environment, environment)
        if mismatches and not arguments.allow_environment_mismatch:
            fields = ", ".join(mismatches)
            raise ValueError(
                "baseline environment differs in "
                f"{fields}; rerun on the same machine/toolchain or pass "
                "--allow-environment-mismatch"
            )
    if work_root.exists():
        shutil.rmtree(work_root)
    work_root.mkdir(parents=True)
    output.parent.mkdir(parents=True, exist_ok=True)

    package_cache = work_root / "SourcePackages"
    preparation = prepare_packages(
        root=root,
        cache=package_cache,
        env=env,
        log_path=work_root / "logs" / "package-resolution.log",
    )

    samples: dict[str, list[Measurement]] = {
        "clean_build": [],
        "no_op_build": [],
        "incremental_build": [],
        "host_backed_test_startup": [],
        "hostless_test_startup": [],
    }
    original_stat = incremental_file.stat()

    try:
        for index in range(1, arguments.runs + 1):
            derived_data = work_root / f"DerivedData-{index}"
            shutil.rmtree(derived_data, ignore_errors=True)
            log_dir = work_root / "logs" / f"run-{index}"

            samples["clean_build"].append(
                run_timed(
                    label=f"Clean app build {index}/{arguments.runs}",
                    command=xcode_command(
                        derived_data=derived_data,
                        package_cache=package_cache,
                        action="build",
                    ),
                    cwd=root,
                    env=env,
                    log_path=log_dir / "clean-build.log",
                )
            )
            samples["no_op_build"].append(
                run_timed(
                    label=f"No-op app build {index}/{arguments.runs}",
                    command=xcode_command(
                        derived_data=derived_data,
                        package_cache=package_cache,
                        action="build",
                    ),
                    cwd=root,
                    env=env,
                    log_path=log_dir / "no-op-build.log",
                )
            )

            os.utime(incremental_file, None)
            samples["incremental_build"].append(
                run_timed(
                    label=f"Incremental model build {index}/{arguments.runs}",
                    command=xcode_command(
                        derived_data=derived_data,
                        package_cache=package_cache,
                        action="build",
                    ),
                    cwd=root,
                    env=env,
                    log_path=log_dir / "incremental-build.log",
                )
            )
            os.utime(
                incremental_file,
                ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns),
            )

            run_timed(
                label=f"Prepare app-hosted test bundle {index}/{arguments.runs}",
                command=xcode_command(
                    derived_data=derived_data,
                    package_cache=package_cache,
                    action="build-for-testing",
                    extra=[f"-only-testing:{HOST_BACKED_TEST}"],
                ),
                cwd=root,
                env=env,
                log_path=log_dir / "prepare-host-backed-test.log",
            )
            host_backed_log = log_dir / "host-backed-test.log"
            samples["host_backed_test_startup"].append(
                run_timed(
                    label=f"App-hosted focused test {index}/{arguments.runs}",
                    command=xcode_command(
                        derived_data=derived_data,
                        package_cache=package_cache,
                        action="test-without-building",
                        extra=[f"-only-testing:{HOST_BACKED_TEST}"],
                    ),
                    cwd=root,
                    env=env,
                    log_path=host_backed_log,
                )
            )
            require_executed_tests(host_backed_log)

            if not arguments.keep_derived_data:
                shutil.rmtree(derived_data, ignore_errors=True)
    finally:
        os.utime(
            incremental_file,
            ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns),
        )

    probe = work_root / "HostlessProbe"
    create_hostless_probe(root, probe)
    scratch = probe / ".build"
    run_timed(
        label="Prepare hostless focused test",
        command=[
            "xcrun",
            "swift",
            "test",
            "--package-path",
            str(probe),
            "--scratch-path",
            str(scratch),
            "--filter",
            "HostlessProbeTests",
        ],
        cwd=root,
        env=env,
        log_path=work_root / "logs" / "prepare-hostless-test.log",
    )
    for index in range(1, arguments.runs + 1):
        hostless_log = work_root / "logs" / f"hostless-test-{index}.log"
        samples["hostless_test_startup"].append(
            run_timed(
                label=f"Hostless focused test {index}/{arguments.runs}",
                command=[
                    "xcrun",
                    "swift",
                    "test",
                    "--package-path",
                    str(probe),
                    "--scratch-path",
                    str(scratch),
                    "--skip-build",
                    "--filter",
                    "HostlessProbeTests",
                ],
                cwd=root,
                env=env,
                log_path=hostless_log,
            )
        )
        require_executed_tests(hostless_log)

    metrics = {
        name: summary([measurement.seconds for measurement in measurements])
        for name, measurements in samples.items()
    }
    clean_build_timings = [
        build_timing_summary(
            Path(measurement.log).read_text(encoding="utf-8", errors="replace")
        )
        for measurement in samples["clean_build"]
    ]
    host_backed = metrics["host_backed_test_startup"]["median_seconds"]
    hostless = metrics["hostless_test_startup"]["median_seconds"]
    comparisons = {
        "hostless_test_startup_reduction_percent": reduction_percent(
            float(host_backed), float(hostless)
        ),
        "hostless_test_startup_saved_seconds": round(
            float(host_backed) - float(hostless), 3
        ),
    }
    report: dict[str, object] = {
        "schema_version": 1,
        "environment": environment,
        "configuration": {
            "runs": arguments.runs,
            "incremental_file": str(arguments.incremental_file),
            "project": "Vitrine.xcodeproj",
            "scheme": "Vitrine",
            "configuration": "Debug",
            "destination": "platform=macOS",
            "host_backed_test": HOST_BACKED_TEST,
            "hostless_probe_sources": [
                "Vitrine/Terminal/ANSIParser.swift",
                "Vitrine/Terminal/CharacterWidth.swift",
                "Vitrine/Terminal/TerminalGrid.swift",
            ],
        },
        "preparation": {
            "package_resolution_seconds": round(preparation.seconds, 3),
            "package_resolution_log": preparation.log,
        },
        "metrics": metrics,
        "clean_build_task_timings": clean_build_timings,
        "comparisons": comparisons,
        "logs_directory": str(work_root / "logs"),
    }
    if baseline_report is not None:
        baseline_metrics = baseline_report.get("metrics")
        if not isinstance(baseline_metrics, dict):
            raise ValueError("--baseline report is missing metrics")
        report["baseline_comparison"] = compare_metric_reports(
            baseline_metrics, metrics
        )
        report["baseline_environment"] = baseline_report.get("environment")
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"\nReport: {output}")
    return report


def main() -> int:
    arguments = parse_arguments()
    if arguments.self_test:
        return run_self_test()
    try:
        measure(arguments)
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
