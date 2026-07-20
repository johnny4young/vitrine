#!/usr/bin/env bash
#
# Release artifact QA checklist.
#
# Verifies that a *published* Vitrine artifact actually works on a clean,
# compatible Mac — the machine a user installs on, not the developer box where
# the build was produced. Local debug success is not distribution success: a DMG
# that launches from DerivedData can still be rejected by Gatekeeper, ship an
# unsigned bundle, or regress a runtime feature. This script is the gate that
# catches that before a release reaches users.
#
# It is deliberately SELF-CONTAINED: it needs only the artifact and the macOS
# command-line tools (codesign, spctl, stapler, hdiutil, plutil, sw_vers, uname),
# all present on a stock Mac. It does NOT read project.yml, the .xcodeproj, or any
# DerivedData, so you can copy this one file (or download it from the release) onto
# a freshly imaged Mac that has never seen the repository and run the same checks a
# user's machine will run.
#
# Usage:
#   scripts/qa-release.sh path/to/Vitrine-<version>.dmg     # a published DMG
#   scripts/qa-release.sh path/to/Vitrine.app              # an extracted .app
#   scripts/qa-release.sh                                  # auto-detect dist/*.dmg
#
# What it does automatically (the scriptable half — see the documented test procedure):
#   * Records the QA environment: macOS version, hardware architecture, the
#     artifact's app version (CFBundleShortVersionString + CFBundleVersion), bundle
#     identifier, and the signing identity (codesign authority). Every manual run
#     starts from a written record of WHERE it ran and WHAT it tested.
#   * Runs the signing / notarization assessment a user's Gatekeeper runs on first
#     launch: codesign --verify --deep --strict, spctl -a, stapler validate, and an
#     Info.plist sanity check (plutil), on both the DMG and the app inside it.
#   * Classifies every result so a FAILURE distinguishes an *app bug* from a
#     *signing / notarization* failure — the two have completely different fixes
#     (code change vs. certificate / notarytool / stapling), and conflating them
#     wastes a release cycle.
#
# What stays MANUAL (a human at the clean Mac, guided by the printed checklist):
#   DMG open, drag-to-Applications, first launch past Gatekeeper, the menu-bar icon
#   appearing with NO Dock icon, quick capture, editor export, settings,
#   launch-at-login, and a clean uninstall. These are interactive behaviors no
#   headless check can prove; the script prints them as a numbered log to walk
#   through and record per release (see docs/RELEASING.md).
#
# Exit status:
#   0  every automated check passed (the manual checklist still has to be walked).
#   2  a SIGNING / NOTARIZATION check failed (not an app bug) — fix the certificate,
#      notarization, or stapling, not the code.
#   3  an APP / artifact problem (missing or malformed bundle, bad Info.plist) —
#      an app/packaging bug, not a signing failure.
#   1  the artifact could not be found or mounted (usage / environment error).
#
set -euo pipefail

# --- Result accounting ------------------------------------------------------
# Track app-level vs. signing-level failures separately so the final summary —
# and the exit code — can tell an app bug apart from a signing/notarization one.
APP_FAILURES=0
SIGNING_FAILURES=0
WARNINGS=0

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
section() { printf '\n'; bold "==> $1"; }

# A passing automated check.
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }

# An APP / artifact failure: a code or packaging bug, fixed by changing the app,
# not the signing pipeline.
fail_app() {
	printf '  \033[31m✗ [APP]\033[0m %s\n' "$1"
	APP_FAILURES=$((APP_FAILURES + 1))
}

# A SIGNING / NOTARIZATION failure: the bundle is structurally fine but is not
# trusted by Gatekeeper. Fixed by the certificate / notarytool / stapling, never
# by editing code.
fail_signing() {
	printf '  \033[31m✗ [SIGNING]\033[0m %s\n' "$1"
	SIGNING_FAILURES=$((SIGNING_FAILURES + 1))
}

# A non-fatal observation (e.g. an unsigned local dev DMG, which is expected to be
# rejected and is never production-ready).
warn() {
	printf '  \033[33m! %s\033[0m\n' "$1"
	WARNINGS=$((WARNINGS + 1))
}

note() { printf '    %s\n' "$1"; }

