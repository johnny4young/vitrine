#!/usr/bin/env python3
"""Mark appcast entries informational for hosts whose updater cannot install.

Builds before ``FIRST_INSTALLABLE_BUILD`` shipped a Sparkle integration that could
not install anything. The app is sandboxed, but its ``Info.plist`` never set
``SUEnableInstallerLauncherService``, so Sparkle could not reach the Installer
XPC service inside its own framework and fell back to submitting a privileged
installer job. The sandbox denies that (``errAuthorizationDenied``), and the user
sees "An error occurred while launching the installer." every single time.

That installed base cannot be repaired by shipping a fixed build: the updater
doing the work is the broken one already on disk. What it *can* still do is fetch
the appcast and show an alert. Sparkle's ``sparkle:informationalUpdate`` turns
that alert into a download link instead of an install that is guaranteed to fail,
which is the only channel that still reaches those users.

Scoped with ``sparkle:belowVersion`` so it applies to exactly the affected hosts:
newer builds carry a working installer and keep updating in place. The bound is
compared against the host's ``CFBundleVersion``, the same space as the appcast's
``sparkle:version``, so it is a build number and not a marketing version.

Run against the appcast ``generate_appcast`` produced, before it is published:

    python3 scripts/mark-informational-update.py dist/appcast.xml
    python3 scripts/mark-informational-update.py --self-test
"""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"

# The first CFBundleVersion whose Sparkle integration can actually install an
# update — the build that added SUEnableInstallerLauncherService to Info.plist.
# Every host below it gets a download link rather than a failing installer.
#
# Do NOT raise this to track the current release: it is a historical fact about
# when the updater started working, not a "latest version" marker. Lowering or
# removing it silently strands every user still running one of those builds.
FIRST_INSTALLABLE_BUILD = 34


def _qualified(tag: str) -> str:
    return f"{{{SPARKLE_NAMESPACE}}}{tag}"


def _reject_doctype(appcast_xml: str) -> None:
    """Refuse a document that declares a DTD or entities.

    The input is our own `generate_appcast` output on our own runner, so this is
    not the front line — but the stdlib parser expands internal entities, which
    is enough for a billion-laughs blowup, and a DTD is the entry point for
    external-entity reads. A signed appcast needs neither, so rejecting them
    outright is cheaper and more honest than pulling a parser dependency into
    the release path.
    """
    for line in appcast_xml.splitlines():
        stripped = line.strip()
        if stripped.startswith("<!DOCTYPE") or stripped.startswith("<!ENTITY"):
            raise ValueError("appcast must not declare a DTD or XML entities")


def mark_informational(appcast_xml: str, below_build: int = FIRST_INSTALLABLE_BUILD) -> str:
    """Return `appcast_xml` with every item marked informational below `below_build`.

    Idempotent: an item that already carries the marker keeps exactly one, so a
    re-run (or a resumed release job) cannot stack duplicates that Sparkle would
    have to disambiguate.
    """
    _reject_doctype(appcast_xml)
    ElementTree.register_namespace("sparkle", SPARKLE_NAMESPACE)
    root = ElementTree.fromstring(appcast_xml)

    items = root.findall("./channel/item")
    if not items:
        # generate_appcast always emits at least one item for the release being
        # published. None means its output shape changed or the DMG was missing —
        # publishing an unmarked appcast would silently hand the broken installed
        # base an install that fails, so refuse instead.
        raise ValueError("appcast has no <item> entries to mark")

    for item in items:
        existing = item.findall(_qualified("informationalUpdate"))
        for duplicate in existing[1:]:
            item.remove(duplicate)
        informational = existing[0] if existing else ElementTree.SubElement(
            item, _qualified("informationalUpdate")
        )
        informational.clear()
        below = ElementTree.SubElement(informational, _qualified("belowVersion"))
        below.text = str(below_build)

    return ElementTree.tostring(root, encoding="unicode", xml_declaration=True)


def _require(condition: bool, label: str) -> None:
    if not condition:
        raise RuntimeError(f"informational-update self-test failed: {label}")


SAMPLE_APPCAST = """<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>Vitrine</title>
        <item>
            <title>1.0.2</title>
            <link>https://github.com/johnny4young/vitrine/releases/tag/v1.0.2</link>
            <sparkle:version>34</sparkle:version>
            <sparkle:shortVersionString>1.0.2</sparkle:shortVersionString>
            <enclosure url="https://example.invalid/Vitrine-1.0.2.dmg" length="23045012"
                type="application/octet-stream" sparkle:edSignature="UbFfAX1yR+ovj3tv9Zw=="/>
        </item>
    </channel>
</rss>
"""


def run_self_test() -> int:
    marked = mark_informational(SAMPLE_APPCAST)
    root = ElementTree.fromstring(marked)
    item = root.find("./channel/item")
    _require(item is not None, "item survives the rewrite")

    informational = item.findall(_qualified("informationalUpdate"))
    _require(len(informational) == 1, "exactly one informationalUpdate element")
    below = informational[0].findall(_qualified("belowVersion"))
    _require(len(below) == 1, "exactly one belowVersion bound")
    _require(
        below[0].text == str(FIRST_INSTALLABLE_BUILD),
        "bound is the first installable build",
    )

    # The EdDSA signature authenticates the download; rewriting the XML around it
    # must leave it byte-identical or Sparkle rejects the update outright.
    enclosure = item.find("enclosure")
    _require(
        enclosure.get(_qualified("edSignature")) == "UbFfAX1yR+ovj3tv9Zw==",
        "enclosure signature is preserved",
    )
    _require(
        enclosure.get("url") == "https://example.invalid/Vitrine-1.0.2.dmg",
        "enclosure URL is preserved",
    )
    _require(
        item.find(_qualified("version")).text == "34", "item version is preserved"
    )

    twice = mark_informational(marked)
    repeated = ElementTree.fromstring(twice).find("./channel/item")
    _require(
        len(repeated.findall(_qualified("informationalUpdate"))) == 1,
        "re-running does not stack duplicate markers",
    )

    empty = SAMPLE_APPCAST[: SAMPLE_APPCAST.index("<item>")] + "</channel>\n</rss>\n"
    try:
        mark_informational(empty)
    except ValueError:
        pass
    else:
        raise RuntimeError(
            "informational-update self-test failed: an item-less appcast must be rejected"
        )

    billion_laughs = SAMPLE_APPCAST.replace(
        "<rss",
        '<!DOCTYPE rss [<!ENTITY lol "lol"><!ENTITY lol2 "&lol;&lol;">]>\n<rss',
        1,
    )
    try:
        mark_informational(billion_laughs)
    except ValueError:
        pass
    else:
        raise RuntimeError(
            "informational-update self-test failed: a DTD/entity appcast must be rejected"
        )

    print("Informational-update appcast helpers passed.")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "appcast", nargs="?", type=Path, help="the appcast.xml to rewrite in place"
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="validate the rewrite helpers without touching an appcast",
    )
    arguments = parser.parse_args(argv)

    if arguments.self_test:
        return run_self_test()
    if arguments.appcast is None:
        parser.error("an appcast path is required unless --self-test is given")

    original = arguments.appcast.read_text(encoding="utf-8")
    arguments.appcast.write_text(mark_informational(original), encoding="utf-8")
    print(
        f"Marked {arguments.appcast} informational for hosts below build "
        f"{FIRST_INSTALLABLE_BUILD}."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
