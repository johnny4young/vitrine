#!/usr/bin/env python3
"""Choose the UI tests a pull request runs, and whether it runs the visual tour.

A pull request runs the smoke list (`UITests/SmokeTests.txt`), every UI test whose body it
changes, and the purge class that must run last. A change to shared UI-test infrastructure
runs the whole suite. Every other event runs the whole suite and the tour.

    python3 scripts/select-ui-tests.py --event pull_request --base <sha> [--head <rev>]
    python3 scripts/select-ui-tests.py --self-test

Prints `ui_tests=<Class/test ...>` (empty means the whole suite) and `visual=true|false`,
ready to append to `$GITHUB_OUTPUT`.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SMOKE_LIST = "UITests/SmokeTests.txt"
PURGE = "ZZDefaultsSuitePurgeUITests"
TOUR = "ScreenshotTourUITests"
# Changes here can affect any journey, so the whole suite and the tour run.
SHARED = (
    "UITests/Robots/", "UITests/VitrineUITestSupport.swift", "project.yml", "Makefile",
    ".github/workflows/ci.yml", "scripts/select-ui-tests.py",
    "scripts/check-ui-test-environment.py", "scripts/qualify-ui-display.swift",
)
TOUR_FILES = (
    "UITests/ScreenshotTourUITests.swift", "UITests/ScreenshotTourManifest.json",
    "scripts/validate-screenshot-tour.py",
)
CLASS = re.compile(r"^\s*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b")
TEST = re.compile(r"^(\s*)(?:@\w+(?:\([^)]*\))?\s+)*(?:\w+\s+)*func\s+(test\w*)\s*[(<]")
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


def smoke(text: str) -> list[str]:
    return [line.strip() for line in text.splitlines()
            if line.strip() and not line.lstrip().startswith("#")]


def is_shared(path: str) -> bool:
    return any(path == item or (item.endswith("/") and path.startswith(item)) for item in SHARED)


def touched(source: str, lines: set[int]) -> set[str]:
    """`Class/test` ids whose bodies contain `lines`; a line outside a test body names its class.

    A test body ends at the closing brace at its own indentation, which swift-format keeps.
    """
    owners: list[tuple[str | None, str | None]] = []
    current_class: str | None = None
    current_test: str | None = None
    test_indent = 0
    for text in source.splitlines():
        if match := CLASS.match(text):
            current_class, current_test = match.group(1), None
        elif current_test is None and current_class and (match := TEST.match(text)):
            current_test, test_indent = match.group(2), len(match.group(1))
        owners.append((current_class, current_test))
        indent = len(text) - len(text.lstrip())
        stripped = text.strip()
        if current_test and indent == test_indent and (
                stripped.startswith("}") or stripped.endswith("}")):
            current_test = None
    found: set[str] = set()
    for line in lines:
        test_class, test = owners[min(max(line, 1), len(owners)) - 1] if owners else (None, None)
        if test_class is None:
            continue
        found.add(f"{test_class}/{test}" if test else test_class)
    return found


def select(changed: dict[str, set[int]], sources: dict[str, str], smoke_ids: list[str]
           ) -> tuple[list[str], bool]:
    """The ids to run (empty for the whole suite) and whether the tour runs."""
    visual = any(path in TOUR_FILES or is_shared(path) for path in changed)
    if any(is_shared(path) for path in changed):
        return [], True
    chosen = set(smoke_ids)
    for path, lines in changed.items():
        if not (path.startswith("UITests/") and path.endswith(".swift")):
            continue
        source = sources.get(path)
        if source is None:
            continue
        if not any(CLASS.match(line) for line in source.splitlines()):
            return [], True  # A helper file outside the shared list.
        chosen |= {item for item in touched(source, lines) if not item.startswith(TOUR)}
    whole = {item for item in chosen if "/" not in item}
    chosen = {item for item in chosen if "/" not in item or item.split("/")[0] not in whole}
    chosen.discard(PURGE)
    return sorted(chosen) + [PURGE], visual


def changed_lines(base: str, head: str = "HEAD") -> dict[str, set[int]]:
    names = subprocess.run(
        ["git", "diff", "--name-only", "--no-renames", f"{base}...{head}"],
        check=True, capture_output=True, text=True, cwd=ROOT).stdout.split()
    result: dict[str, set[int]] = {name: set() for name in names}
    diff = subprocess.run(
        ["git", "diff", "-U0", "--no-renames", f"{base}...{head}", "--", "UITests"],
        check=True, capture_output=True, text=True, cwd=ROOT).stdout
    path = None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = None if line == "+++ /dev/null" else line.removeprefix("+++ b/")
        elif path and (match := HUNK.match(line)):
            start, count = int(match.group(1)), int(match.group(2) or "1")
            result.setdefault(path, set()).update(range(start, start + max(count, 1)))
    return result


def show(revision: str, path: str) -> str | None:
    result = subprocess.run(["git", "show", f"{revision}:{path}"], capture_output=True,
                            text=True, cwd=ROOT)
    return result.stdout if result.returncode == 0 else None


def run_self_test() -> int:
    def expect(condition: bool, label: str) -> None:
        if not condition:
            raise RuntimeError(f"select-ui-tests self-test failed: {label}")

    source = "\n".join([
        "import XCTest",                                  # 1
        "final class VitrineUITests: XCTestCase {",       # 2
        "    @MainActor",                                 # 3
        "    func testAlpha() {",                         # 4
        "        let x = 1",                              # 5
        "    }",                                          # 6
        "    func testBeta() throws {",                   # 7
        "        let y = 2",                              # 8
        "    }",                                          # 9
        "    private func helper() {}",                   # 10
        "    func testGamma() {",                         # 11
        "        func local() -> Int { 3 }",              # 12
        "        let z = local()",                        # 13
        "    }",                                          # 14
        "    override func setUpWithError() throws {",    # 15
        "        continueAfterFailure = false",           # 16
        "    }",                                          # 17
        "    private let timeout = 5.0",                  # 18
        "}",                                              # 19
    ])
    smoke_ids = ["VitrineUITests/testSmoke"]
    path = "UITests/VitrineUITests.swift"
    ids, visual = select({path: {5}}, {path: source}, smoke_ids)
    expect(ids == ["VitrineUITests/testAlpha", "VitrineUITests/testSmoke", PURGE],
           f"a changed test body runs that test with the smoke list: {ids}")
    expect(not visual, "a smoke-suite edit does not run the tour")
    ids, _ = select({path: {10}}, {path: source}, smoke_ids)
    expect(ids == ["VitrineUITests", PURGE], f"a helper change runs its class: {ids}")
    ids, _ = select({path: {13}}, {path: source}, smoke_ids)
    expect(ids == ["VitrineUITests/testGamma", "VitrineUITests/testSmoke", PURGE],
           f"a line after a nested function stays in its test: {ids}")
    for line in (16, 18):
        ids, _ = select({path: {line}}, {path: source}, smoke_ids)
        expect(ids == ["VitrineUITests", PURGE], f"class scope after a test runs the class: {ids}")
    ids, _ = select({"Vitrine/App/AppDelegate.swift": set()}, {}, smoke_ids)
    expect(ids == ["VitrineUITests/testSmoke", PURGE], "product changes run the smoke list")
    expect(select({"UITests/Robots/EditorRobot.swift": {1}}, {}, smoke_ids) == ([], True),
           "shared UI-test code runs the whole suite and the tour")
    expect(select({"project.yml": set()}, {}, smoke_ids) == ([], True), "project.yml runs all")
    tour = "UITests/ScreenshotTourUITests.swift"
    tour_source = "final class ScreenshotTourUITests: XCTestCase {\n    func testTour() {}\n}"
    ids, visual = select({tour: {2}}, {tour: tour_source}, smoke_ids)
    expect(visual and ids == ["VitrineUITests/testSmoke", PURGE],
           f"tour edits run the tour, not tour cases in the UI job: {ids}")
    helper = "UITests/NewHelper.swift"
    expect(select({helper: {1}}, {helper: "extension XCTestCase {}"}, smoke_ids) == ([], True),
           "a new non-test UI file runs the whole suite")
    expect(smoke("# note\nA/testB\n\n") == ["A/testB"], "the smoke list skips comments")
    print("UI test selection self-test passed.")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--event")
    parser.add_argument("--base")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args(argv)
    if arguments.self_test:
        return run_self_test()
    if not arguments.event:
        parser.error("--event is required")
    if arguments.event != "pull_request" or not arguments.base:
        ids, visual, reason = [], True, f"{arguments.event} runs the whole suite and the tour"
    else:
        try:
            changed = changed_lines(arguments.base, arguments.head)
            sources = {path: show(arguments.head, path) for path in changed
                       if path.startswith("UITests/") and path.endswith(".swift")}
            sources = {path: text for path, text in sources.items() if text is not None}
            ids, visual = select(changed, sources, smoke((ROOT / SMOKE_LIST).read_text()))
            reason = f"{len(ids)} selected" if ids else "shared UI-test code changed"
        except Exception as error:  # Any failure runs everything rather than failing the job.
            ids, visual, reason = [], True, f"selection failed ({error}); running everything"
    print(f"UI tests: {reason}; visual tour {'runs' if visual else 'skipped'}.", file=sys.stderr)
    print(f"ui_tests={' '.join(ids)}")
    print(f"visual={'true' if visual else 'false'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
