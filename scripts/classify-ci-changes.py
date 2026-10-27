#!/usr/bin/env python3
"""Decide whether a pull request needs the macOS app gates.

A pull request whose changed files all sit under a documentation-only surface skips
the build, UI and visual-tour jobs; the repository contracts that read those files
still run. Anything else, an empty diff, or any other event runs every gate.

    python3 scripts/classify-ci-changes.py --event pull_request --base <sha>
    python3 scripts/classify-ci-changes.py --self-test

Prints `app=true` or `app=false`, ready to append to `$GITHUB_OUTPUT`.
"""

from __future__ import annotations

import argparse
import subprocess
import sys

# The macOS gates neither build nor test these paths. Repository contracts still
# read them, which is why a documentation-only pull request runs that job instead.
DOCUMENTATION_PREFIXES = ("docs/", "site/", ".design-sync/", ".github/ISSUE_TEMPLATE/")
DOCUMENTATION_FILES = ("LICENSE",)


def is_documentation(path: str) -> bool:
    if path.startswith(DOCUMENTATION_PREFIXES) or path in DOCUMENTATION_FILES:
        return True
    return "/" not in path and path.endswith(".md")


def needs_app_gates(event: str, changed: list[str]) -> bool:
    if event != "pull_request" or not changed:
        return True
    return not all(is_documentation(path) for path in changed)


def changed_files(base: str) -> list[str]:
    output = subprocess.run(
        ["git", "diff", "--name-only", f"{base}...HEAD"],
        check=True, capture_output=True, text=True,
    ).stdout
    return [line for line in output.splitlines() if line]


def run_self_test() -> int:
    def expect(condition: bool, label: str) -> None:
        if not condition:
            raise RuntimeError(f"classify-ci-changes self-test failed: {label}")

    expect(not needs_app_gates("pull_request", ["docs/RELEASING.md", "README.md"]), "docs only")
    expect(not needs_app_gates("pull_request", ["site/src/i18n/content.ts"]), "site only")
    expect(needs_app_gates("pull_request", ["docs/HELP.md", "Vitrine/App/AppDelegate.swift"]),
           "docs plus app")
    expect(needs_app_gates("pull_request", ["scripts/check-perf.py"]), "scripts run in CI")
    expect(needs_app_gates("pull_request", [".github/workflows/ci.yml"]), "workflows")
    expect(needs_app_gates("pull_request", ["Vitrine/Resources/README.md"]), "nested markdown")
    expect(needs_app_gates("pull_request", []), "an empty diff runs everything")
    expect(needs_app_gates("push", ["docs/HELP.md"]), "pushes run everything")
    expect(needs_app_gates("schedule", []), "schedules run everything")
    print("CI change classification passed.")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--event")
    parser.add_argument("--base")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args(argv)

    if arguments.self_test:
        return run_self_test()
    if not arguments.event:
        parser.error("--event is required")
    changed = changed_files(arguments.base) if arguments.base else []
    app = needs_app_gates(arguments.event, changed)
    print(f"{len(changed)} changed file(s); app gates {'required' if app else 'skipped'}.",
          file=sys.stderr)
    print(f"app={'true' if app else 'false'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
