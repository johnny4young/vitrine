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


SCHEMA_VERSION = 3
SUPPORTED_BASELINE_SCHEMAS = {1, 2, SCHEMA_VERSION}
DEFAULT_RUNS = 7
MINIMUM_P95_SAMPLES = 20
DEFAULT_FOUNDATION_INCREMENTAL_FILE = Path("VitrineDomain/Terminal/CharacterWidth.swift")
DEFAULT_MODEL_INCREMENTAL_FILE = Path("VitrineDomain/Models/StyleSnapshot.swift")
DEFAULT_OUTPUT = Path("build/metrics/build-boundaries.json")
DEFAULT_WORK_ROOT = Path("build/BuildBoundaryMetrics")
FOCUSED_TEST_SUITE = "BuildBoundaryProbeTests"
HOST_BACKED_TEST = f"VitrineTests/{FOCUSED_TEST_SUITE}"
HOSTLESS_TEST = f"VitrineDomainTests/{FOCUSED_TEST_SUITE}"
COMPARABLE_ENVIRONMENT_KEYS = (
    "macos",
    "architecture",
    "hardware_model",
    "processor_name",
    "processor_count",
    "memory_bytes",
    "power_source",
    "xcode",
)


@dataclass(frozen=True)
class Measurement:
    label: str
    seconds: float
    command: list[str]
    log: Path


def percentile(values: Sequence[float], fraction: float) -> float:
    """Return a nearest-rank percentile for a non-empty sample."""
    if not values:
        raise ValueError("cannot summarize an empty sample")
    ordered = sorted(values)
    index = max(0, math.ceil(fraction * len(ordered)) - 1)
    return ordered[index]


def summary(values: Sequence[float]) -> dict[str, object]:
    """Produce robust JSON-ready statistics for a metric."""
    if not values:
        raise ValueError("cannot summarize an empty sample")
    median = statistics.median(values)
    result: dict[str, object] = {
        "samples_seconds": [round(value, 3) for value in values],
        "sample_count": len(values),
        "minimum_seconds": round(min(values), 3),
        "median_seconds": round(median, 3),
        "maximum_seconds": round(max(values), 3),
        "median_absolute_deviation_seconds": round(
            statistics.median(abs(value - median) for value in values), 3
        ),
        "p95_seconds": None,
    }
    if len(values) >= MINIMUM_P95_SAMPLES:
        result["p95_seconds"] = round(percentile(values, 0.95), 3)
    return result


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


def optional_output(command: Sequence[str], cwd: Path, env: dict[str, str]) -> str | None:
    """Return command output when metadata is available."""
    try:
        return checked_output(command, cwd, env)
    except (OSError, subprocess.CalledProcessError):
        return None


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
    return Measurement(label, elapsed, list(command), log_path)


def executed_test_count(log: str) -> int:
    """Return the largest XCTest or Swift Testing completion count in a log."""
    counts = [
        int(match)
        for match in re.findall(r"(?:Executed|Test run with) (\d+) tests?", log)
    ]
    return max(counts, default=0)


def require_executed_tests(log_path: Path) -> int:
    count = executed_test_count(
        log_path.read_text(encoding="utf-8", errors="replace")
    )
    if count < 1:
        raise RuntimeError(f"focused test filter executed no tests; see {log_path}")
    return count


