#!/usr/bin/env python3
"""Five explicit, local CLI workflows. Never installs, activates, or configures clients."""

from __future__ import annotations

import argparse
import json
import struct
import subprocess
import zlib
import sys
from pathlib import Path


class WorkflowError(RuntimeError):
    """A denied, failed, or incomplete CLI invocation is not a completed workflow."""


def invoke(cli: Path, arguments: list[str]) -> dict:
    result = subprocess.run([str(cli), *arguments], capture_output=True, text=True, check=True, timeout=120)
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise WorkflowError("CLI did not return complete JSON") from error
    if not isinstance(payload, dict):
        raise WorkflowError("CLI result must be a JSON object")
    return payload


def regular_file(path: Path) -> Path:
    if path.is_symlink() or not path.is_file():
        raise WorkflowError(f"Expected a regular, non-symlink file: {path}")
    return path


def verify_png(data: bytes, dimensions: list[int]) -> None:
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise WorkflowError("The reported PNG is invalid")
    position = 8
    chunks = []
    while position + 12 <= len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        end = position + 12 + length
        if end > len(data):
            raise WorkflowError("PNG chunk is truncated")
        kind = data[position + 4:position + 8]
        content = data[position + 8:end - 4]
        checksum = struct.unpack(">I", data[end - 4:end])[0]
        if zlib.crc32(kind + content) != checksum:
            raise WorkflowError("PNG chunk checksum is invalid")
        if not chunks:
            if kind != b"IHDR" or length != 13 or list(struct.unpack(">II", content[:8])) != dimensions:
                raise WorkflowError("PNG dimensions do not match the result")
        chunks.append(kind)
        position = end
        if kind == b"IEND":
            if length != 0 or end != len(data):
                raise WorkflowError("PNG end marker is invalid")
            break
    if not chunks or chunks[-1] != b"IEND" or b"IDAT" not in chunks:
        raise WorkflowError("PNG is incomplete")


def verify_render(payload: dict, output: Path) -> None:
    expected_sidecars = [output.with_suffix(ext) for ext in (".md", ".html", ".txt")]
    dimensions = [payload.get("width"), payload.get("height")]
    if (payload.get("command") != "render" or payload.get("status") != "rendered"
            or payload.get("copied") is not False or payload.get("format") != "png"
            or payload.get("output") != str(output)
            or not isinstance(payload.get("sidecars"), list)
            or any(not isinstance(value, str) for value in payload["sidecars"])
            or sorted(payload["sidecars"]) != sorted(map(str, expected_sidecars))
            or any(type(value) is not int or value <= 0 for value in dimensions)):
        raise WorkflowError("Incomplete or unexpected render result")
    verify_png(regular_file(output).read_bytes(), dimensions)
    for sidecar in expected_sidecars:
        if not regular_file(sidecar).read_text(encoding="utf-8").strip():
            raise WorkflowError("An expected sidecar is empty")


