#!/usr/bin/env python3
"""Keep CI coverage, performance and visual test execution disjoint and nonempty."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import subprocess
import sys
from urllib.parse import unquote, urlsplit


DEDICATED = {
    "performance": ["VitrineTests/PerformanceTests"],
    "goldens": [
        "VitrineTests/GoldenImageTests", "VitrineTests/GoldenValidationTests",
        "VitrineTests/SocialCardGoldenTests",
    ],
}
COVERAGE_BUNDLES = {
    "VitrineTests", "VitrineDomainTests", "VitrineRenderingTests",
    "VitrineCLITests", "VitrineRepositoryTests",
}


def selection(lane: str) -> list[str]:
    if lane == "coverage":
        return ["-skip-testing:" + suite for suites in DEDICATED.values() for suite in suites]
    return ["-only-testing:" + suite for suite in DEDICATED[lane]]


def verify(tree: dict, lane: str) -> dict[str, int]:
    expected = COVERAGE_BUNDLES if lane == "coverage" else set(DEDICATED[lane])
    excluded = {suite for suites in DEDICATED.values() for suite in suites}
    counts = dict.fromkeys(sorted(expected), 0)
    seen: set[str] = set()

    def visit(node: dict) -> None:
        if node.get("result") in {"Failed", "Not Run", "Expected Failure"}:
            raise ValueError("unsuccessful test node: " + str(node.get("nodeIdentifierURL", "")))
        if lane != "coverage" and node.get("result") == "Skipped":
            raise ValueError("skipped node in dedicated lane")
        if node.get("nodeType") == "Test Case":
            identifier = node.get("nodeIdentifierURL", "")
            url = urlsplit(identifier)
            parts = [unquote(part) for part in url.path.split("/") if part]
            if url.scheme != "test" or url.netloc != "com.apple.xcode" or len(parts) < 4:
                raise ValueError("missing or malformed test identifier")
            if identifier in seen:
                raise ValueError("duplicate test case: " + identifier)
            seen.add(identifier)
            bundle, suite = parts[1], "/".join(parts[1:3])
            key = bundle if lane == "coverage" else suite
            if key not in expected or (lane == "coverage" and suite in excluded):
                raise ValueError("unexpected test in lane: " + suite)
            result = node.get("result")
            if result != "Passed" and not (lane == "coverage" and result == "Skipped"):
                raise ValueError(f"{identifier}: {result!r}, expected Passed")
            if result == "Passed":
                counts[key] += 1
        for child in node.get("children", []):
            visit(child)

    for node in tree.get("testNodes", []):
        visit(node)
    missing = [key for key, count in counts.items() if count == 0]
    if missing:
        raise ValueError("no passing tests for: " + ", ".join(missing))
    return counts


def self_test() -> None:
    def case(suite: str, result: str = "Passed") -> dict:
        return {"nodeType": "Test Case", "result": result,
                "nodeIdentifierURL": "test://com.apple.xcode/Vitrine/" + suite + "/example()"}

    for lane in ["coverage", *DEDICATED]:
        suites = [bundle + "/Example" for bundle in sorted(COVERAGE_BUNDLES)] if lane == "coverage" else DEDICATED[lane]
        good = {"testNodes": [case(suite) for suite in suites]}
        assert all(verify(good, lane).values())
        failures = [{}, {"testNodes": []}, {"testNodes": good["testNodes"][1:]}]
        for result in ["Failed", "Not Run", "Expected Failure"]:
            bad = copy.deepcopy(good)
            bad["testNodes"][0]["result"] = result
            failures.append(bad)
        failures.append({"testNodes": good["testNodes"] + [case("UnknownTests/Example")]})
        failures.append({"testNodes": good["testNodes"] * 2})
        bad = copy.deepcopy(good)
        bad["testNodes"][0]["children"] = [{"nodeType": "Arguments", "result": "Failed"}]
        failures.append(bad)
        if lane == "coverage":
            failures.append({"testNodes": good["testNodes"] + [case(DEDICATED["performance"][0])]})
        else:
            bad = copy.deepcopy(good)
            bad["testNodes"][0]["result"] = "Skipped"
            failures.append(bad)
            bad = copy.deepcopy(good)
            bad["testNodes"][0]["children"] = [{"nodeType": "Arguments", "result": "Skipped"}]
            failures.append(bad)
        for bad in failures:
            try:
                verify(bad, lane)
            except ValueError:
                pass
            else:
                raise AssertionError(f"accepted invalid {lane} inventory: {bad}")
    excluded = set(selection("coverage"))
    assert excluded == {flag.replace("-only-testing:", "-skip-testing:") for lane in DEDICATED for flag in selection(lane)}
    print("Test lane guard passed: exact partition; empty, missing, failed and duplicate cases rejected.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lane", choices=["coverage", *DEDICATED])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--selection", action="store_true")
    mode.add_argument("--result-bundle", type=Path)
    mode.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
            return 0
        if not args.lane:
            parser.error("--lane is required")
        if args.selection:
            print(" ".join(selection(args.lane)))
            return 0
        raw = subprocess.check_output([
            "xcrun", "xcresulttool", "get", "test-results", "tests", "--path",
            str(args.result_bundle), "--compact"], text=True)
        counts = verify(json.loads(raw), args.lane)
        evidence = {"lane": args.lane, "passedTests": counts}
        Path(str(args.result_bundle) + ".lane.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(json.dumps(evidence, sort_keys=True))
        return 0
    except (OSError, ValueError, AttributeError, TypeError, subprocess.CalledProcessError) as error:
        print(f"error: test lane not qualified: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
