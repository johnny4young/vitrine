#!/usr/bin/env python3
"""Capture reproducible, reviewable dynamic-memory evidence for Vitrine."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Sequence


SCHEMA_VERSION = 2
DEFAULT_OUTPUT = Path("build/memory-smoke")
DEFAULT_JOURNEY = "editor-snapshot"
JOURNEYS = {
    "editor-snapshot": {
        "label": "editor snapshot loop",
        "arguments": ["--open-editor", "--snapshot-loop"],
        "completion_marker": "VITRINE_MEMORY_EDITOR_SNAPSHOT_COMPLETE",
        "default_iterations": 14,
    },
    "image-import-cycle": {
        "label": "foreground image import and decode cycle",
        "arguments": ["--memory-image-cycle"],
        "completion_marker": "VITRINE_MEMORY_IMAGE_CYCLE_COMPLETE",
        "default_iterations": 36,
    },
    "window-churn": {
        "label": "editor window open, render, and close cycles",
        "arguments": ["--memory-window-churn"],
        "completion_marker": "VITRINE_MEMORY_WINDOW_CHURN_COMPLETE",
        "default_iterations": 20,
    },
    "web-snapshot-cycle": {
        "label": "real local-HTML WebKit session cycles",
        "arguments": ["--memory-web-snapshot-cycle"],
        "completion_marker": "VITRINE_MEMORY_WEB_SNAPSHOT_CYCLE_COMPLETE",
        "default_iterations": 10,
    },
    "large-document-cycle": {
        "label": "large-document publish, render, and teardown cycles",
        "arguments": ["--memory-large-document-cycle"],
        "completion_marker": "VITRINE_MEMORY_LARGE_DOCUMENT_CYCLE_COMPLETE",
        "default_iterations": 20,
    },
}
APP_FRAME_MARKER = "Vitrine.debug.dylib"
ROOT_STACK_PATTERN = re.compile(
    r"^STACK OF (?P<count>\d+) INSTANCES? OF '(?P<header>.*)':$"
)
QUANTITY_PATTERN = re.compile(r"^(?P<value>\d+(?:\.\d+)?)(?P<unit>[KMGT]?)$")
SAMPLE_PATTERN = re.compile(
    r"^VITRINE_MEMORY_SAMPLE journey=(?P<journey>[a-z-]+) "
    r"iteration=(?P<iteration>\d+) physical-footprint-bytes=(?P<bytes>\d+)$",
    re.MULTILINE,
)


def checked_output(command: Sequence[str], root: Path) -> str:
    return subprocess.run(
        command,
        cwd=root,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    ).stdout.strip()


def optional_output(command: Sequence[str], root: Path) -> str | None:
    try:
        return checked_output(command, root)
    except (OSError, subprocess.CalledProcessError):
        return None


def approximate_bytes(quantity: str) -> int:
    """Convert the compact quantities printed by leaks into approximate bytes."""
    match = QUANTITY_PATTERN.fullmatch(quantity.strip())
    if match is None:
        raise ValueError(f"unrecognized leaks quantity: {quantity}")
    multiplier = {
        "": 1,
        "K": 1024,
        "M": 1024**2,
        "G": 1024**3,
        "T": 1024**4,
    }[match.group("unit")]
    return round(float(match.group("value")) * multiplier)


def root_identity(header: str) -> tuple[str, str]:
    match = re.search(r"ROOT (?P<kind>LEAK|CYCLE): <(?P<signature>.*)>", header)
    if match is None:
        return "unknown", header
    return match.group("kind").lower(), match.group("signature")


def display_signature(signature: str) -> str:
    if "WTF::" in signature:
        return "WTF allocation"
    if len(signature) <= 160:
        return signature
    return f"{signature[:157]}..."


def application_symbol(line: str) -> str:
    symbol = re.sub(
        rf"^\s*\d+\s+{re.escape(APP_FRAME_MARKER)}\s+0x[0-9a-fA-F]+\s+",
        "",
        line,
    )
    return symbol.strip()


def parse_leaks_report(text: str) -> dict[str, object]:
    footprint = re.search(r"^Physical footprint:\s+(\S+)$", text, re.MULTILINE)
    peak = re.search(r"^Physical footprint \(peak\):\s+(\S+)$", text, re.MULTILINE)
    allocation = re.search(
        r"^Process \d+: (?P<nodes>\d+) nodes malloced for (?P<kb>\d+) KB$",
        text,
        re.MULTILINE,
    )
    leaks = re.search(
        r"^Process \d+: (?P<count>\d+) leaks for (?P<bytes>\d+) "
        r"total leaked bytes\.$",
        text,
        re.MULTILINE,
    )
    missing = [
        label
        for label, match in [
            ("physical footprint", footprint),
            ("peak physical footprint", peak),
            ("allocation summary", allocation),
            ("leak summary", leaks),
        ]
        if match is None
    ]
    if missing:
        raise ValueError(f"leaks report is missing {', '.join(missing)}")

    lines = text.splitlines()
    root_groups: list[dict[str, object]] = []
    for index, line in enumerate(lines):
        stack_match = ROOT_STACK_PATTERN.match(line)
        if stack_match is None:
            continue
        stack_lines: list[str] = []
        for candidate in lines[index + 1 :]:
            if candidate == "====":
                break
            stack_lines.append(candidate)
        header = stack_match.group("header")
        kind, signature = root_identity(header)
        application_frames = [
            application_symbol(candidate)
            for candidate in stack_lines
            if APP_FRAME_MARKER in candidate
        ]
        meaningful_frames = [
            frame
            for frame in application_frames
            if "__debug_main_executable_dylib_entry_point" not in frame
            and "VitrineApp.$main" not in frame
        ]
        root_groups.append(
            {
                "instances": int(stack_match.group("count")),
                "kind": kind,
                "signature": display_signature(signature),
                "fingerprint": hashlib.sha256(header.encode("utf-8")).hexdigest()[:12],
                "application_path_frames": meaningful_frames,
            }
        )

    assert footprint is not None
    assert peak is not None
    assert allocation is not None
    assert leaks is not None
    return {
        "physical_footprint": footprint.group(1),
        "physical_footprint_bytes_approximate": approximate_bytes(footprint.group(1)),
        "peak_physical_footprint": peak.group(1),
        "peak_physical_footprint_bytes_approximate": approximate_bytes(peak.group(1)),
        "malloc_nodes": int(allocation.group("nodes")),
        "malloc_kilobytes": int(allocation.group("kb")),
        "leak_records": int(leaks.group("count")),
        "leaked_bytes": int(leaks.group("bytes")),
        "root_groups": root_groups,
        "root_group_count": len(root_groups),
        "root_instance_count": sum(int(group["instances"]) for group in root_groups),
        "root_groups_with_application_path_frames": sum(
            bool(group["application_path_frames"]) for group in root_groups
        ),
    }


def linear_slope(samples: Sequence[dict[str, int]]) -> float:
    """Return least-squares footprint bytes per completed iteration."""
    if len(samples) < 2:
        return 0.0
    mean_iteration = sum(sample["iteration"] for sample in samples) / len(samples)
    mean_footprint = sum(sample["physical_footprint_bytes"] for sample in samples) / len(
        samples
    )
    numerator = sum(
        (sample["iteration"] - mean_iteration)
        * (sample["physical_footprint_bytes"] - mean_footprint)
        for sample in samples
    )
    denominator = sum(
        (sample["iteration"] - mean_iteration) ** 2 for sample in samples
    )
    return numerator / denominator if denominator else 0.0


def parse_journey_samples(
    text: str, journey_id: str, expected_iterations: int
) -> dict[str, object]:
    samples = [
        {
            "iteration": int(match.group("iteration")),
            "physical_footprint_bytes": int(match.group("bytes")),
        }
        for match in SAMPLE_PATTERN.finditer(text)
        if match.group("journey") == journey_id
    ]
    expected_sequence = list(range(1, expected_iterations + 1))
    actual_sequence = [sample["iteration"] for sample in samples]
    if actual_sequence != expected_sequence:
        raise ValueError(
            f"{journey_id} footprint samples are incomplete or out of order: "
            f"expected {expected_sequence}, found {actual_sequence}"
        )
    if any(sample["physical_footprint_bytes"] <= 0 for sample in samples):
        raise ValueError(f"{journey_id} reported a non-positive footprint")

    warmup_count = expected_iterations // 5 if expected_iterations >= 10 else 0
    settled_samples = samples[warmup_count:]
    return {
        "sample_count": len(samples),
        "samples": samples,
        "first_footprint_bytes": samples[0]["physical_footprint_bytes"],
        "last_footprint_bytes": samples[-1]["physical_footprint_bytes"],
        "minimum_footprint_bytes": min(
            sample["physical_footprint_bytes"] for sample in samples
        ),
        "maximum_footprint_bytes": max(
            sample["physical_footprint_bytes"] for sample in samples
        ),
        "linear_slope_bytes_per_iteration": linear_slope(samples),
        "warmup_samples_excluded": warmup_count,
        "post_warmup_slope_bytes_per_iteration": linear_slope(settled_samples),
    }


def require_exact_completion(
    text: str, journey_id: str, completion_marker: object, iterations: int
) -> None:
    pattern = re.compile(
        rf"^{re.escape(str(completion_marker))} iterations={iterations}(?:\s|$)",
        re.MULTILINE,
    )
    if pattern.search(text) is None:
        raise ValueError(f"{journey_id} did not report exact completion")


def environment_metadata(root: Path) -> dict[str, object]:
    working_tree = optional_output(["git", "status", "--porcelain"], root)
    return {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "macos": platform.mac_ver()[0],
        "architecture": platform.machine(),
        "xcode": (optional_output(["xcodebuild", "-version"], root) or "").splitlines(),
        "commit": optional_output(["git", "rev-parse", "HEAD"], root),
        "branch": optional_output(["git", "branch", "--show-current"], root),
        "working_tree_clean": working_tree == "",
    }


def baseline_comparison(
    baseline: dict[str, object], candidate: dict[str, object]
) -> dict[str, object]:
    baseline_environment = baseline.get("environment")
    candidate_environment = candidate.get("environment")
    if not isinstance(baseline_environment, dict) or not isinstance(
        candidate_environment, dict
    ):
        raise ValueError("baseline and candidate need environment provenance")
    mismatches = [
        key
        for key in ("macos", "architecture", "xcode", "commit")
        if baseline_environment.get(key) != candidate_environment.get(key)
    ]
    if baseline_environment.get("working_tree_clean") is not True:
        mismatches.append("baseline_working_tree_clean")
    if candidate_environment.get("working_tree_clean") is not True:
        mismatches.append("candidate_working_tree_clean")
    baseline_journey = baseline.get("journey_id", baseline.get("journey"))
    candidate_journey = candidate.get("journey_id", candidate.get("journey"))
    comparable_journey = baseline_journey == candidate_journey
    comparable_iteration_count = baseline.get("iteration_count") == candidate.get(
        "iteration_count"
    )
    baseline_metrics = baseline.get("metrics")
    candidate_metrics = candidate.get("metrics")
    if not isinstance(baseline_metrics, dict) or not isinstance(candidate_metrics, dict):
        raise ValueError("baseline and candidate need parsed metrics")
    baseline_samples = baseline.get("footprint_samples")
    candidate_samples = candidate.get("footprint_samples")
    if not isinstance(baseline_samples, dict) or not isinstance(candidate_samples, dict):
        raise ValueError("baseline and candidate need footprint samples")
    return {
        "comparable": not mismatches and comparable_journey and comparable_iteration_count,
        "comparable_environment": not mismatches,
        "comparable_journey": comparable_journey,
        "comparable_iteration_count": comparable_iteration_count,
        "environment_mismatches": mismatches,
        "leak_records_delta": int(candidate_metrics["leak_records"])
        - int(baseline_metrics["leak_records"]),
        "leaked_bytes_delta": int(candidate_metrics["leaked_bytes"])
        - int(baseline_metrics["leaked_bytes"]),
        "physical_footprint_bytes_delta_approximate": int(
            candidate_metrics["physical_footprint_bytes_approximate"]
        )
        - int(baseline_metrics["physical_footprint_bytes_approximate"]),
        "peak_physical_footprint_bytes_delta_approximate": int(
            candidate_metrics["peak_physical_footprint_bytes_approximate"]
        )
        - int(baseline_metrics["peak_physical_footprint_bytes_approximate"]),
        "post_warmup_slope_bytes_per_iteration_delta": float(
            candidate_samples["post_warmup_slope_bytes_per_iteration"]
        )
        - float(
            baseline_samples["post_warmup_slope_bytes_per_iteration"]
        ),
    }


def require_self_test(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(f"self-test failed: {label}")


def run_self_test() -> int:
    fixture = """\
