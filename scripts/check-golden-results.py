#!/usr/bin/env python3
"""Fail closed unless every committed visual scenario was actually compared."""
from __future__ import annotations

import argparse
import copy
import json
import re
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path


IMAGE_KEYS = {"osVersion", "osBuild", "architecture", "swiftVersion", "xcodeBuild", "sdkBuild"}


def expected_results(root: Path) -> dict[tuple[str, str], dict]:
    expected = {}
    for kind, directory in [("export", "Golden"), ("social", "SocialCards")]:
        folder = root / directory
        manifest = json.loads((folder / "manifest.json").read_text())
        image = manifest["pinnedImage"]
        if manifest["schema"] != 2 or set(image) != IMAGE_KEYS or any(
            not isinstance(value, str) or not value or value == "unknown" for value in image.values()
        ):
            raise ValueError(f"{directory}: baseline has no qualified environment")
        scenarios = manifest["scenarios"]
        if not isinstance(scenarios, dict) or not scenarios:
            raise ValueError(f"{directory}: empty scenario set")
        if set(scenarios) != {file.stem for file in folder.glob("*.png")}:
            raise ValueError(f"{directory}: fixture/manifest scenario mismatch")
        for scenario in scenarios:
            if re.fullmatch(r"[a-z0-9-]+", scenario) is None:
                raise ValueError("invalid scenario identifier")
            record = scenarios[scenario]
            data = (folder / f"{scenario}.png").read_bytes()
            if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
                raise ValueError(f"{directory}/{scenario}: invalid PNG")
            width, height = struct.unpack(">II", data[16:24])
            if (width, height) != (record["width"], record["height"]) or min(width, height) == 0:
                raise ValueError(f"{directory}/{scenario}: dimensions disagree with manifest")
            if re.fullmatch(r"[0-9a-f]{64}", record["configFingerprint"]) is None:
                raise ValueError(f"{directory}/{scenario}: invalid config fingerprint")
            expected[(kind, scenario)] = image
    return expected


def verify(log: str, expected: dict[tuple[str, str], dict]) -> None:
    if not expected or {kind for kind, _ in expected} != {"export", "social"}:
        raise ValueError("both export and social-card scenarios are required")
    seen = set()
    for line in log.splitlines():
        if "GOLDEN SKIP" in line or "GOLDEN SMOKE" in line:
            raise ValueError("strict lane performed smoke or skipped comparison")
        if not line.startswith("GOLDEN RESULT "):
            continue
        receipt = json.loads(line.removeprefix("GOLDEN RESULT "))
        key = (receipt["kind"], receipt["scenario"])
        if key not in expected or key in seen or receipt["image"] != expected[key]:
            raise ValueError(f"unexpected, duplicate or unqualified comparison: {key}")
        seen.add(key)
    if seen != set(expected):
        raise ValueError(f"missing executed comparisons: {sorted(set(expected) - seen)}")


def self_test() -> None:
    image = dict.fromkeys(IMAGE_KEYS, "synthetic")
    expected = {("export", "example"): image, ("social", "default-card"): image}
    rows = [{"kind": kind, "scenario": scenario, "image": image} for kind, scenario in expected]

    def log(records: list[dict]) -> str:
        return "\n".join("GOLDEN RESULT " + json.dumps(row) for row in records)

    verify(log(rows), expected)
    changed = copy.deepcopy(rows)
    changed[0]["image"]["osBuild"] = "unqualified"
    for invalid in ["", log(rows[:1]), log(rows + rows), log(changed), log(rows) + "\nGOLDEN SMOKE x"]:
        try:
            verify(invalid, expected)
        except ValueError:
            pass
        else:
            raise AssertionError("accepted empty, omitted, duplicated, smoke or unqualified evidence")
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        for directory in ["Golden", "SocialCards"]:
            folder = root / directory
            folder.mkdir()
            manifest = {"schema": 2, "pinnedImage": image, "scenarios": {
                "example": {"width": 1, "height": 1, "configFingerprint": "a" * 64}}}
            (folder / "manifest.json").write_text(json.dumps(manifest))
            (folder / "example.png").write_bytes(b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR" + struct.pack(">II", 1, 1))
        assert len(expected_results(root)) == 2
        (root / "SocialCards/example.png").unlink()
        try:
            expected_results(root)
        except ValueError:
            pass
        else:
            raise AssertionError("accepted missing social-card PNG")
    print("Golden execution guard self-test passed.")


def export_recording(bundle: Path, destination: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="vitrine-golden-attachments-") as temporary:
        raw = Path(temporary) / "raw"
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                        "--output-path", str(raw)], check=True)
        staged = Path(temporary) / "fixtures"
        seen = set()
        for group in json.loads((raw / "manifest.json").read_text()):
            for attachment in group["attachments"]:
                name = attachment.get("suggestedHumanReadableName", "")
                match = re.fullmatch(r"(export|social)-([a-z0-9-]+)(?:_\d+_[0-9A-F-]+)?\.(png|json)", name)
                if match is None:
                    continue
                kind, stem, extension = match.groups()
                folder = "Golden" if kind == "export" else "SocialCards"
                target = staged / folder / f"{stem}.{extension}"
                if target in seen:
                    raise ValueError(f"duplicate recorder attachment: {name}")
                source = (raw / attachment["exportedFileName"]).resolve()
                if not source.is_relative_to(raw.resolve()):
                    raise ValueError("attachment escaped export directory")
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
                seen.add(target)
        expected_results(staged)  # Require complete PNG sets and both provenance manifests.
        for folder in ["Golden", "SocialCards"]:
            # A recording is the complete baseline: drop fixtures it no longer produces.
            for stale in [*(destination / folder).glob("*.png"), destination / folder / "manifest.json"]:
                stale.unlink(missing_ok=True)
            shutil.copytree(staged / folder, destination / folder, dirs_exist_ok=True)
        print(f"Exported complete golden candidates to {destination}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", type=Path, default=Path("Tests/Fixtures"))
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--log", type=Path)
    mode.add_argument("--self-test", action="store_true")
    mode.add_argument("--export-recording", type=Path)
    mode.add_argument("--check-fixtures", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.export_recording:
        export_recording(args.export_recording, args.fixtures)
        return
    expected = expected_results(args.fixtures)
    if args.check_fixtures:
        print(f"Verified {len(expected)} fixtures and both environment manifests (not pixel qualification).")
        return
    verify(args.log.read_text(), expected)
    print(f"Qualified {len(expected)} strict comparisons, including social card.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"error: golden execution not qualified: {error}")
