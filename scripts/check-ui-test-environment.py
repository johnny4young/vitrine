#!/usr/bin/env python3
"""Fail before XCUITest when another macOS UI-test runner is still active."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


RUNNER_PATTERN = re.compile(
    r"^(?:\S*/)?(?P<name>[A-Za-z0-9_.-]+UITests-Runner)\.app/Contents/MacOS/"
    r"(?P=name)(?=\s|$)"
)


class PreflightError(RuntimeError):
    """The UI-test environment cannot provide isolated evidence."""


@dataclass(frozen=True, order=True)
class ActiveRunner:
    pid: int
    name: str


def parse_active_runners(process_list: str) -> list[ActiveRunner]:
    """Extract concrete XCTest runner executables from a BSD ps listing."""

    runners: set[ActiveRunner] = set()
    for raw_line in process_list.splitlines():
        match = re.match(r"^\s*(?P<pid>\d+)\s+(?P<command>.+?)\s*$", raw_line)
        if match is None:
            continue
        runner = RUNNER_PATTERN.match(match.group("command"))
        if runner is None:
            continue
        runners.add(ActiveRunner(pid=int(match.group("pid")), name=runner.group("name")))
    return sorted(runners)


def current_process_list() -> str:
    try:
        result = subprocess.run(
            ["ps", "-ww", "-axo", "pid=,command="],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise PreflightError(f"could not inspect running processes: {error}") from error
    return result.stdout


def assert_isolated(process_list: str) -> None:
    runners = parse_active_runners(process_list)
    if not runners:
        return
    details = ", ".join(f"PID {runner.pid} ({runner.name})" for runner in runners)
    raise PreflightError(
        "active macOS UI-test runner detected: "
        f"{details}. Finish or stop the existing suite, then retry. "
        "Vitrine does not terminate test processes automatically."
    )


def run_self_test() -> None:
    assert parse_active_runners("") == []
    assert parse_active_runners("  42 /Applications/Xcode.app/Contents/MacOS/Xcode\n") == []
    assert parse_active_runners("  43 echo UITests-Runner\n") == []
    assert (
        parse_active_runners(
            "  44 /bin/sh -c echo /tmp/FakeUITests-Runner.app/Contents/MacOS/"
            "FakeUITests-Runner\n"
        )
        == []
    )

    listing = """
      900 /Users/me/Library/Developer/Xcode/DerivedData/Portavoz/Build/Products/Debug/PortavozUITests-Runner.app/Contents/MacOS/PortavozUITests-Runner -AppleLanguages (en)
      901 /Users/me/Library/Developer/Xcode/DerivedData/Vitrine/Build/Products/Debug/VitrineUITests-Runner.app/Contents/MacOS/VitrineUITests-Runner
      901 /Users/me/Library/Developer/Xcode/DerivedData/Vitrine/Build/Products/Debug/VitrineUITests-Runner.app/Contents/MacOS/VitrineUITests-Runner
    """
    assert parse_active_runners(listing) == [
        ActiveRunner(pid=900, name="PortavozUITests-Runner"),
        ActiveRunner(pid=901, name="VitrineUITests-Runner"),
    ]

    try:
        assert_isolated(listing)
    except PreflightError as error:
        message = str(error)
        assert "PID 900 (PortavozUITests-Runner)" in message
        assert "PID 901 (VitrineUITests-Runner)" in message
        assert "does not terminate" in message
    else:
        raise AssertionError("an active UI-test runner must fail the preflight")

    assert_isolated("  42 /Applications/Xcode.app/Contents/MacOS/Xcode\n")
    print("UI-test environment preflight self-test passed.")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--process-list",
        type=Path,
        help="read a captured `ps -ww -axo pid=,command=` listing instead of live processes",
    )
    parser.add_argument("--self-test", action="store_true", help="run deterministic parser checks")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.self_test:
            run_self_test()
            return 0
        process_list = (
            arguments.process_list.read_text(encoding="utf-8")
            if arguments.process_list is not None
            else current_process_list()
        )
        assert_isolated(process_list)
    except (OSError, PreflightError) as error:
        print(f"error: UI-test environment preflight failed: {error}", file=sys.stderr)
        return 1
    print("UI-test environment is isolated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