def workflow(args: argparse.Namespace) -> Path:
    cli = regular_file(Path(args.cli).expanduser().resolve(strict=True))
    parent = Path(args.parent).expanduser().resolve(strict=True)
    if not parent.is_dir() or args.name in ("", ".", "..") or any(
        char in args.name for char in ("/", "\\", "\0")
    ):
        raise WorkflowError("Choose an existing parent and a single new folder name")
    input_path = regular_file(Path(args.input).expanduser().absolute()) if args.input else None
    recipe = regular_file(Path(args.recipe).expanduser().absolute()) if args.recipe else None
    if args.workflow in ("edit", "render", "terminal") and input_path is None:
        raise WorkflowError("This workflow requires --input")
    if args.workflow in ("recipe", "render") and recipe is None:
        raise WorkflowError("This workflow requires --recipe")
    if args.workflow in ("render", "terminal") and not args.alt_text:
        raise WorkflowError("Supply an explicitly authored --alt-text")
    directory = parent / args.name
    # Reserve a private run directory exclusively; existing directories and symlinks fail.
    directory.mkdir(mode=0o700)
    try:
        if args.workflow == "discover":
            payload = invoke(cli, ["list", "all", "--json"])
            for catalog in ("themes", "languages", "formats", "profiles", "presets"):
                entries = payload.get(catalog)
                if not isinstance(entries, list) or not entries or any(
                    not isinstance(entry, dict) or not isinstance(entry.get("id"), str)
                    or not entry["id"] for entry in entries
                ):
                    raise WorkflowError(f"Missing or incomplete catalog: {catalog}")
        elif args.workflow == "recipe":
            validation = invoke(cli, ["recipe", "validate", str(recipe), "--json"])
            payload = invoke(cli, ["recipe", "show", str(recipe), "--json"])
            if (validation.get("valid") is not True
                    or validation.get("format") != "vitrine.workspace-recipe"
                    or validation.get("schemaVersion") != 1
                    or payload.get("format") != "vitrine.workspace-recipe"
                    or payload.get("schemaVersion") != 1
                    or not isinstance(payload.get("recipe"), dict)
                    or not payload["recipe"].get("name")
                    or payload["recipe"]["name"] != validation.get("name")):
                raise WorkflowError("Recipe validation or inspection is incomplete")
        elif args.workflow == "edit":
            payload = invoke(cli, ["render", str(input_path), "--edit", "--json"])
            if (payload.get("command") != "render" or payload.get("status") != "opened_editor"
                    or payload.get("copied") is not False or payload.get("sidecars") != []
                    or any(payload.get(key) is not None for key in ("output", "format", "width", "height"))):
                raise WorkflowError("Editor handoff must not render, copy, or write outputs")
        else:
            output = directory / "snapshot.png"
            arguments = ["render", str(input_path), "--out", str(output), "--format", "png",
                         "--no-overwrite", "--sidecars", "all", "--alt-text", args.alt_text, "--json"]
            if args.workflow == "render":
                arguments += ["--recipe", str(recipe)]
            else:
                # This fixture deliberately hides its second rendered terminal row.
                arguments += ["--language", "terminal", "--terminal-width", "80", "--redact-lines", "2"]
            payload = invoke(cli, arguments)
            verify_render(payload, output)
            if args.workflow == "terminal" and any(
                "PRIVATE_REDACTED_SENTINEL" in output.with_suffix(ext).read_text(encoding="utf-8")
                for ext in (".md", ".html", ".txt")
            ):
                raise WorkflowError("Withheld synthetic terminal row reappeared")
        with (directory / "result.json").open("x", encoding="utf-8") as stream:
            json.dump(payload, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
        # This marker means every required result was checked, not merely that the process exited.
        with (directory / "COMPLETE").open("x", encoding="utf-8") as stream:
            stream.write(args.workflow + "\n")
        return directory
    except Exception:
        # Do not erase files that a concurrent caller might have added. Retain failed runs
        # without COMPLETE; choose a fresh name when retrying, never overwrite them.
        print(f"Incomplete run retained without COMPLETE: {directory}", file=sys.stderr)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workflow", choices=["discover", "recipe", "edit", "render", "terminal"])
    parser.add_argument("--cli", required=True, help="Explicit path to an existing Vitrine CLI")
    parser.add_argument("--parent", required=True, help="Existing output parent directory")
    parser.add_argument("--name", required=True, help="New run folder name; existing paths fail")
    parser.add_argument("--input", help="Explicit input file, never a repository scan")
    parser.add_argument("--recipe", help="Explicit workspace recipe")
    parser.add_argument("--alt-text", help="Authored description for render workflows")
    try:
        print(json.dumps({"status": "complete", "directory": str(workflow(parser.parse_args()))}))
        return 0
    except subprocess.SubprocessError as error:
        # Do not echo argv or captured stderr: descriptions and filenames may be private.
        status = getattr(error, "returncode", None)
        print(f"Workflow stopped: CLI timed out or failed (exit {status})", file=sys.stderr)
        return 1
    except ValueError:
        print("Workflow stopped: result data is unreadable", file=sys.stderr)
        return 1
    except (OSError, WorkflowError) as error:
        print(f"Workflow stopped: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
