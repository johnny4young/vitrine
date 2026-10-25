#!/usr/bin/env python3
"""Probe inert rule-store selection and real waiter contracts without a test-framework host."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import signal
import subprocess
import sys
import time


PACKAGE = '''// swift-tools-version: 6.2
import PackageDescription
let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self), .enableUpcomingFeature("MemberImportVisibility"),
]
let package = Package(
    name: "WebRuleStoreHarness", platforms: [.macOS(.v15)],
    targets: [
        .target(name: "VitrineDomain"),
        .target(name: "VitrineRendering", dependencies: ["VitrineDomain"], swiftSettings: settings),
        .executableTarget(name: "WebRuleStoreProbe", dependencies: ["VitrineRendering"], swiftSettings: PROBE_SETTINGS),
    ], swiftLanguageModes: [.v6])
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-checkout", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--developer-dir", type=Path, default=Path("/Applications/Xcode.app/Contents/Developer"))
    parser.add_argument("--waiter-only", action="store_true", help="Probe the retained base's waiter contracts only")
    args = parser.parse_args()
    if sys.platform != "darwin":
        raise RuntimeError("This harness requires full Xcode on macOS")
    root = args.source_checkout.resolve(strict=True)
    output = args.output.resolve()
    if output.exists():
        raise RuntimeError("Use a fresh output directory; existing evidence is never replaced")
    swift = args.developer_dir / "Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
    if not swift.is_file():
        raise RuntimeError("Full Xcode Swift is unavailable; do not change system Xcode to run this harness")
    output.mkdir(parents=True)
    package = output / "Package"
    source = package / "Sources"
    for directory in [source / "VitrineDomain", source / "VitrineRendering", source / "WebRuleStoreProbe"]:
        directory.mkdir(parents=True)
    manifest = {}

    def copy(relative, destination):
        path = root / relative
        if path.is_symlink() or not path.resolve(strict=True).is_relative_to(root):
            raise RuntimeError(f"Source path escapes its checkout: {relative}")
        text = path.read_text()
        if re.search(r"(?m)^\s*(?:@\w+\s+)?import\s+(?:WebKit|AppKit|SwiftUI|Testing|XCTest)\b", text):
            raise RuntimeError(f"Unexpected UI framework dependency: {relative}")
        manifest[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(text)

    for path in sorted((root / "VitrineDomain").rglob("*.swift")):
        copy(str(path.relative_to(root)), source / "VitrineDomain" / path.relative_to(root / "VitrineDomain"))
    copy("VitrineRendering/Rendering/RenderBudget.swift", source / "VitrineRendering/RenderBudget.swift")
    copy("Vitrine/WebRendering/WebLoadWaiter.swift", source / "WebRuleStoreProbe/WebLoadWaiter.swift")
    config_path = root / "Vitrine/WebRendering/WebSnapshotConfig.swift"
    config = config_path.read_text()
    start = config.index("enum WebSnapshotError: Error, Equatable {")
    end = config.index("\n}\n", start) + 3
    declaration = config[start:end]
    (source / "WebRuleStoreProbe/WebSnapshotError.swift").write_text("import VitrineRendering\n\n" + declaration)
    manifest[str(config_path.relative_to(root))] = hashlib.sha256(config_path.read_bytes()).hexdigest()
    manifest["extracted-WebSnapshotError-declaration"] = hashlib.sha256(declaration.encode()).hexdigest()
    if not args.waiter_only:
        copy("Vitrine/WebRendering/WebContentRuleListStoreSource.swift", source / "WebRuleStoreProbe/WebContentRuleListStoreSource.swift")
    fixture = Path(__file__).resolve().parent / "fixtures/web-rule-store-probe.swift"
    text = fixture.read_text()
    if re.search(r"(?m)^\s*import\s+(?:WebKit|AppKit|SwiftUI|Testing|XCTest)\b", text):
        raise RuntimeError("Unexpected UI/test framework in the standalone probe")
    manifest["runner-fixture/web-rule-store-probe.swift"] = hashlib.sha256(fixture.read_bytes()).hexdigest()
    (source / "WebRuleStoreProbe/Probe.swift").write_text(text)
    flags = 'settings' if args.waiter_only else 'settings + [.define("INCLUDE_STORE_SELECTOR")]'
    (package / "Package.swift").write_text(PACKAGE.replace("PROBE_SETTINGS", flags))
    (output / "source-sha256.json").write_text(json.dumps(manifest, indent=2) + "\n")
    for name in ["home", "tmp", "cache", "clang-cache", "swift-cache"]:
        (output / name).mkdir()
    user = pwd.getpwuid(os.getuid()).pw_name
    env = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "USER": user, "LOGNAME": user,
        "HOME": str(output / "home"), "CFFIXED_USER_HOME": str(output / "home"),
        "TMPDIR": str(output / "tmp") + "/", "XDG_CACHE_HOME": str(output / "cache"),
        "CLANG_MODULE_CACHE_PATH": str(output / "clang-cache"),
        "SWIFTPM_MODULECACHE_OVERRIDE": str(output / "swift-cache"),
        "DEVELOPER_DIR": str(args.developer_dir), "LC_ALL": "en_US.UTF-8",
    }
    command = [str(swift), "run", "--package-path", str(package), "--scratch-path", str(output / "Build"),
               "--cache-path", str(output / "cache"), "--disable-automatic-resolution", "--jobs", "1",
               "WebRuleStoreProbe"]
    metadata = {"argv": command, "source_checkout": str(root), "waiter_only": args.waiter_only,
                "expected": "Standalone factory/waiter contract probe; no test framework, WebKit adapter, store, view or app host",
                "timeout_seconds": 180, "environment_allowlist": env}
    record = output / "command.json"
    record.write_text(json.dumps(metadata, indent=2) + "\n")
    started = time.monotonic()
    with (output / "stdout.log").open("w") as stdout, (output / "stderr.log").open("w") as stderr:
        process = subprocess.Popen(command, cwd=package, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
        metadata["pid"] = process.pid
        record.write_text(json.dumps(metadata, indent=2) + "\n")
        try:
            metadata["exit_code"] = process.wait(timeout=180)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            metadata["interrupted_or_timed_out"] = True
            if process.poll() is None and os.getpgid(process.pid) == process.pid:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            metadata["exit_code"] = process.returncode
    metadata["duration_seconds_not_benchmark"] = time.monotonic() - started
    record.write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"output": str(output), "exit_code": metadata["exit_code"],
                      "waiter_only": args.waiter_only, "scope": metadata["expected"]}, indent=2))
    if metadata["exit_code"] != 0:
        raise RuntimeError("Standalone probe failed; preserve logs and diagnose before a fresh run")


    receipts = []
    for line in (output / "stdout.log").read_text().splitlines():
        if line.startswith("{"):
            receipts.append(json.loads(line))
    summaries = [r for r in receipts if r.get("kind") == "summary"]
    boundaries = [r for r in receipts if r.get("kind") == "framework-boundary"]
    expected = {
        "waiter-early-outcome", "waiter-first-outcome", "waiter-concurrent-rejection",
        "waiter-timeout", "waiter-pending-cancellation", "waiter-pre-cancellation",
    }
    if not args.waiter_only:
        expected |= {"selector-default", "selector-directory", "selector-missing-default", "selector-missing-directory"}
        expected |= {f"selector-invalid-{i}" for i in range(5)}
    if len(summaries) != 1 or len(boundaries) != 2:
        raise RuntimeError("Missing standalone oracle or framework-boundary receipt")
    summary = summaries[0]
    if (summary.get("status") != "passed" or set(summary.get("cases", [])) != expected
            or len(summary.get("cases", [])) != len(expected)
            or {b.get("phase") for b in boundaries} != {"before", "after"}
            or any(b.get("webKitImages") != [] for b in boundaries)):
        raise RuntimeError("Incomplete contract inventory or WebKit framework boundary failed")
    metadata["receipt_validated"] = True
    metadata["oracles"] = summary
    record.write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"validated_contract_cases": len(expected), "checks": summary["checks"],
                      "framework_boundaries_passed": 2}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Hostless rule-store validation failed: {error}", file=sys.stderr)
        sys.exit(1)
