#!/usr/bin/env python3
"""Decide whether a push to `main` may reuse its pull request's CI instead of rerunning it.

A squash merge of a pull request that was up to date with `main` lands exactly the tree
the pull request's CI already tested. The push then reuses that evidence, but only when:

- the push added one commit, the merge commit of a merged pull request into `main`;
- that commit's tree equals the pull request head's tree;
- the newest run of every required check on that head succeeded, read with the same
  rules as the release gate (`scripts/verify-commit-ci.py`);
- the commit leaves `project.yml` alone. A release tags the commit that bumps the version
  there, and its gate reads that commit's own checks, so those commits always run;
- no required check on the head says it skipped a comparison, such as a pull request that
  rendered the goldens without comparing pixels on an image the baselines do not pin.

Anything else, including an API or git error, prints `reuse=false` and the full gate runs.

    python3 scripts/ci-reuse-pr-evidence.py --repository OWNER/NAME --commit <sha> \\
        --before <sha> --required "<check name>" [--required ...]
    python3 scripts/ci-reuse-pr-evidence.py --self-test

Prints `reuse=true` or `reuse=false`, ready to append to `$GITHUB_OUTPUT`.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

ALWAYS_FULL = ("project.yml",)
BASE_BRANCH = "main"
# Annotation titles ci.yml writes when a pull request skipped part of what main enforces.
WEAKER_THAN_MAIN = ("Golden baseline image",)


def load_commit_ci() -> Any:
    path = Path(__file__).with_name("verify-commit-ci.py")
    spec = importlib.util.spec_from_file_location("verify_commit_ci", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def merged_pull(pulls: list[dict[str, Any]], commit: str) -> dict[str, Any] | None:
    """The pull request whose merge into `main` produced `commit`, if any."""
    for pull in pulls:
        if (
            pull.get("merged_at")
            and pull.get("merge_commit_sha") == commit
            and pull.get("base", {}).get("ref") == BASE_BRANCH
        ):
            return pull
    return None


def newest_runs(runs: list[dict[str, Any]], required: list[str], head: str) -> list[int]:
    """The ids of the newest Actions run of each required check on `head`."""
    newest: dict[str, dict[str, Any]] = {}
    for run in runs:
        name = run.get("name")
        if name not in required or run.get("head_sha") != head:
            continue
        if (run.get("app") or {}).get("slug") != "github-actions":
            continue
        if name not in newest or run["id"] > newest[name]["id"]:
            newest[name] = run
    return [run["id"] for run in newest.values()]


def decide(
    *, single_commit: bool, changed: list[str], commit_tree: str, head_tree: str | None,
    checks: str, weaker: list[str]
) -> tuple[bool, str]:
    if not single_commit:
        return False, "the push added more than one commit"
    if any(path in ALWAYS_FULL for path in changed):
        return False, "the commit changes project.yml, so a release may tag it"
    if head_tree is None:
        return False, "no merged pull request produced this commit"
    if head_tree != commit_tree:
        return False, "main's tree differs from the pull request head's"
    if checks != "passed":
        return False, f"the pull request head's required checks are {checks}"
    if weaker:
        return False, f"the pull request ran weaker than main ({', '.join(weaker)})"
    return True, "the pull request head tested this exact tree"


def git(*arguments: str) -> str:
    return subprocess.run(
        ["git", *arguments], check=True, capture_output=True, text=True
    ).stdout.strip()


def api(path: str, *, paginate: bool = False, jq: str | None = None) -> str:
    command = ["gh", "api", path, *(["--paginate"] if paginate else []),
               *(["--jq", jq] if jq else [])]
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def gather(repository: str, commit: str, before: str, required: list[str]) -> tuple[bool, str]:
    single_commit = git("rev-parse", f"{commit}^") == before
    changed = git("diff", "--name-only", "--no-renames", f"{commit}^", commit).splitlines()
    commit_tree = git("rev-parse", f"{commit}^{{tree}}")
    pull = merged_pull(json.loads(api(f"repos/{repository}/commits/{commit}/pulls")), commit)
    head_tree, checks, weaker = None, "unread", []
    if pull is not None:
        head = pull["head"]["sha"]
        head_tree = json.loads(api(f"repos/{repository}/git/commits/{head}"))["tree"]["sha"]
        runs = load_commit_ci().load_check_runs(
            api(f"repos/{repository}/commits/{head}/check-runs?per_page=100",
                paginate=True, jq=".check_runs[]"))
        checks, lines = load_commit_ci().evaluate(runs, required, head)
        for run_id in newest_runs(runs, required, head):
            titles = api(f"repos/{repository}/check-runs/{run_id}/annotations?per_page=100",
                         paginate=True, jq=".[].title").splitlines()
            weaker += [title for title in titles if title in WEAKER_THAN_MAIN]
        print(f"Pull request #{pull['number']} head {head}:", file=sys.stderr)
        for line in lines:
            print(f"  {line}", file=sys.stderr)
    reuse, reason = decide(
        single_commit=single_commit, changed=changed, commit_tree=commit_tree,
        head_tree=head_tree, checks=checks, weaker=weaker)
    if reuse and pull is not None:
        reason += f": #{pull['number']} at {pull['head']['sha']}"
    return reuse, reason


def run_self_test() -> int:
    def expect(condition: bool, label: str) -> None:
        if not condition:
            raise RuntimeError(f"ci-reuse-pr-evidence self-test failed: {label}")

    good = {
        "single_commit": True, "changed": ["Vitrine/App/AppDelegate.swift"],
        "commit_tree": "t", "head_tree": "t", "checks": "passed", "weaker": [],
    }
    expect(decide(**good)[0], "the same tree with every check passed reuses")
    for label, override in [
        ("a push of several commits", {"single_commit": False}),
        ("a version bump", {"changed": ["project.yml", "CHANGELOG.md"]}),
        ("no merged pull request", {"head_tree": None}),
        ("a tree the pull request never tested", {"head_tree": "u"}),
        ("a failed required check", {"checks": "failed"}),
        ("a required check still running or missing", {"checks": "pending"}),
        ("goldens rendered without comparing pixels", {"weaker": [WEAKER_THAN_MAIN[0]]}),
    ]:
        expect(not decide(**{**good, **override})[0], label)

    merge = {"merged_at": "2026-11-06T00:00:00Z", "merge_commit_sha": "c",
             "base": {"ref": BASE_BRANCH}}
    expect(merged_pull([merge], "c") is merge, "the merged pull request is found")
    expect(merged_pull([{**merge, "merged_at": None}], "c") is None, "an open pull request")
    expect(merged_pull([{**merge, "merge_commit_sha": "d"}], "c") is None,
           "a pull request that merely contains the commit")
    expect(merged_pull([{**merge, "base": {"ref": "release"}}], "c") is None,
           "a merge into another branch")

    commit_ci = load_commit_ci()
    required = ["Build & test · Tahoe 26"]
    run = {"id": 1, "name": required[0], "status": "completed", "conclusion": "success",
           "head_sha": "a" * 40, "app": {"slug": "github-actions"}}
    expect(commit_ci.evaluate([run], required, "a" * 40)[0] == "passed",
           "check runs are read with the release gate's rules")
    expect(commit_ci.evaluate([{**run, "conclusion": "skipped"}], required, "a" * 40)[0]
           == "failed", "a skipped check is not evidence")
    rerun = {**run, "id": 2}
    other = {**run, "id": 3, "name": "WebKit integration · macos-26"}
    expect(newest_runs([run, rerun, other], required, "a" * 40) == [2],
           "annotations are read from the newest run of each required check")
    print("CI evidence reuse self-test passed.")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--commit")
    parser.add_argument("--before")
    parser.add_argument("--required", action="append", default=[])
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args(argv)

    if arguments.self_test:
        return run_self_test()
    try:
        if not (arguments.repository and arguments.commit and arguments.before
                and arguments.required):
            raise ValueError("--repository, --commit, --before and --required are required")
        reuse, reason = gather(
            arguments.repository, arguments.commit, arguments.before, arguments.required)
    except (OSError, ValueError, KeyError, RuntimeError, json.JSONDecodeError,
            subprocess.CalledProcessError) as error:
        reuse, reason = False, f"could not prove reuse ({error})"
    print(f"{'Reusing' if reuse else 'Running the full gate'}: {reason}.", file=sys.stderr)
    print(f"reuse={'true' if reuse else 'false'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
