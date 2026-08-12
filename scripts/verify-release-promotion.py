#!/usr/bin/env python3
"""Validate that a manual promotion targets one exact successful candidate run."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


STABLE_TAG = re.compile(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
POSITIVE_INTEGER = re.compile(r"^[1-9][0-9]*$")
QA_CONFIRMATION = "CLEAN-MAC-QA-PASSED"


def validate(
    *,
    tag: str,
    candidate_run_id: str,
    expected_sha256: str,
    qa_confirmation: str,
    tag_object_type: str,
    tag_commit: str,
    marketing_version: str,
    repository: str,
    workflow_path: str,
    run: dict[str, Any],
) -> list[str]:
    errors: list[str] = []
    match = STABLE_TAG.fullmatch(tag)
    if match is None:
        errors.append(f"promotion tag {tag!r} is not stable v-prefixed SemVer")
        tag_version = ""
    else:
        tag_version = tag[1:]

    if not POSITIVE_INTEGER.fullmatch(candidate_run_id):
        errors.append("candidate run ID must be a positive integer")
    if not SHA256.fullmatch(expected_sha256):
        errors.append("expected SHA-256 must be 64 lowercase hexadecimal digits")
    if qa_confirmation != QA_CONFIRMATION:
        errors.append(f"QA confirmation must be exactly {QA_CONFIRMATION}")
    if tag_object_type != "tag":
        errors.append("promotion requires an existing annotated tag object")
    if tag_version and tag_version != marketing_version:
        errors.append(
            f"tag version {tag_version} does not match MARKETING_VERSION {marketing_version}"
        )

    actual_run_id = str(run.get("id", ""))
    if POSITIVE_INTEGER.fullmatch(candidate_run_id) and actual_run_id != candidate_run_id:
        errors.append(
            f"candidate metadata run ID {actual_run_id!r} does not match {candidate_run_id}"
        )
    if run.get("event") != "push":
        errors.append("candidate run was not triggered by a tag push")
    if run.get("status") != "completed" or run.get("conclusion") != "success":
        errors.append("candidate run has not completed successfully")
    if run.get("head_sha") != tag_commit:
        errors.append("candidate run head SHA does not match the annotated tag commit")
    if run.get("path") != workflow_path:
        errors.append("candidate run did not execute the expected release workflow")

    run_repository = run.get("repository")
    actual_repository = (
        run_repository.get("full_name") if isinstance(run_repository, dict) else None
    )
    if actual_repository != repository:
        errors.append("candidate run belongs to a different repository")
    return errors


def run_self_test() -> None:
    base_run: dict[str, Any] = {
        "id": 123456,
        "event": "push",
        "status": "completed",
        "conclusion": "success",
        "head_sha": "a" * 40,
        "path": ".github/workflows/release.yml",
        "repository": {"full_name": "johnny4young/vitrine"},
    }
    base = {
        "tag": "v1.1.0",
        "candidate_run_id": "123456",
        "expected_sha256": "b" * 64,
        "qa_confirmation": QA_CONFIRMATION,
        "tag_object_type": "tag",
        "tag_commit": "a" * 40,
        "marketing_version": "1.1.0",
        "repository": "johnny4young/vitrine",
        "workflow_path": ".github/workflows/release.yml",
        "run": base_run,
    }
    if validate(**base):
        raise AssertionError("valid promotion fixture was rejected")

    invalid_cases = [
        {"tag": "v1.1.0-rc.1"},
        {"candidate_run_id": "0"},
        {"expected_sha256": "B" * 64},
        {"qa_confirmation": "yes"},
        {"tag_object_type": "commit"},
        {"marketing_version": "1.0.1"},
        {"run": {**base_run, "conclusion": "failure"}},
        {"run": {**base_run, "head_sha": "c" * 40}},
        {"run": {**base_run, "path": ".github/workflows/other.yml"}},
        {"run": {**base_run, "repository": {"full_name": "other/vitrine"}}},
    ]
    for overrides in invalid_cases:
        fixture = {**base, **overrides}
        if not validate(**fixture):
            raise AssertionError(f"invalid promotion fixture was accepted: {overrides}")
    print("release promotion validator self-test passed")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--tag")
    parser.add_argument("--candidate-run-id")
    parser.add_argument("--expected-sha256")
    parser.add_argument("--qa-confirmation")
    parser.add_argument("--tag-object-type")
    parser.add_argument("--tag-commit")
    parser.add_argument("--marketing-version")
    parser.add_argument("--repository")
    parser.add_argument("--workflow-path", default=".github/workflows/release.yml")
    parser.add_argument("--run-json", type=Path)
    return parser.parse_args()


def required(value: str | None, name: str) -> str:
    if value is None:
        raise ValueError(f"{name} is required")
    return value


def main() -> int:
    args = parse_args()
    if args.self_test:
        run_self_test()
        return 0

    try:
        run_path = required(args.run_json, "--run-json")
        run = json.loads(run_path.read_text(encoding="utf-8"))
        if not isinstance(run, dict):
            raise ValueError("--run-json must contain a JSON object")
        errors = validate(
            tag=required(args.tag, "--tag"),
            candidate_run_id=required(args.candidate_run_id, "--candidate-run-id"),
            expected_sha256=required(args.expected_sha256, "--expected-sha256"),
            qa_confirmation=required(args.qa_confirmation, "--qa-confirmation"),
            tag_object_type=required(args.tag_object_type, "--tag-object-type"),
            tag_commit=required(args.tag_commit, "--tag-commit"),
            marketing_version=required(args.marketing_version, "--marketing-version"),
            repository=required(args.repository, "--repository"),
            workflow_path=args.workflow_path,
            run=run,
        )
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"release promotion validation failed: {error}", file=sys.stderr)
        return 2

    if errors:
        for error in errors:
            print(f"release promotion validation failed: {error}", file=sys.stderr)
        return 2
    print("release promotion request validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
