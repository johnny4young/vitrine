#!/usr/bin/env python3
"""Run controlled WebKit tests and require every expected xcresult test receipt."""

import argparse
import copy
from contextlib import contextmanager
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    "controlledRedirectProducesARealImage()",
    "crossHostSignInSessionIsAvailableToTheNextCapture()",
    "privateRedirectFailsBeforeReachingTheDestination()",
    "privateResourcesAreBlockedWithAReachablePositiveControl()",
    "cancellationStopsAnActuallyPendingLoad()",
    "loopbackSubresourcesRequireExplicitOptIn()",
    "pendingLoadHonorsItsTimeout()",
    "realFullPageCaptureHonorsTheHeightCap()",
    "clearingSessionsRemovesCachedPrivateResponses()",
}
PREFIX = "WebCaptureIntegrationTests/"


def validate(payload):
    found = {}

    def visit(node):
        identifier = node.get("nodeIdentifier", "")
        if node.get("nodeType") == "Test Case" and identifier.startswith(PREFIX):
            name = identifier.removeprefix(PREFIX)
            if name in found:
                raise ValueError(f"Duplicate controlled test: {name}")
            found[name] = node.get("result")
        for child in node.get("children", []):
            visit(child)

    for node in payload.get("testNodes", []):
        visit(node)
    if set(found) != EXPECTED:
        raise ValueError(f"Controlled test inventory mismatch: {found}")
    if any(result != "Passed" for result in found.values()):
        raise ValueError(f"Controlled test skipped or failed: {found}")
    return found


def receipts(bundle):
    result = subprocess.run([
        "xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle),
        "--compact",
    ], check=True, capture_output=True, text=True)
    payload = json.loads(result.stdout)
    validate(payload)
    return payload


def self_test():
    good = {"testNodes": [{"children": [
        {"nodeIdentifier": PREFIX + name, "nodeType": "Test Case", "result": "Passed"}
        for name in sorted(EXPECTED)
    ]}]}
    validate(good)
    bad = [{}, {"testNodes": []}]
    omitted = copy.deepcopy(good)
    omitted["testNodes"][0]["children"].pop()
    bad.append(omitted)
    duplicate = copy.deepcopy(good)
    duplicate["testNodes"][0]["children"].append(duplicate["testNodes"][0]["children"][0])
    bad.append(duplicate)
    for status in ("Skipped", "Failed", "Expected Failure", None):
        altered = copy.deepcopy(good)
        altered["testNodes"][0]["children"][0]["result"] = status
        bad.append(altered)
    for payload in bad:
        try:
            validate(payload)
        except ValueError:
            continue
        raise AssertionError("Accepted invalid WebKit test receipts")
    print(f"Controlled WebKit receipt guard: {len(bad)} fail-closed cases passed")


@contextmanager
def loopback_fixture(output, *, script=None, startup_timeout=10):
    port_file = output / "port"
    log_path = output / "fixture.log"
    script = script or ROOT / "scripts/web-capture-fixture.py"
    with log_path.open("w") as log:
        log.write("Starting isolated loopback fixture\n")
        log.flush()
        fixture = subprocess.Popen([
            sys.executable, "-u", str(script), "--port-file", str(port_file),
        ], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + startup_timeout
            while not port_file.exists():
                status = fixture.poll()
                if status is not None or time.monotonic() >= deadline:
                    reason = f"exit {status}" if status is not None else "readiness timeout"
                    raise RuntimeError(f"Loopback fixture failed to start ({reason}); see {log_path}")
                time.sleep(0.02)
            port = int(port_file.read_text())
            if not 0 < port < 65536:
                raise ValueError("Invalid fixture port")
            yield port
        finally:
            fixture.terminate()
            try:
                fixture.wait(timeout=5)
            except subprocess.TimeoutExpired:
                fixture.kill()
                fixture.wait()


def run(output, diagnostic_host):
    output.mkdir(parents=True, exist_ok=False)
    with loopback_fixture(output) as port:
        bundle = output / "tests.xcresult"
        command = [
            "xcodebuild", "-project", "Vitrine.xcodeproj", "-scheme", "Vitrine",
            "-configuration", "Debug", "-destination", "platform=macOS",
            "-enableCodeCoverage", "NO", f"VITRINE_WEB_FIXTURE_PORT={port}",
            "-only-testing:VitrineTests/WebCaptureIntegrationTests",
            "-resultBundlePath", str(bundle),
        ]
        if diagnostic_host:
            command += ["CODE_SIGN_ENTITLEMENTS=", "ENABLE_APP_SANDBOX=NO"]
        command.append("test")
        with (output / "xcodebuild.log").open("w") as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=900)
        payload = receipts(bundle)
        report = {
            "diagnosticHost": diagnostic_host,
            "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "workingTree": subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True),
            "developerDirectory": os.environ.get("DEVELOPER_DIR"),
            "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
            "tests": payload,
        }
        (output / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"Verified {len(EXPECTED)} real controlled WebKit tests: {output}")
        if diagnostic_host:
            print("Diagnostic test host only; not production sandbox qualification.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--self-test", action="store_true")
    mode.add_argument("--verify", type=Path)
    mode.add_argument("--output", type=Path)
    parser.add_argument("--diagnostic-host", action="store_true",
                        help="Explicitly use an unsandboxed diagnostic test host, never a shipping build")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.verify:
        receipts(args.verify)
        print(f"Verified {len(EXPECTED)} real controlled WebKit tests")
    else:
        run(args.output.resolve(), args.diagnostic_host)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Controlled WebKit qualification failed: {error}", file=sys.stderr)
        sys.exit(1)