def require_matching_test_counts(
    host_backed_counts: Sequence[int], hostless_counts: Sequence[int]
) -> int:
    """Require every focused-test sample to execute the same nonzero workload."""
    if not host_backed_counts or not hostless_counts:
        raise ValueError("focused test counts cannot be empty")
    distinct = set(host_backed_counts) | set(hostless_counts)
    if len(distinct) != 1 or 0 in distinct:
        raise RuntimeError(
            "focused test workloads differ: "
            f"app-hosted={list(host_backed_counts)}, hostless={list(hostless_counts)}"
        )
    return distinct.pop()


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
    scheme: str = "Vitrine",
    extra: Sequence[str] = (),
) -> list[str]:
    return [
        "xcodebuild",
        "-project",
        "Vitrine.xcodeproj",
        "-scheme",
        scheme,
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


def require_self_test(condition: bool, label: str) -> None:
    """Raise a runtime error when a helper invariant does not hold."""
    if not condition:
        raise RuntimeError(f"build-boundary self-test failed: {label}")


def run_self_test() -> int:
    require_self_test(percentile([1.0], 0.95) == 1.0, "single-value percentile")
    require_self_test(
        percentile([3.0, 1.0, 2.0], 0.5) == 2.0, "median percentile"
    )
    require_self_test(
        percentile([3.0, 1.0, 2.0], 0.95) == 3.0, "nearest-rank percentile"
    )
    require_self_test(
        summary([2.0, 1.0, 4.0])
        == {
            "samples_seconds": [2.0, 1.0, 4.0],
            "sample_count": 3,
            "minimum_seconds": 1.0,
            "median_seconds": 2.0,
            "maximum_seconds": 4.0,
            "median_absolute_deviation_seconds": 1.0,
            "p95_seconds": None,
        },
        "metric summary",
    )
    require_self_test(
        summary([float(value) for value in range(1, 21)])["p95_seconds"] == 19.0,
        "p95 sample threshold",
    )
    require_self_test(
        reduction_percent(10.0, 7.5) == 25.0, "reduction percentage"
    )
    require_self_test(
        compare_metric_reports(
            {"build": {"median_seconds": 10.0}},
            {"build": {"median_seconds": 8.0}},
        )
        == {
            "build": {
                "baseline_median_seconds": 10.0,
                "candidate_median_seconds": 8.0,
                "reduction_percent": 20.0,
            }
        },
        "report comparison",
    )
    require_self_test(
        environment_mismatches(
            {"macos": "26.5", "architecture": "arm64"},
            {"macos": "26.6", "architecture": "arm64"},
        )
        == ["macos"],
        "environment mismatch",
    )
    require_self_test(
        executed_test_count("Executed 4 tests\nTest run with 0 tests") == 4,
        "nonzero test count",
    )
    require_self_test(executed_test_count("unrelated output") == 0, "zero test count")
    require_self_test(
        require_matching_test_counts([4, 4], [4, 4]) == 4,
        "matching test counts",
    )
    require_self_test(
        build_timing_summary(
            "Build Timing Summary\n\nSwiftCompile (47 tasks) | 103.831 seconds\n"
        )
        == {
            "SwiftCompile": {
                "task_count": 47,
                "aggregate_seconds": 103.831,
            }
        },
        "build timing summary",
    )
    try:
        summary([])
    except ValueError:
        pass
    else:
        raise RuntimeError("build-boundary self-test failed: empty samples must fail")
    try:
        require_matching_test_counts([4], [3])
    except RuntimeError:
        pass
    else:
        raise RuntimeError(
            "build-boundary self-test failed: mismatched test counts must fail"
        )
    print("Build-boundary metric helpers passed.")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--runs",
        type=int,
        default=DEFAULT_RUNS,
        help=f"number of samples per measured operation (default: {DEFAULT_RUNS})",
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
        "--foundation-incremental-file",
        type=Path,
        default=DEFAULT_FOUNDATION_INCREMENTAL_FILE,
        help="low-fan-out Foundation source used for incremental builds",
    )
    parser.add_argument(
        "--incremental-file",
        type=Path,
        default=DEFAULT_MODEL_INCREMENTAL_FILE,
        help="high-fan-out model source used for incremental builds",
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
        "--allow-ineligible-baseline",
        action="store_true",
        help="compare a dirty or undersampled report that is not baseline-eligible",
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
    incremental_paths = [
        ("--foundation-incremental-file", arguments.foundation_incremental_file),
        ("--incremental-file", arguments.incremental_file),
    ]
    resolved_paths: list[Path] = []
    for label, configured_path in incremental_paths:
        path = (root / configured_path).resolve()
        try:
            path.relative_to(root)
        except ValueError as error:
            raise ValueError(f"{label} must stay inside the repository") from error
        if not path.is_file() or path.suffix != ".swift":
            raise ValueError(f"{label} must name an existing Swift source")
        resolved_paths.append(path)
    if len(set(resolved_paths)) != len(resolved_paths):
        raise ValueError("incremental scenarios must use different source files")


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
    *,
    root: Path,
    cache: Path,
    derived_data: Path,
    env: dict[str, str],
    log_path: Path,
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
            "-derivedDataPath",
            str(derived_data),
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
    memory = optional_output(["sysctl", "-n", "hw.memsize"], root, env)
    power = optional_output(["pmset", "-g", "batt"], root, env)
    power_match = re.search(r"Now drawing from '([^']+)'", power or "")
    return {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "commit": git_output(root, "rev-parse", "HEAD"),
        "branch": git_output(root, "branch", "--show-current"),
        "working_tree_clean": not bool(status),
        "macos": platform.mac_ver()[0],
        "architecture": platform.machine(),
        "hardware_model": optional_output(["sysctl", "-n", "hw.model"], root, env),
        "processor_name": optional_output(
            ["sysctl", "-n", "machdep.cpu.brand_string"], root, env
        ),
        "processor_count": os.cpu_count(),
        "memory_bytes": int(memory) if memory and memory.isdigit() else None,
        "power_source": power_match.group(1) if power_match else None,
        "xcode": xcode_version,
        "python": platform.python_version(),
    }


def measure(arguments: argparse.Namespace) -> dict[str, object]:
    root = Path(__file__).resolve().parent.parent
    validate_inputs(arguments, root)
    env = developer_environment()
    output = (root / arguments.output).resolve()
    work_root = (root / arguments.work_root).resolve()
    foundation_incremental_file = (
        root / arguments.foundation_incremental_file
    ).resolve()
    model_incremental_file = (root / arguments.incremental_file).resolve()
    incremental_scenarios = [
        ("foundation", foundation_incremental_file),
        ("model", model_incremental_file),
    ]
    baseline_report: dict[str, object] | None = None
    environment = machine_metadata(root, env)
    environment["baseline_eligible"] = bool(environment["working_tree_clean"]) and (
        arguments.runs >= DEFAULT_RUNS
    )

    validate_generated_paths(root, output, work_root)
    if arguments.baseline:
        baseline_path = (root / arguments.baseline).resolve()
        if not baseline_path.is_file():
            raise ValueError("--baseline must name an existing JSON report")
        loaded = json.loads(baseline_path.read_text(encoding="utf-8"))
        if (
            not isinstance(loaded, dict)
            or loaded.get("schema_version") not in SUPPORTED_BASELINE_SCHEMAS
        ):
            versions = ", ".join(
                str(version) for version in sorted(SUPPORTED_BASELINE_SCHEMAS)
            )
            raise ValueError(
                f"--baseline must use build-boundary schema version {versions}"
            )
        baseline_report = loaded
        baseline_environment = baseline_report.get("environment")
        if not isinstance(baseline_environment, dict):
            raise ValueError("--baseline report is missing environment provenance")
        if (
            baseline_environment.get("baseline_eligible") is not True
            and not arguments.allow_ineligible_baseline
        ):
            raise ValueError(
                "baseline report is dirty or undersampled; generate at least "
                f"{DEFAULT_RUNS} samples from a clean commit or pass "
                "--allow-ineligible-baseline"
            )
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
    package_resolution_derived_data = work_root / "PackageResolutionDerivedData"
    preparation = prepare_packages(
        root=root,
        cache=package_cache,
        derived_data=package_resolution_derived_data,
        env=env,
        log_path=work_root / "logs" / "package-resolution.log",
    )
    samples: dict[str, list[Measurement]] = {
        "clean_build": [],
        "no_op_build": [],
        "incremental_foundation_build": [],
        "incremental_model_build": [],
        "host_backed_test_build": [],
        "host_backed_test_startup": [],
        "domain_test_build": [],
        "domain_test_startup": [],
    }
    original_stats = {
        path: path.stat() for _, path in incremental_scenarios
    }
    host_backed_test_counts: list[int] = []
    hostless_test_counts: list[int] = []

    try:
        for index in range(1, arguments.runs + 1):
            app_derived_data = work_root / f"AppDerivedData-{index}"
            host_backed_derived_data = work_root / f"HostedTestDerivedData-{index}"
            hostless_derived_data = work_root / f"HostlessDerivedData-{index}"
            for disposable_path in [
                app_derived_data,
                host_backed_derived_data,
                hostless_derived_data,
            ]:
                shutil.rmtree(disposable_path, ignore_errors=True)
            log_dir = work_root / "logs" / f"run-{index}"

            samples["clean_build"].append(
                run_timed(
                    label=f"Clean app build {index}/{arguments.runs}",
                    command=xcode_command(
                        derived_data=app_derived_data,
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
                        derived_data=app_derived_data,
                        package_cache=package_cache,
                        action="build",
                    ),
                    cwd=root,
                    env=env,
                    log_path=log_dir / "no-op-build.log",
                )
            )

            ordered_scenarios = (
                incremental_scenarios
                if index % 2 == 1
                else list(reversed(incremental_scenarios))
            )
            for scenario, incremental_file in ordered_scenarios:
                os.utime(incremental_file, None)
                samples[f"incremental_{scenario}_build"].append(
                    run_timed(
                        label=(
                            f"Incremental {scenario} build "
                            f"{index}/{arguments.runs}"
                        ),
                        command=xcode_command(
                            derived_data=app_derived_data,
                            package_cache=package_cache,
                            action="build",
                        ),
                        cwd=root,
                        env=env,
                        log_path=log_dir / f"incremental-{scenario}-build.log",
                    )
                )
                original_stat = original_stats[incremental_file]
                os.utime(
                    incremental_file,
                    ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns),
                )

            samples["host_backed_test_build"].append(
                run_timed(
                    label=f"Clean app-hosted test build {index}/{arguments.runs}",
                    command=xcode_command(
                        derived_data=host_backed_derived_data,
                        package_cache=package_cache,
                        action="build-for-testing",
                        scheme="VitrineHostedProbe",
                        extra=[f"-only-testing:{HOST_BACKED_TEST}"],
                    ),
                    cwd=root,
                    env=env,
                    log_path=log_dir / "host-backed-test-build.log",
                )
            )
            host_backed_log = log_dir / "host-backed-test-startup.log"
            samples["host_backed_test_startup"].append(
                run_timed(
                    label=f"App-hosted focused test {index}/{arguments.runs}",
                    command=xcode_command(
                        derived_data=host_backed_derived_data,
                        package_cache=package_cache,
                        action="test-without-building",
                        scheme="VitrineHostedProbe",
                        extra=[f"-only-testing:{HOST_BACKED_TEST}"],
                    ),
                    cwd=root,
                    env=env,
                    log_path=host_backed_log,
                )
            )
            host_backed_test_counts.append(require_executed_tests(host_backed_log))

            samples["domain_test_build"].append(
                run_timed(
                    label=f"Clean hostless test build {index}/{arguments.runs}",
                    command=xcode_command(
                        derived_data=hostless_derived_data,
                        package_cache=package_cache,
                        action="build-for-testing",
                        scheme="VitrineDomain",
                        extra=[f"-only-testing:{HOSTLESS_TEST}"],
                    ),
                    cwd=root,
                    env=env,
                    log_path=log_dir / "hostless-test-build.log",
                )
            )
            hostless_log = log_dir / "hostless-test-startup.log"
            samples["domain_test_startup"].append(
                run_timed(
                    label=f"Hostless focused test {index}/{arguments.runs}",
                    command=xcode_command(
                        derived_data=hostless_derived_data,
                        package_cache=package_cache,
                        action="test-without-building",
                        scheme="VitrineDomain",
                        extra=[f"-only-testing:{HOSTLESS_TEST}"],
                    ),
                    cwd=root,
                    env=env,
                    log_path=hostless_log,
                )
            )
            hostless_test_counts.append(require_executed_tests(hostless_log))

            if not arguments.keep_derived_data:
                for disposable_path in [
                    app_derived_data,
                    host_backed_derived_data,
                    hostless_derived_data,
                ]:
                    shutil.rmtree(disposable_path, ignore_errors=True)
    finally:
        for incremental_file, original_stat in original_stats.items():
            os.utime(
                incremental_file,
                ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns),
            )

    focused_test_count = require_matching_test_counts(
        host_backed_test_counts, hostless_test_counts
    )

    metrics = {
        name: summary([measurement.seconds for measurement in measurements])
        for name, measurements in samples.items()
    }
    clean_build_timings = [
        build_timing_summary(
            measurement.log.read_text(encoding="utf-8", errors="replace")
        )
        for measurement in samples["clean_build"]
    ]
    host_backed_startup = metrics["host_backed_test_startup"]["median_seconds"]
    hostless_startup = metrics["domain_test_startup"]["median_seconds"]
    host_backed_build = metrics["host_backed_test_build"]["median_seconds"]
    hostless_build = metrics["domain_test_build"]["median_seconds"]
    comparisons = {
        "focused_test_count": focused_test_count,
        "domain_test_build_reduction_percent": reduction_percent(
            float(host_backed_build), float(hostless_build)
        ),
        "domain_test_build_saved_seconds": round(
            float(host_backed_build) - float(hostless_build), 3
        ),
        "domain_test_startup_reduction_percent": reduction_percent(
            float(host_backed_startup), float(hostless_startup)
        ),
        "domain_test_startup_saved_seconds": round(
            float(host_backed_startup) - float(hostless_startup), 3
        ),
    }
    report: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "environment": environment,
        "configuration": {
            "runs": arguments.runs,
            "minimum_p95_samples": MINIMUM_P95_SAMPLES,
            "incremental_files": {
                "foundation": str(arguments.foundation_incremental_file),
                "model": str(arguments.incremental_file),
            },
            "incremental_order": "alternating",
            "project": "Vitrine.xcodeproj",
            "scheme": "Vitrine",
            "configuration": "Debug",
            "destination": "platform=macOS",
            "focused_test_source": "Tests/BuildBoundaryProbeTests.swift",
            "host_backed_test": HOST_BACKED_TEST,
            "domain_test": HOSTLESS_TEST,
            "domain_probe_sources": [
                "VitrineDomain/Terminal/ANSIParser.swift",
                "VitrineDomain/Terminal/CharacterWidth.swift",
                "VitrineDomain/Terminal/TerminalGrid.swift",
            ],
        },
        "preparation": {
            "package_resolution_seconds": round(preparation.seconds, 3),
            "package_resolution_log": str(preparation.log.relative_to(root)),
        },
        "metrics": metrics,
        "clean_build_task_timings": clean_build_timings,
        "test_counts": {
            "app_hosted": host_backed_test_counts,
            "hostless": hostless_test_counts,
        },
        "comparisons": comparisons,
        "logs_directory": str((work_root / "logs").relative_to(root)),
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
    try:
        if arguments.self_test:
            return run_self_test()
        measure(arguments)
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