# --- Locate the artifact ----------------------------------------------------
# Accept a DMG or an .app; with no argument, auto-detect the newest dist/*.dmg so
# a local run after build-dmg.sh "just works". The script never depends on the
# repo layout beyond this convenience default.
ARTIFACT="${1:-}"
if [ -z "$ARTIFACT" ]; then
	# Pick the most recently modified dist/*.dmg by mtime (stat -f %m on macOS),
	# without parsing `ls`. Empty (no DMG present) falls through to the usage error.
	newest_mtime=0
	for candidate in dist/*.dmg; do
		[ -e "$candidate" ] || continue
		mtime="$(stat -f %m "$candidate" 2>/dev/null || echo 0)"
		if [ "$mtime" -ge "$newest_mtime" ]; then
			newest_mtime="$mtime"
			ARTIFACT="$candidate"
		fi
	done
	if [ -z "$ARTIFACT" ]; then
		echo "error: no artifact given and no dist/*.dmg found." >&2
		echo "usage: $0 <Vitrine-VERSION.dmg | Vitrine.app>" >&2
		exit 1
	fi
	echo "No artifact argument; using newest DMG: $ARTIFACT"
fi

if [ ! -e "$ARTIFACT" ]; then
	echo "error: artifact not found: $ARTIFACT" >&2
	exit 1
fi

# Mount a DMG read-only and locate the .app inside it; an .app argument is used
# directly. MOUNT_POINT is cleaned up on exit.
MOUNT_POINT=""
DMG=""
# Invoked indirectly via `trap … EXIT` below, so shellcheck cannot see the call.
# shellcheck disable=SC2329
cleanup() {
	if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
		hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
		rmdir "$MOUNT_POINT" 2>/dev/null || true
	fi
}
trap cleanup EXIT

case "$ARTIFACT" in
*.dmg)
	DMG="$ARTIFACT"
	section "Mounting DMG"
	MOUNT_POINT="$(mktemp -d /tmp/vitrine-qa.XXXXXX)"
	# -nobrowse so it does not pop a Finder window; -readonly so QA cannot mutate
	# the published artifact; -noverify so a deliberately unsigned dev DMG still
	# mounts for inspection.
	if hdiutil attach "$DMG" -readonly -nobrowse -noverify -mountpoint "$MOUNT_POINT" -quiet; then
		pass "DMG mounted at $MOUNT_POINT"
	else
		fail_app "DMG failed to mount (hdiutil attach) — the container is corrupt"
		exit 3
	fi
	APP="$(find "$MOUNT_POINT" -maxdepth 1 -name '*.app' -print -quit)"
	if [ -z "$APP" ]; then
		fail_app "no .app found inside the DMG"
		exit 3
	fi
	;;
*.app)
	APP="$ARTIFACT"
	;;
*)
	echo "error: artifact must be a .dmg or .app: $ARTIFACT" >&2
	exit 1
	;;
esac

if [ ! -d "$APP" ]; then
	fail_app "app bundle is not a directory: $APP"
	exit 3
fi

# --- QA environment record --------------------------------------------------
# Every manual QA run must record WHERE it ran and WHAT it tested, so a pass/fail
# is tied to a known machine and artifact: macOS version, architecture, app
# version, and signing identity.
INFO_PLIST="$APP/Contents/Info.plist"
plist_value() {
	# Read one Info.plist key without depending on the repo; plutil ships on every
	# Mac. Prints empty on a missing key.
	plutil -extract "$1" raw -o - "$INFO_PLIST" 2>/dev/null || true
}

APP_VERSION="$(plist_value CFBundleShortVersionString)"
BUILD_VERSION="$(plist_value CFBundleVersion)"
BUNDLE_ID="$(plist_value CFBundleIdentifier)"
LSUIELEMENT="$(plist_value LSUIElement)"

# Signing identity: the Developer ID "Authority" line from the app's signature, or
# a clear marker when the bundle is unsigned / ad-hoc. Capture the output once so
# strict pipefail mode cannot misclassify a valid signature when a short-circuiting
# parser closes its pipe before codesign finishes writing.
CODESIGN_DETAILS="$(codesign --display --verbose=2 "$APP" 2>&1 || true)"
SIGN_IDENTITY="$(awk -F'Authority=' '/^Authority=/ { print $2; exit }' <<<"$CODESIGN_DETAILS")"
if [ -z "$SIGN_IDENTITY" ]; then
	SIGN_IDENTITY="(none — unsigned or ad-hoc)"
fi

section "QA environment"
note "macOS version : $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
note "Architecture  : $(uname -m)"
note "Artifact      : $ARTIFACT"
note "App bundle    : $APP"
note "App version   : ${APP_VERSION:-(unknown)} (build ${BUILD_VERSION:-?})"
note "Bundle id     : ${BUNDLE_ID:-(unknown)}"
note "Signing id    : $SIGN_IDENTITY"
note "Tested at     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# --- Automated artifact / Info.plist checks (app bugs) ----------------------
# These prove the *bundle itself* is well-formed. A failure here is an app /
# packaging bug, not a signing problem.
section "Artifact structure (app/packaging checks)"

if plutil -lint "$INFO_PLIST" >/dev/null 2>&1; then
	pass "Info.plist is valid (plutil -lint)"
else
	fail_app "Info.plist failed plutil -lint — malformed property list"
fi

if [ -n "$APP_VERSION" ]; then
	pass "App version present: $APP_VERSION (build ${BUILD_VERSION:-?})"
else
	fail_app "CFBundleShortVersionString missing from Info.plist"
fi

# The menu-bar agent must declare LSUIElement so it has NO Dock icon. A
# missing/false value is an app bug the manual "no Dock icon" check would also catch.
if [ "$LSUIELEMENT" = "true" ] || [ "$LSUIELEMENT" = "1" ] || [ "$LSUIELEMENT" = "YES" ]; then
	pass "LSUIElement is set (menu-bar agent, no Dock icon)"
else
	fail_app "LSUIElement is not set — the app would show a Dock icon"
fi

EXECUTABLE="$(plist_value CFBundleExecutable)"
if [ -n "$EXECUTABLE" ] && [ -x "$APP/Contents/MacOS/$EXECUTABLE" ]; then
	pass "Main executable present and executable: $EXECUTABLE"
else
	fail_app "main executable missing or not executable (Contents/MacOS/$EXECUTABLE)"
fi

# --- Automated signing / notarization checks (signing failures) -------------
# These are exactly what Gatekeeper evaluates on a user's Mac at first launch.
# A failure here is a SIGNING / NOTARIZATION problem — fixed by the certificate,
# notarytool, or stapling, never by editing code.
section "Signing & notarization (Gatekeeper checks)"

# Is the app signed with a real Developer ID at all? An unsigned / ad-hoc bundle
# is a development artifact and is never production-ready. Artifact QA treats that
# as a signing failure so a release workflow cannot publish it as a successful run.
SIGNED=0
if [[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]]; then
	SIGNED=1
fi

if [ "$SIGNED" -eq 1 ]; then
	# codesign --verify --deep --strict: the structural signature check Gatekeeper
	# relies on. A failure means the signature is broken/invalid.
	if codesign --verify --deep --strict --verbose=2 "$APP" 2>/dev/null; then
		pass "Code signature verifies (codesign --verify --deep --strict)"
	else
		fail_signing "codesign --verify --deep --strict failed — broken Developer ID signature"
	fi

	# Hardened runtime must be on for a notarizable build.
	if [[ "$CODESIGN_DETAILS" == *"flags="*"runtime"* ]]; then
		pass "Hardened runtime is enabled"
	else
		fail_signing "hardened runtime is OFF — notarization requires it"
	fi

	# spctl -a: the Gatekeeper execution assessment. "accepted" + "Notarized
	# Developer ID" is the production state.
	SPCTL_APP="$(spctl -a -vv "$APP" 2>&1 || true)"
	if [[ "$SPCTL_APP" == *"accepted"* ]]; then
		pass "Gatekeeper accepts the app (spctl -a -vv)"
		printf '%s' "$SPCTL_APP" | grep -E 'source|origin' | sed 's/^/      /' || true
	else
		fail_signing "Gatekeeper REJECTS the app (spctl -a) — not notarized / not trusted"
		note "$SPCTL_APP"
	fi

	# stapler validate: a stapled ticket lets first launch validate OFFLINE. Missing
	# stapling still passes online but fails on a machine with no network on first run.
	if xcrun stapler validate "$APP" >/dev/null 2>&1; then
		pass "Notarization ticket is stapled to the app (offline first launch works)"
	else
		fail_signing "no stapled notarization ticket on the app (stapler validate failed)"
	fi

	# Assess the DMG container too, since that is what the user actually downloads.
	if [ -n "$DMG" ]; then
		SPCTL_DMG="$(spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 || true)"
		if [[ "$SPCTL_DMG" != *"accepted"* ]]; then
			SPCTL_DMG="$(spctl -a -vv "$DMG" 2>&1 || true)"
		fi
		if [[ "$SPCTL_DMG" == *"accepted"* ]]; then
			pass "Gatekeeper accepts the DMG (spctl -a)"
		else
			fail_signing "Gatekeeper REJECTS the DMG — sign + notarize the container too"
		fi
		if xcrun stapler validate "$DMG" >/dev/null 2>&1; then
			pass "Notarization ticket is stapled to the DMG"
		else
			warn "DMG is not stapled (the app inside may still be stapled; verify offline first launch)"
		fi
	fi
else
	fail_signing "App is UNSIGNED or ad-hoc — Gatekeeper will reject it on a clean Mac."
	note "This is a development artifact and is NOT production-ready. A signed,"
	note "notarized build is required before release. Skipping signature/Gatekeeper"
	note "PASS checks; this is a known state, not an app bug."
fi

# --- Manual checklist -------------------------------------------------------
# The interactive behaviors no headless check can prove. Walk these on the clean
# Mac and record the result per release (docs/RELEASING.md keeps the log template).
section "Manual checklist — run these by hand on this clean Mac"
cat <<'CHECKLIST'
    Work top to bottom; record pass/fail for each in the release QA log.

    [ ]  1. DMG opens         — double-click the .dmg; the volume window appears.
    [ ]  2. Drag to /Applications — drag Vitrine.app onto the Applications alias.
    [ ]  3. First launch      — open Vitrine from /Applications; it launches past
                                  Gatekeeper WITHOUT the "unidentified developer"
                                  block (a signed + notarized build is required).
    [ ]  4. Gatekeeper        — no "cannot be opened because the developer cannot
                                  be verified" dialog on that first launch.
    [ ]  5. Menu-bar icon     — the Vitrine icon appears in the menu bar.
    [ ]  6. No Dock icon      — Vitrine shows NO Dock icon and no app-switcher
                                  (Cmd-Tab) entry (LSUIElement agent).
    [ ]  7. Quick capture     — trigger Quick Capture; it renders the clipboard /
                                  selection to an image.
    [ ]  8. Editor export     — open the editor, paste code, and export a PNG;
                                  the saved file opens and looks correct.
    [ ]  9. Settings          — open Settings; panes load and a changed setting
                                  persists across an app relaunch.
    [ ] 10. Launch at login   — toggle "Launch at login" on; log out and back in
                                  (or reboot) and confirm Vitrine starts. Toggle it
                                  off and confirm it no longer auto-starts.
    [ ] 11. Uninstall         — quit Vitrine, move it to the Trash (or
                                  `brew uninstall --cask vitrine`); it leaves no
                                  menu-bar icon and no login item behind.
CHECKLIST

# --- Summary + exit ---------------------------------------------------------
# The exit code lets CI or a wrapper distinguish the failure CLASS without parsing
# text: signing failures and app bugs have different owners and different fixes.
section "Summary"
note "Automated app/packaging failures : $APP_FAILURES"
note "Automated signing/notarization    : $SIGNING_FAILURES"
note "Warnings                          : $WARNINGS"

if [ "$APP_FAILURES" -gt 0 ]; then
	bold "RESULT: APP/ARTIFACT failures — this is an app or packaging bug, not signing."
	exit 3
elif [ "$SIGNING_FAILURES" -gt 0 ]; then
	bold "RESULT: SIGNING/NOTARIZATION failures — fix the certificate, notarization,"
	bold "        or stapling. This is NOT an app bug."
	exit 2
else
	bold "RESULT: all automated checks passed. Now complete the manual checklist above"
	bold "        on this clean Mac and record each result in the release QA log."
	exit 0
fi
