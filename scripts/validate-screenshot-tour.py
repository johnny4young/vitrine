#!/usr/bin/env python3
"""Validate and export Vitrine's strict ScreenshotTour xcresult attachments."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

SLUG_PATTERN = re.compile(r"^(?P<slug>\d{2}-[a-z0-9-]+)(?:_\d+_[0-9A-F-]+)?\.png$")
SOURCE_SLUG_PATTERN = re.compile(r'"(\d{2}-[a-z0-9-]+)"')
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class ValidationError(RuntimeError):
    """A visual evidence contract violation."""


def load_expected(path: Path) -> list[str]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        schema_version = payload["schemaVersion"]
        screenshots = payload["screenshots"]
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise ValidationError(f"Unreadable screenshot manifest {path}: {error}") from error

    if schema_version != 1:
        raise ValidationError(f"Unsupported screenshot manifest schema: {schema_version!r}")
    if not isinstance(screenshots, list) or not all(isinstance(item, str) for item in screenshots):
        raise ValidationError("Screenshot manifest must contain a string screenshots array")
    if screenshots != sorted(screenshots):
        raise ValidationError("Screenshot manifest entries must stay sorted")
    if len(screenshots) != len(set(screenshots)):
        raise ValidationError("Screenshot manifest contains duplicate slugs")
    invalid = [slug for slug in screenshots if not re.fullmatch(r"\d{2}-[a-z0-9-]+", slug)]
    if invalid:
        raise ValidationError(f"Screenshot manifest contains invalid slugs: {invalid}")
    return screenshots


def verify_source_contract(source: Path, expected: set[str]) -> None:
    try:
        declared = set(SOURCE_SLUG_PATTERN.findall(source.read_text(encoding="utf-8")))
    except OSError as error:
        raise ValidationError(f"Could not read screenshot tour source {source}: {error}") from error

    missing = sorted(expected - declared)
    untracked = sorted(declared - expected)
    if missing or untracked:
        details = []
        if missing:
            details.append(f"manifest-only: {', '.join(missing)}")
        if untracked:
            details.append(f"source-only: {', '.join(untracked)}")
        raise ValidationError("Screenshot source/manifest drift: " + "; ".join(details))


def png_dimensions(path: Path) -> tuple[int, int]:
    try:
        header = path.read_bytes()[:24]
    except OSError as error:
        raise ValidationError(f"Could not read exported attachment {path}: {error}") from error
    if len(header) < 24 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ValidationError(f"Exported attachment is not a valid PNG: {path}")
    return struct.unpack(">II", header[16:24])


def attachment_slug(suggested_name: str) -> str | None:
    match = SLUG_PATTERN.fullmatch(suggested_name)
    return match.group("slug") if match else None


def export_attachments(result_bundle: Path, destination: Path) -> None:
    if not result_bundle.is_dir():
        raise ValidationError(f"Screenshot result bundle does not exist: {result_bundle}")
    command = [
        "xcrun",
        "xcresulttool",
        "export",
        "attachments",
        "--path",
        str(result_bundle),
        "--output-path",
        str(destination),
    ]
    try:
        subprocess.run(command, check=True)
    except (OSError, subprocess.CalledProcessError) as error:
        raise ValidationError(f"Could not export screenshot attachments: {error}") from error


def collect_evidence(raw: Path, expected: set[str]) -> dict[str, tuple[Path, str]]:
    manifest_path = raw / "manifest.json"
    try:
        groups = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValidationError(f"Could not read xcresult attachment manifest: {error}") from error

    collected: dict[str, tuple[Path, str]] = {}
    unexpected: set[str] = set()
    for group in groups:
        test_identifier = group.get("testIdentifier", "unknown test")
        for attachment in group.get("attachments", []):
            suggested_name = attachment.get("suggestedHumanReadableName", "")
            slug = attachment_slug(suggested_name)
            if slug is None:
                continue
            if slug not in expected:
                unexpected.add(slug)
                continue
            if slug in collected:
                raise ValidationError(f"Duplicate screenshot attachment for {slug}")
            exported_name = attachment.get("exportedFileName")
            if not isinstance(exported_name, str):
                raise ValidationError(f"Attachment {slug} has no exported filename")
            collected[slug] = (raw / exported_name, test_identifier)

    missing = sorted(expected - collected.keys())
    if missing or unexpected:
        details = []
        if missing:
            details.append(f"missing: {', '.join(missing)}")
        if unexpected:
            details.append(f"unexpected: {', '.join(sorted(unexpected))}")
        raise ValidationError("Incomplete screenshot evidence: " + "; ".join(details))
    return collected


def materialize_evidence(
    collected: dict[str, tuple[Path, str]], output: Path
) -> list[dict[str, object]]:
    output.mkdir(parents=True, exist_ok=True)
    summaries: list[dict[str, object]] = []
    hashes: dict[str, str] = {}
    for slug in sorted(collected):
        source, test_identifier = collected[slug]
        width, height = png_dimensions(source)
        if width < 64 or height < 64:
            raise ValidationError(f"Screenshot {slug} is implausibly small: {width}x{height}")
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if digest in hashes:
            raise ValidationError(
                f"Screenshots {hashes[digest]} and {slug} are byte-identical; "
                "the tour likely captured the wrong surface"
            )
        hashes[digest] = slug
        destination = output / f"{slug}.png"
        shutil.copy2(source, destination)
        summaries.append(
            {
                "slug": slug,
                "testIdentifier": test_identifier,
                "width": width,
                "height": height,
                "sha256": digest,
            }
        )

    (output / "manifest.json").write_text(
        json.dumps({"schemaVersion": 1, "screenshots": summaries}, indent=2) + "\n",
        encoding="utf-8",
    )
    return summaries


def self_test() -> None:
    assert attachment_slug("01-welcome_0_ABCDEF12-3456-7890-ABCD-EF1234567890.png") == "01-welcome"
    assert attachment_slug("screenshot_0_ABC.png") is None
    with tempfile.TemporaryDirectory() as directory:
        fixture = Path(directory) / "fixture.png"
        fixture.write_bytes(PNG_SIGNATURE + b"\x00\x00\x00\rIHDR" + struct.pack(">II", 700, 520))
        assert png_dimensions(fixture) == (700, 520)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--result-bundle", type=Path)
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        self_test()
        expected_list = load_expected(arguments.manifest)
        expected = set(expected_list)
        verify_source_contract(arguments.source, expected)
        if arguments.result_bundle is None and arguments.output is None:
            print(f"✓ strict screenshot contract tracks {len(expected)} required states")
            return 0
        if arguments.result_bundle is None or arguments.output is None:
            raise ValidationError("--result-bundle and --output must be provided together")

        with tempfile.TemporaryDirectory(prefix="vitrine-screenshot-attachments-") as directory:
            raw = Path(directory)
            export_attachments(arguments.result_bundle, raw)
            collected = collect_evidence(raw, expected)
            summaries = materialize_evidence(collected, arguments.output)
        print(
            f"✓ exported and validated {len(summaries)} strict screenshots in "
            f"{arguments.output}"
        )
        return 0
    except ValidationError as error:
        print(f"✗ {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
