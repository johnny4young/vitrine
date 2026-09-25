#!/usr/bin/env python3
"""Require actual passing tests from every selected sanitizer suite in an xcresult."""

from __future__ import annotations

import argparse
import copy
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


MANIFEST = Path(__file__).with_name("sanitizer-suites.json")


class EvidenceError(ValueError):
    """Missing, malformed, skipped, or unsuccessful execution evidence."""


def suites_for(manifest: object, lane: str) -> list[str]:
    if not isinstance(manifest, dict) or set(manifest) != {"asan", "tsan"}:
        raise EvidenceError("manifest must define exactly asan and tsan")
    for name, suites in manifest.items():
        if not isinstance(suites, list) or not suites:
            raise EvidenceError(f"{name}: empty or malformed suite selection")
        if any(
            not isinstance(suite, str)
            or re.fullmatch(r"[A-Za-z0-9_]+Tests/[A-Za-z0-9_]+", suite) is None
            or "UITests/" in suite
            for suite in suites
        ):
            raise EvidenceError(f"{name}: expected bundle/suite unit-test identifiers")
        if len(set(suites)) != len(suites):
            raise EvidenceError(f"{name}: duplicate suite identifiers")
    return manifest[lane]


def verify(tree: object, expected: list[str]) -> dict[str, int]:
    if not expected or len(set(expected)) != len(expected):
        raise EvidenceError("execution policy must contain unique expected suites")
    if not isinstance(tree, dict) or not isinstance(tree.get("testNodes"), list):
        raise EvidenceError("xcresult has no testNodes array")
    counts = dict.fromkeys(expected, 0)

    def walk(node: object) -> None:
        if not isinstance(node, dict):
            raise EvidenceError("malformed test node")
        children = node.get("children", [])
        if not isinstance(children, list):
            raise EvidenceError("malformed test children")
        # Sanitizer reports that do not crash surface as runtime warnings on a
        # passing test, so a warning anywhere disqualifies the lane.
        if node.get("nodeType") == "Runtime Warning":
            raise EvidenceError(f"runtime warning: {node.get('name', '')}")
        identifier = node.get("nodeIdentifierURL", "")
        if not isinstance(identifier, str):
            raise EvidenceError("malformed test identifier")
        url = urlsplit(identifier)
        parts = [unquote(part) for part in url.path.split("/") if part]
        suite = "/".join(parts[1:3]) if len(parts) >= 3 else ""
        if suite in counts:
            if url.scheme != "test" or url.netloc != "com.apple.xcode":
                raise EvidenceError(f"{suite}: unsupported test identifier URL")
            if node.get("result") != "Passed":
                raise EvidenceError(f"{identifier}: result is {node.get('result')!r}, not Passed")
            if node.get("nodeType") == "Test Case":
                if len(parts) < 4:
                    raise EvidenceError(f"{suite}: test case has no method identifier")
                counts[suite] += 1
        for child in children:
            walk(child)

    for node in tree["testNodes"]:
        walk(node)
    missing = [suite for suite, count in counts.items() if count == 0]
    if missing:
        raise EvidenceError("no executed passing test cases for: " + ", ".join(missing))
    return counts


def self_test() -> None:
    expected = ["VitrineDomainTests/TerminalGridTests", "VitrineTests/ANSIParserTests"]

    def suite_node(suite: str) -> dict:
        url = "test://com.apple.xcode/Vitrine/" + suite
        return {
            "nodeType": "Test Suite", "name": "A human-readable label",
            "nodeIdentifierURL": url, "result": "Passed", "children": [{
                "nodeType": "Test Case", "nodeIdentifierURL": url + "/example()",
                "result": "Passed", "children": [{
                    "nodeType": "Arguments", "result": "Passed",
                    "nodeIdentifierURL": url + "/example()?args=synthetic",
                }],
            }],
        }

    tree = {"testNodes": [suite_node(suite) for suite in expected]}
    assert verify(tree, expected) == dict.fromkeys(expected, 1)
    bad_trees = [{}, {"testNodes": []}, {"testNodes": tree["testNodes"][:1]}]
    for result in ["Skipped", "Failed", "Expected Failure", "Not Run", None]:
        bad = copy.deepcopy(tree)
        bad["testNodes"][0]["children"][0]["result"] = result
        bad_trees.append(bad)
    for change in [
        "empty suite", "wrong bundle", "skipped argument", "missing identifier", "runtime warning",
    ]:
        bad = copy.deepcopy(tree)
        node = bad["testNodes"][0]
        if change == "empty suite":
            node["children"] = []
        elif change == "wrong bundle":
            node["children"][0]["nodeIdentifierURL"] = (
                "test://com.apple.xcode/Vitrine/VitrineTests/TerminalGridTests/example()")
        elif change == "skipped argument":
            node["children"][0]["children"][0]["result"] = "Skipped"
        elif change == "runtime warning":
            node["children"][0]["children"].append(
                {"nodeType": "Runtime Warning", "name": "Data race in synthetic()"})
        else:
            del node["children"][0]["nodeIdentifierURL"]
        bad_trees.append(bad)
    for bad in bad_trees:
        try:
            verify(bad, expected)
        except EvidenceError:
            pass
        else:
            raise AssertionError(f"accepted invalid execution evidence: {bad}")
    for selection in [[], [expected[0], expected[0]]]:
        try:
            verify(tree, selection)
        except EvidenceError:
            pass
        else:
            raise AssertionError("accepted empty/duplicate expected selection")
    for suites in [[], ["VitrineTests"], ["VitrineUITests/Example"], ["bad;command/Suite"], [42]]:
        try:
            suites_for({"asan": suites, "tsan": expected}, "asan")
        except EvidenceError:
            pass
        else:
            raise AssertionError("accepted malformed lane selection")
    print(
        "Sanitizer execution guard self-test passed "
        "(including empty/missing/skipped suites and runtime warnings).")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lane", choices=["asan", "tsan"])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--print-selection", action="store_true")
    mode.add_argument("--result-bundle", type=Path)
    mode.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
            return 0
        if args.lane is None:
            parser.error("--lane is required")
        suites = suites_for(json.loads(MANIFEST.read_text()), args.lane)
        if args.print_selection:
            print(" ".join("-only-testing:" + suite for suite in suites))
            return 0
        result = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path",
             str(args.result_bundle), "--compact"], check=True, capture_output=True, text=True)
        counts = verify(json.loads(result.stdout), suites)
        evidence = {"lane": args.lane, "resultBundle": str(args.result_bundle), "passedTests": counts}
        Path(str(args.result_bundle) + ".execution.json").write_text(json.dumps(evidence, indent=2) + "\n")
        for suite, count in counts.items():
            print(f"{args.lane}: {suite}: {count} passing test cases")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: sanitizer execution not qualified: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
