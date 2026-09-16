#!/usr/bin/env python3
"""Require a commit's CI checks to have passed before a release candidate is built.

The release workflow used to re-run lint, both builds, the UI-test build, and the unit
suite on the tagged commit, although CI had already run a strict superset of that work on
the same commit when it landed on `main`. The release gate now reads that commit's check
runs instead: `gh api --paginate .../commits/<sha>/check-runs --jq '.check_runs[]'` writes
one JSON object per line, and this decides whether every required check passed.

Only check runs created by GitHub Actions for the exact commit count, and for each required
name only the newest run does, so a job re-run that succeeds replaces an earlier failure and
a later failure replaces an earlier success.

Exit codes: 0 when every required check passed; 3 when none failed but some are still
running or have not been created, so the caller may wait and ask again; 2 when a check
failed, was cancelled, skipped, or timed out, or when the input is invalid.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


COMMIT = re.compile(r"^[0-9a-f]{40}$")
ACTIONS_APP = "github-actions"
PASSED, PENDING, FAILED = "passed", "pending", "failed"
EXIT_CODES = {PASSED: 0, FAILED: 2, PENDING: 3}


def load_check_runs(text: str) -> list[dict[str, Any]]:
    """Check runs from `--jq '.check_runs[]'` output, or from a `{"check_runs": [...]}` object."""
    stripped = text.strip()
    if not stripped:
        return []
    if stripped.startswith("{") and "\n" not in stripped:
        document = json.loads(stripped)
        if isinstance(document.get("check_runs"), list):
            return list(document["check_runs"])
        return [document]
    runs: list[dict[str, Any]] = []
    for number, line in enumerate(stripped.splitlines(), start=1):
        if not line.strip():
            continue
        value = json.loads(line)
        if not isinstance(value, dict):
            raise ValueError(f"line {number} is not a check run object")
        runs.append(value)
    return runs


def evaluate(
    check_runs: list[dict[str, Any]], required: list[str], commit: str, app: str = ACTIONS_APP
) -> tuple[str, list[str]]:
    """The overall state and one report line per required check."""
    relevant: dict[str, list[dict[str, Any]]] = {}
    for run in check_runs:
        run_app = run.get("app")
        if run.get("head_sha") != commit or not isinstance(run_app, dict):
            continue
        if run_app.get("slug") != app or not isinstance(run.get("id"), int):
            continue
        relevant.setdefault(str(run.get("name")), []).append(run)

    lines: list[str] = []
    states: set[str] = set()
    for name in required:
        runs = relevant.get(name, [])
        if not runs:
            states.add(PENDING)
            lines.append(f"… {name}: no check run yet")
            continue
        newest = max(runs, key=lambda run: run["id"])
        if newest.get("status") != "completed":
            states.add(PENDING)
            lines.append(f"… {name}: {newest.get('status')}")
        elif newest.get("conclusion") == "success":
            states.add(PASSED)
            lines.append(f"✓ {name}: success")
        else:
            states.add(FAILED)
            lines.append(f"✗ {name}: {newest.get('conclusion')}")

    if FAILED in states:
        return FAILED, lines
    if PENDING in states:
        return PENDING, lines
    return PASSED, lines


def run_self_test() -> None:
    commit = "a" * 40
    required = ["Build & test · Tahoe 26", "UI tests · Tahoe 26"]

    def run(run_id: int, name: str, status: str = "completed", conclusion: str | None = "success",
            **overrides: Any) -> dict[str, Any]:
        return {
            "id": run_id, "name": name, "status": status, "conclusion": conclusion,
            "head_sha": commit, "app": {"slug": ACTIONS_APP}, **overrides,
        }

    cases: list[tuple[str, list[dict[str, Any]], str]] = [
        ("every required check succeeded", [run(1, required[0]), run(2, required[1])], PASSED),
        ("one check is still running",
         [run(1, required[0]), run(2, required[1], "in_progress", None)], PENDING),
        ("one check has not been created", [run(1, required[0])], PENDING),
        ("a failure outranks a pending check",
         [run(1, required[0], conclusion="failure"), run(2, required[1], "queued", None)], FAILED),
        ("a successful re-run replaces an earlier failure",
         [run(1, required[0], conclusion="failure"), run(3, required[0]), run(2, required[1])],
         PASSED),
        ("a newer failure replaces an earlier success",
         [run(1, required[0]), run(3, required[0], conclusion="failure"), run(2, required[1])],
         FAILED),
        ("a skipped required check is not a pass",
         [run(1, required[0], conclusion="skipped"), run(2, required[1])], FAILED),
        ("a cancelled required check is not a pass",
         [run(1, required[0], conclusion="cancelled"), run(2, required[1])], FAILED),
        ("a check from another app does not count",
         [run(1, required[0]), run(2, required[1], app={"slug": "someone-else"})], PENDING),
        ("a check on another commit does not count",
         [run(1, required[0]), run(2, required[1], head_sha="b" * 40)], PENDING),
    ]
    for label, runs, expected in cases:
        state, _ = evaluate(runs, required, commit)
        if state != expected:
            raise AssertionError(f"{label}: expected {expected}, got {state}")

    lines = "\n".join(json.dumps(item) for item in [run(1, required[0]), run(2, required[1])])
    if len(load_check_runs(lines)) != 2 or load_check_runs(""):
        raise AssertionError("line-delimited check runs did not load")
    wrapped = json.dumps({"check_runs": [run(1, required[0])]})
    if len(load_check_runs(wrapped)) != 1:
        raise AssertionError("a wrapped check-runs object did not load")
    print("commit CI gate self-test passed")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--commit")
    parser.add_argument("--check-runs", type=Path)
    parser.add_argument("--required", action="append", default=[])
    parser.add_argument("--app", default=ACTIONS_APP)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        run_self_test()
        return 0

    try:
        if args.commit is None or not COMMIT.fullmatch(args.commit):
            raise ValueError("--commit must be a full 40-character lowercase commit SHA")
        if not args.required or len(set(args.required)) != len(args.required):
            raise ValueError("--required must name each required check once")
        if args.check_runs is None:
            raise ValueError("--check-runs is required")
        runs = load_check_runs(args.check_runs.read_text(encoding="utf-8"))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"commit CI gate failed: {error}", file=sys.stderr)
        return EXIT_CODES[FAILED]

    state, lines = evaluate(runs, args.required, args.commit, args.app)
    for line in lines:
        print(line)
    print(f"CI on {args.commit}: {state}")
    return EXIT_CODES[state]


if __name__ == "__main__":
    raise SystemExit(main())
