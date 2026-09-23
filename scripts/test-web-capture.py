#!/usr/bin/env python3
"""Run controlled WebKit tests and require every expected xcresult test receipt."""

import argparse
import copy
from contextlib import contextmanager
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    "controlledRedirectProducesARealImage()",
    "crossHostSignInSessionIsAvailableToTheNextCapture()",
    "signInWindowRejectsPrivateRedirect()",
    "signInWindowBlocksPrivateSubresources()",
    "signInWindowRequiresLoopbackOptIn()",
    "privateRedirectFailsBeforeReachingTheDestination()",
    "privateResourcesAreBlockedWithAReachablePositiveControl()",
    "cancellationStopsAnActuallyPendingLoad()",
    "loopbackSubresourcesRequireExplicitOptIn()",
    "pendingLoadHonorsItsTimeout()",
    "realFullPageCaptureHonorsTheHeightCap()",
    "clearingSessionsRemovesCachedPrivateResponses()",
}
PREFIX = "WebCaptureIntegrationTests/"
DIRECT_ENTITLEMENTS = "Vitrine/Resources/Vitrine.DirectDownload.entitlements"
DIRECT_UI_CASE = "VitrineUITests/testWebSignInAffordanceRequiresExplicitSessionOptIn()"


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


def test_results(bundle):
    result = subprocess.run([
        "xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle),
        "--compact",
    ], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def receipts(bundle):
    payload = test_results(bundle)
    validate(payload)
    return payload


def validate_direct_ui(payload):
    found = []

    def visit(node):
        if node.get("nodeType") == "Test Case":
            found.append((node.get("nodeIdentifier"), node.get("result")))
        for child in node.get("children", []):
            visit(child)

    for node in payload.get("testNodes", []):
        visit(node)
    if found != [(DIRECT_UI_CASE, "Passed")]:
        raise ValueError(f"Signed Direct UI case missing, skipped, failed, or duplicated: {found}")


def verify_direct_ui(bundle):
    payload = test_results(bundle)
    validate_direct_ui(payload)
    signed_entitlements = direct_sandbox_receipt()
    report = {
        "head": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "workingTree": subprocess.check_output(
            ["git", "status", "--short"], cwd=ROOT, text=True),
        "signedEntitlements": signed_entitlements,
        "tests": payload,
    }
    (bundle.parent / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Verified signed Direct sign-in UI case: {bundle}")


def validate_direct_sandbox(settings, entitlements):
    if settings.get("CODE_SIGN_ENTITLEMENTS") != DIRECT_ENTITLEMENTS:
        raise ValueError("Controlled WebKit host did not use Direct Download entitlements")
    for key in ("com.apple.security.app-sandbox", "com.apple.security.network.client"):
        if entitlements.get(key) is not True:
            raise ValueError(f"Controlled WebKit host lacks signed entitlement: {key}")


def direct_sandbox_receipt():
    result = subprocess.run([
        "xcodebuild", "-project", "Vitrine.xcodeproj", "-scheme", "Vitrine",
        "-configuration", "Debug", "-destination", "platform=macOS",
        "-showBuildSettings", "-json",
    ], cwd=ROOT, check=True, capture_output=True, text=True)
    targets = [item for item in json.loads(result.stdout) if item["target"] == "Vitrine"]
    if len(targets) != 1:
        raise ValueError("Cannot identify the controlled WebKit app host")
    settings = targets[0]["buildSettings"]
    app = Path(settings["TARGET_BUILD_DIR"]) / settings["WRAPPER_NAME"]
    signed = subprocess.run([
        "codesign", "-d", "--entitlements", ":-", str(app),
    ], check=True, capture_output=True)
    entitlements = plistlib.loads(signed.stdout)
    validate_direct_sandbox(settings, entitlements)
    return {key: entitlements[key] for key in (
        "com.apple.security.app-sandbox", "com.apple.security.network.client")}


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
    ui_good = {"testNodes": [{"children": [
        {"nodeIdentifier": DIRECT_UI_CASE, "nodeType": "Test Case", "result": "Passed"}
    ]}]}
    validate_direct_ui(ui_good)
    ui_bad = [copy.deepcopy(ui_good), copy.deepcopy(ui_good), copy.deepcopy(ui_good)]
    ui_bad[0]["testNodes"][0]["children"].clear()
    ui_bad[1]["testNodes"][0]["children"][0]["result"] = "Skipped"
    ui_bad[2]["testNodes"][0]["children"].append(
        copy.deepcopy(ui_bad[2]["testNodes"][0]["children"][0]))
    for payload in ui_bad:
        try:
            validate_direct_ui(payload)
        except ValueError:
            continue
        raise AssertionError("Accepted a missing, skipped, or duplicate signed Direct UI case")
    settings = {"CODE_SIGN_ENTITLEMENTS": DIRECT_ENTITLEMENTS}
    grants = {"com.apple.security.app-sandbox": True,
              "com.apple.security.network.client": True}
    validate_direct_sandbox(settings, grants)
    for invalid_settings, invalid_grants in [
        ({}, grants),
        (settings, {**grants, "com.apple.security.app-sandbox": False}),
        (settings, {**grants, "com.apple.security.network.client": False}),
    ]:
        try:
            validate_direct_sandbox(invalid_settings, invalid_grants)
        except ValueError:
            continue
        raise AssertionError("Accepted an incorrectly signed WebKit host")
    print(
        f"Controlled WebKit receipt guard: {len(bad)} capture and "
        f"{len(ui_bad)} signed UI fail-closed cases passed")


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


def run(output, diagnostic_host, require_direct_sandbox):
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
        signed_entitlements = direct_sandbox_receipt() if require_direct_sandbox else None
        report = {
            "diagnosticHost": diagnostic_host,
            "signedEntitlements": signed_entitlements,
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
    mode.add_argument("--verify-direct-ui", type=Path)
    mode.add_argument("--output", type=Path)
    parser.add_argument("--diagnostic-host", action="store_true",
                        help="Explicitly use an unsandboxed diagnostic test host, never a shipping build")
    parser.add_argument("--require-direct-sandbox", action="store_true",
                        help="Fail unless the app host is signed for the Direct Download sandbox")
    args = parser.parse_args()
    if args.diagnostic_host and args.require_direct_sandbox:
        parser.error("Diagnostic and Direct Download sandbox modes are mutually exclusive")
    if args.self_test:
        self_test()
    elif args.verify:
        receipts(args.verify)
        print(f"Verified {len(EXPECTED)} real controlled WebKit tests")
    elif args.verify_direct_ui:
        verify_direct_ui(args.verify_direct_ui)
    else:
        run(args.output.resolve(), args.diagnostic_host, args.require_direct_sandbox)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Controlled WebKit qualification failed: {error}", file=sys.stderr)
        sys.exit(1)