Physical footprint:         12.5M
Physical footprint (peak):  20.0M
----
Process 42: 100 nodes malloced for 200 KB
Process 42: 4 leaks for 96 total leaked bytes.

STACK OF 2 INSTANCES OF 'ROOT CYCLE: <NSXPCConnection>':
1   com.apple.AppIntents 0x1 makeXPCConnection + 4
0   libsystem_malloc.dylib 0x2 calloc + 8
====
    2 (64 bytes) ROOT CYCLE: <NSXPCConnection 0x123> [32]

STACK OF 1 INSTANCE OF 'ROOT LEAK: <Widget>':
2   Vitrine.debug.dylib 0x1 static VitrineApp.$main() + 4
1   Vitrine.debug.dylib 0x2 Widget.make() + 8
0   libsystem_malloc.dylib 0x3 malloc + 8
====
    1 (32 bytes) ROOT LEAK: <Widget 0x456> [32]
"""
    metrics = parse_leaks_report(fixture)
    require_self_test(metrics["leak_records"] == 4, "leak count")
    require_self_test(metrics["leaked_bytes"] == 96, "leaked bytes")
    require_self_test(metrics["root_instance_count"] == 3, "root instances")
    require_self_test(
        metrics["root_groups_with_application_path_frames"] == 1,
        "application allocation-path classification",
    )
    groups = metrics["root_groups"]
    require_self_test(isinstance(groups, list), "root groups")
    require_self_test(
        groups[1]["application_path_frames"] == ["Widget.make() + 8"],
        "generic app entry points excluded",
    )
    baseline = {
        "journey_id": "editor-snapshot",
        "journey": "editor snapshot loop",
        "iteration_count": 3,
        "environment": {
            "macos": "15.0",
            "architecture": "arm64",
            "xcode": ["16"],
            "commit": "abc123",
            "working_tree_clean": True,
        },
        "metrics": {
            "leak_records": 3,
            "leaked_bytes": 64,
            "physical_footprint_bytes_approximate": 10,
            "peak_physical_footprint_bytes_approximate": 20,
        },
        "footprint_samples": {"post_warmup_slope_bytes_per_iteration": 10.0},
    }
    candidate = {
        "journey_id": "editor-snapshot",
        "journey": "editor snapshot loop",
        "iteration_count": 3,
        "environment": {
            "macos": "15.0",
            "architecture": "arm64",
            "xcode": ["16"],
            "commit": "abc123",
            "working_tree_clean": True,
        },
        "metrics": {
            "leak_records": 4,
            "leaked_bytes": 96,
            "physical_footprint_bytes_approximate": 12,
            "peak_physical_footprint_bytes_approximate": 24,
        },
        "footprint_samples": {"post_warmup_slope_bytes_per_iteration": 12.0},
    }
    comparison = baseline_comparison(baseline, candidate)
    require_self_test(comparison["comparable"] is True, "comparable report")
    require_self_test(comparison["comparable_environment"] is True, "comparable baseline")
    require_self_test(comparison["comparable_journey"] is True, "comparable journey")
    require_self_test(
        comparison["comparable_iteration_count"] is True,
        "comparable iteration profile",
    )
    require_self_test(comparison["leaked_bytes_delta"] == 32, "baseline delta")
    candidate["environment"]["commit"] = "def456"
    different_commit = baseline_comparison(baseline, candidate)
    require_self_test(
        different_commit["comparable"] is False
        and "commit" in different_commit["environment_mismatches"],
        "different commits are not comparable",
    )
    candidate["environment"]["commit"] = "abc123"
    candidate["environment"]["working_tree_clean"] = False
    dirty_candidate = baseline_comparison(baseline, candidate)
    require_self_test(
        dirty_candidate["comparable"] is False
        and "candidate_working_tree_clean" in dirty_candidate["environment_mismatches"],
        "dirty candidates are not comparable",
    )
    candidate["environment"]["working_tree_clean"] = True
    candidate["journey_id"] = "image-import-cycle"
    different_journey = baseline_comparison(baseline, candidate)
    require_self_test(
        different_journey["comparable"] is False
        and different_journey["comparable_journey"] is False,
        "different journeys are not comparable",
    )
    candidate["journey_id"] = "editor-snapshot"
    candidate["iteration_count"] = 20
    different_profile = baseline_comparison(baseline, candidate)
    require_self_test(
        different_profile["comparable"] is False
        and different_profile["comparable_iteration_count"] is False,
        "different iteration profiles are not comparable",
    )
    sample_text = "\n".join(
        f"VITRINE_MEMORY_SAMPLE journey=window-churn iteration={iteration} "
        f"physical-footprint-bytes={1000 + iteration * 25}"
        for iteration in range(1, 6)
    )
    sample_metrics = parse_journey_samples(sample_text, "window-churn", 5)
    require_self_test(sample_metrics["sample_count"] == 5, "sample count")
    require_self_test(
        sample_metrics["linear_slope_bytes_per_iteration"] == 25.0,
        "linear footprint slope",
    )
    try:
        parse_journey_samples(sample_text, "window-churn", 6)
        require_self_test(False, "missing sample rejection")
    except ValueError:
        pass
    completion_text = "VITRINE_MEMORY_WINDOW_CHURN_COMPLETE iterations=5 snapshots=5\n"
    require_exact_completion(
        completion_text,
        "window-churn",
        "VITRINE_MEMORY_WINDOW_CHURN_COMPLETE",
        5,
    )
    try:
        require_exact_completion(
            completion_text,
            "window-churn",
            "VITRINE_MEMORY_WINDOW_CHURN_COMPLETE",
            6,
        )
        require_self_test(False, "mismatched completion rejection")
    except ValueError:
        pass
    require_self_test(approximate_bytes("1.5M") == 1_572_864, "compact quantity")
    print("memory-smoke self-test passed")
    return 0


def validate_output_root(root: Path, output: Path) -> Path:
    resolved = (root / output).resolve() if not output.is_absolute() else output.resolve()
    build_root = (root / "build").resolve()
    try:
        resolved.relative_to(build_root)
    except ValueError as error:
        raise ValueError("--output must stay inside the ignored build directory") from error
    return resolved


def locate_built_app(arguments: argparse.Namespace, root: Path) -> Path:
    completed = subprocess.run(
        [
            "xcodebuild",
            "-project",
            str(arguments.project),
            "-scheme",
            arguments.scheme,
            "-configuration",
            arguments.configuration,
            "-showBuildSettings",
            "-json",
        ],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        diagnostic = completed.stderr.strip().splitlines()
        detail = diagnostic[-1] if diagnostic else "no diagnostic"
        raise RuntimeError(f"xcodebuild could not locate the built app: {detail}")
    payload = json.loads(completed.stdout)
    if not isinstance(payload, list):
        raise ValueError("xcodebuild build-settings JSON is not a target list")
    candidates: list[Path] = []
    for target in payload:
        if not isinstance(target, dict):
            continue
        settings = target.get("buildSettings")
        if not isinstance(settings, dict) or settings.get("WRAPPER_EXTENSION") != "app":
            continue
        directory = settings.get("TARGET_BUILD_DIR")
        wrapper = settings.get("WRAPPER_NAME")
        if isinstance(directory, str) and isinstance(wrapper, str):
            candidates.append(Path(directory) / wrapper)
    if len(candidates) != 1:
        raise ValueError(
            f"expected one built app in xcodebuild settings, found {len(candidates)}"
        )
    return candidates[0]


def run_capture(arguments: argparse.Namespace) -> dict[str, object]:
    root = Path(__file__).resolve().parent.parent
    app = (
        arguments.app.resolve()
        if arguments.app is not None
        else locate_built_app(arguments, root).resolve()
    )
    executable = app / "Contents" / "MacOS" / "Vitrine"
    if not executable.is_file():
        raise ValueError(f"Vitrine executable not found at {executable}")
    output_root = validate_output_root(root, arguments.output)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_directory = output_root / timestamp
    suffix = 1
    while run_directory.exists():
        run_directory = output_root / f"{timestamp}-{suffix}"
        suffix += 1
    run_directory.mkdir(parents=True)

    memgraph = run_directory / f"{arguments.journey}.memgraph"
    launch_log = run_directory / "launch.log"
    leaks_report = run_directory / "leaks.txt"
    suite = f"com.johnny4young.vitrine.memory-smoke.{uuid.uuid4()}"
    environment = os.environ.copy()
    environment["VITRINE_USER_DEFAULTS_SUITE"] = suite
    journey = JOURNEYS[arguments.journey]
    iterations = arguments.iterations or int(journey["default_iterations"])
    environment["VITRINE_MEMORY_ITERATIONS"] = str(iterations)
    if arguments.journey == "image-import-cycle":
        environment["VITRINE_MEMORY_IMAGE_STORE_ISOLATED"] = "1"
    command = [
        "xcrun",
        "leaks",
        "--fullStacks",
        f"--outputGraph={memgraph}",
        "--atExit",
        "--",
        str(executable),
        "--skip-onboarding",
        *journey["arguments"],
    ]

    launch_status: int | None = None
    try:
        with launch_log.open("w", encoding="utf-8") as output:
            completed = subprocess.run(
                command,
                cwd=root,
                env=environment,
                stdout=output,
                stderr=subprocess.STDOUT,
                timeout=arguments.launch_timeout,
                check=False,
                text=True,
            )
            launch_status = completed.returncode
    finally:
        subprocess.run(
            ["defaults", "delete", suite],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    if not memgraph.exists():
        raise RuntimeError(
            f"leaks did not produce {memgraph}; inspect {launch_log} "
            f"(exit status {launch_status})"
        )
    completion_marker = journey["completion_marker"]
    launch_text = launch_log.read_text(encoding="utf-8")
    if completion_marker is not None:
        try:
            require_exact_completion(
                launch_text, arguments.journey, completion_marker, iterations
            )
        except ValueError as error:
            raise RuntimeError(
                f"{arguments.journey} did not report exact completion; "
                f"inspect {launch_log}"
            ) from error
    footprint_samples = parse_journey_samples(
        launch_text, arguments.journey, iterations
    )
    with leaks_report.open("w", encoding="utf-8") as output:
        analysis = subprocess.run(
            ["xcrun", "leaks", "--fullStacks", str(memgraph)],
            cwd=root,
            stdout=output,
            stderr=subprocess.STDOUT,
            timeout=arguments.analysis_timeout,
            check=False,
            text=True,
        )
    if analysis.returncode not in {0, 1}:
        raise RuntimeError(
            f"leaks analysis failed with exit status {analysis.returncode}; "
            f"inspect {leaks_report}"
        )
    report_text = leaks_report.read_text(encoding="utf-8")
    metrics = parse_leaks_report(report_text)
    report: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "journey_id": arguments.journey,
        "journey": journey["label"],
        "iteration_count": iterations,
        "environment": environment_metadata(root),
        "app": str(app),
        "launch_exit_status": launch_status,
        "analysis_exit_status": analysis.returncode,
        "analysis_result": "leaks_detected" if analysis.returncode == 1 else "no_leaks_reported",
        "metrics": metrics,
        "footprint_samples": footprint_samples,
        "artifacts": {
            "memgraph": str(memgraph),
            "leaks_report": str(leaks_report),
            "launch_log": str(launch_log),
        },
        "interpretation": {
            "status": "manual_review_required",
            "limitations": [
                "At-exit leaks cannot prove the absence of reachable retain cycles or steady-state growth.",
                "An application frame identifies an allocation path, not ownership of the leaked root.",
                "Snapshot rasterization contributes to the recorded peak footprint.",
                "Framework leaks are reported rather than silently allowlisted or treated as product failures.",
                {
                    "image-import-cycle": (
                        "The image journey uses deterministic local PNGs; it does not simulate "
                        "a defective external item provider or a maximum-size image."
                    ),
                    "window-churn": (
                        "Window churn covers controller and SwiftUI teardown, not every auxiliary window type."
                    ),
                    "web-snapshot-cycle": (
                        "The WebKit journey uses local HTML and measures the Vitrine host process, "
                        "not separate WebContent processes; it does not qualify public network capture."
                    ),
                    "editor-snapshot": (
                        "The editor snapshot journey does not exercise image import or item-provider callbacks."
                    ),
                    "large-document-cycle": (
                        "The large-document journey covers interactive fallback and editor teardown, not the five-megabyte import ceiling."
                    ),
                }[arguments.journey],
                "Footprint slope is diagnostic evidence; no single run or absolute value is an ownership verdict.",
            ],
        },
    }
    if arguments.baseline is not None:
        baseline = json.loads(arguments.baseline.read_text(encoding="utf-8"))
        if not isinstance(baseline, dict) or baseline.get("schema_version") != SCHEMA_VERSION:
            raise ValueError(
                f"--baseline must use memory-smoke schema version {SCHEMA_VERSION}"
            )
        report["baseline_comparison"] = baseline_comparison(baseline, report)

    report_path = run_directory / "report.json"
    report["artifacts"]["report"] = str(report_path)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(
        f"Dynamic-memory evidence captured for {journey['label']}; "
        "manual root classification is required."
    )
    print(
        f"Leaks: {metrics['leak_records']} records / {metrics['leaked_bytes']} bytes; "
        f"footprint: {metrics['physical_footprint']} "
        f"(peak {metrics['peak_physical_footprint']})."
    )
    print(
        f"Root groups: {metrics['root_group_count']} "
        f"({metrics['root_groups_with_application_path_frames']} include meaningful "
        "Vitrine allocation-path frames)."
    )
    print(
        "Settled footprint slope: "
        f"{footprint_samples['post_warmup_slope_bytes_per_iteration']:.1f} "
        f"bytes/iteration after {footprint_samples['warmup_samples_excluded']} "
        "warm-up samples."
    )
    if "baseline_comparison" in report:
        comparison = report["baseline_comparison"]
        print(f"Baseline comparison: {json.dumps(comparison, sort_keys=True)}")
    print(f"Report: {report_path}")
    print(f"Memgraph: {memgraph}")
    return report


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--app", type=Path, help="built Vitrine.app; otherwise locate it through Xcode"
    )
    parser.add_argument("--project", type=Path, default=Path("Vitrine.xcodeproj"))
    parser.add_argument("--scheme", default="Vitrine")
    parser.add_argument("--configuration", default="Debug")
    parser.add_argument(
        "--journey", choices=sorted(JOURNEYS), default=DEFAULT_JOURNEY
    )
    parser.add_argument(
        "--iterations",
        type=lambda value: bounded_iteration_count(value),
        help="override the journey with 1-100 iterations (qualification profiles use 20/50/100)",
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--launch-timeout", type=int, default=180)
    parser.add_argument("--analysis-timeout", type=int, default=180)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def bounded_iteration_count(value: str) -> int:
    try:
        count = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("iterations must be an integer") from error
    if not 1 <= count <= 100:
        raise argparse.ArgumentTypeError("iterations must be between 1 and 100")
    return count


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.self_test:
            return run_self_test()
        run_capture(arguments)
    except (
        AssertionError,
        json.JSONDecodeError,
        OSError,
        RuntimeError,
        ValueError,
        subprocess.TimeoutExpired,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
