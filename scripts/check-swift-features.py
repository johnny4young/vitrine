#!/usr/bin/env python3
"""Require an upcoming Swift feature in every app-owned module's compiler invocation.

Reads an `xcodebuild` log. Each Swift module compiles through one driver invocation that
names the module (`-module-name X`) and carries every resolved build setting, so the log
is the authoritative record of what the compiler was asked to do, whatever combination of
project settings, xcconfigs, and command-line overrides produced it.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

FEATURE = "MemberImportVisibility"
# Modules the repository owns. Swift packages compile with their own settings.
APP_MODULES = {
    "Vitrine",
    "VitrineCLICore",
    "VitrineDomain",
    "VitrineRendering",
    "VitrineMenuBarHelper",
    "vitrine_cli",
}
MODULE_NAME = re.compile(r"(?:^|\s)-module-name\s+(\S+)")


def modules_without_feature(log: str) -> tuple[set[str], set[str]]:
    """The app-owned modules the log compiles, and those compiled without the feature."""
    seen: set[str] = set()
    missing: set[str] = set()
    for line in log.splitlines():
        if "swiftc" not in line and "swift-frontend" not in line:
            continue
        match = MODULE_NAME.search(line)
        if match is None or match.group(1) not in APP_MODULES:
            continue
        module = match.group(1)
        seen.add(module)
        if f"-enable-upcoming-feature {FEATURE}" not in line:
            missing.add(module)
    return seen, missing


def self_test() -> None:
    log = (
        "swiftc -module-name VitrineDomain -enable-upcoming-feature MemberImportVisibility -O\n"
        "swiftc -module-name Highlightr -O\n"
        "swiftc -module-name Vitrine -enable-upcoming-feature InferIsolatedConformances -O\n"
        "note: -module-name vitrine_cli mentioned in a note, not a compile\n"
    )
    assert modules_without_feature(log) == ({"VitrineDomain", "Vitrine"}, {"Vitrine"})
    assert modules_without_feature("") == (set(), set())
    print("swift feature guard self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.log is None:
        parser.error("a build log is required")
    seen, missing = modules_without_feature(args.log.read_text(encoding="utf-8", errors="replace"))
    if missing:
        print(f"{FEATURE} is off for: {', '.join(sorted(missing))}", file=sys.stderr)
        return 1
    if seen != APP_MODULES:
        absent = ", ".join(sorted(APP_MODULES - seen))
        print(f"the log compiles no Swift for: {absent}; build clean so every module is checked",
              file=sys.stderr)
        return 1
    print(f"{FEATURE} is on for every app-owned module: {', '.join(sorted(seen))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
