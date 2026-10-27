#!/usr/bin/env python3
"""Fail a release whose appcast would offer the update to Macs that cannot run it.

Sparkle hosts on an older macOS or an Intel Mac stay on their last compatible build
only when every appcast item carries the deployment floor and the Apple-silicon
requirement. `generate_appcast` derives both from the app it reads, so this check
catches a build that quietly regained an Intel slice or a lower floor.

    python3 scripts/check-appcast-requirements.py --minimum-system-version 26.0 dist/appcast.xml
    python3 scripts/check-appcast-requirements.py --self-test
"""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def _text(item: ElementTree.Element, tag: str) -> str:
    element = item.find(f"{{{SPARKLE_NAMESPACE}}}{tag}")
    return (element.text or "").strip() if element is not None else ""


def appcast_problems(appcast_xml: str, minimum_system_version: str) -> list[str]:
    if "<!DOCTYPE" in appcast_xml or "<!ENTITY" in appcast_xml:
        return ["appcast must not declare a DTD or XML entities"]
    items = ElementTree.fromstring(appcast_xml).findall("./channel/item")
    if not items:
        return ["appcast has no items"]
    problems = []
    for item in items:
        name = _text(item, "shortVersionString") or _text(item, "version") or "item"
        found_floor = _text(item, "minimumSystemVersion")
        if found_floor != minimum_system_version:
            problems.append(
                f"{name}: minimumSystemVersion is {found_floor or 'missing'}, "
                f"expected {minimum_system_version}"
            )
        requirements = [
            value.strip().lower() for value in _text(item, "hardwareRequirements").split(",")
        ]
        if "arm64" not in requirements:
            problems.append(f"{name}: hardwareRequirements must include arm64")
    return problems


SAMPLE_APPCAST = """<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <item>
            <sparkle:version>40</sparkle:version>
            <sparkle:shortVersionString>1.4.0</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
        </item>
    </channel>
</rss>
"""


def run_self_test() -> int:
    def expect(condition: bool, label: str) -> None:
        if not condition:
            raise RuntimeError(f"appcast-requirements self-test failed: {label}")

    expect(appcast_problems(SAMPLE_APPCAST, "26.0") == [], "a compliant item passes")
    expect(len(appcast_problems(SAMPLE_APPCAST, "27.0")) == 1, "a different floor fails")
    intel = SAMPLE_APPCAST.replace(
        "<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>", ""
    )
    expect(len(appcast_problems(intel, "26.0")) == 1, "a missing arm64 requirement fails")
    empty = SAMPLE_APPCAST[: SAMPLE_APPCAST.index("<item>")] + "</channel>\n</rss>\n"
    expect(appcast_problems(empty, "26.0") == ["appcast has no items"], "no items fails")
    doctype = SAMPLE_APPCAST.replace("<rss", '<!DOCTYPE rss [<!ENTITY a "a">]>\n<rss', 1)
    expect(len(appcast_problems(doctype, "26.0")) == 1, "a DTD is rejected")
    print("Appcast requirement checks passed.")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("appcast", nargs="?", type=Path)
    parser.add_argument("--minimum-system-version")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args(argv)

    if arguments.self_test:
        return run_self_test()
    if arguments.appcast is None or not arguments.minimum_system_version:
        parser.error("an appcast path and --minimum-system-version are required")

    problems = appcast_problems(
        arguments.appcast.read_text(encoding="utf-8"), arguments.minimum_system_version
    )
    for problem in problems:
        print(f"::error title=Appcast requirements::{problem}")
    if problems:
        return 1
    print(f"Every appcast item requires macOS {arguments.minimum_system_version}+ on arm64.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
