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
# command-line tools (codesign, spctl, stapler, hdiutil, plutil, lipo, base64,
# sw_vers, uname, stat),
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
#     Info.plist sanity check (plutil), on both the DMG and the app inside it. The
#     every executable Mach-O payload must contain both arm64 and x86_64; checking
#     only the outer executable would miss a thin CLI, helper, or framework.
#     direct-download PRO signing key must be present and decode to exactly 32 bytes;
#     the script never prints or logs that private value.
#   * Classifies every result so a FAILURE distinguishes an *app bug* from a
#     *signing / notarization* failure — the two have completely different fixes
#     (code change vs. certificate / notarytool / stapling), and conflating them
#     wastes a release cycle.
#
# What stays MANUAL (a human at the clean Mac, guided by the printed checklist):
#   DMG open, drag-to-Applications, first launch past Gatekeeper, the menu-bar icon
#   appearing with NO Dock icon, quick capture, editor export, settings,
#   launch-at-login, a real PRO activation, offline relaunch, PRO-only CLI output,
#   token-file permissions, real installed-candidate WebKit journeys, a real Sparkle
#   N-to-N+1 install, and a clean uninstall. These are interactive behaviors no
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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

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
HELPER_ENTITLEMENTS_FILE=""
APP_ENTITLEMENTS_FILE=""
LICENSE_KEY_BASE64_FILE=""
LICENSE_KEY_RAW_FILE=""
# Invoked indirectly via `trap … EXIT` below, so shellcheck cannot see the call.
# shellcheck disable=SC2329
cleanup() {
	if [ -n "$HELPER_ENTITLEMENTS_FILE" ]; then
		rm -f "$HELPER_ENTITLEMENTS_FILE"
	fi
	if [ -n "$APP_ENTITLEMENTS_FILE" ]; then
		rm -f "$APP_ENTITLEMENTS_FILE"
	fi
	# These files hold the private activation signer only long enough to validate its
	# encoded shape. Never print, inspect, or retain either file.
	if [ -n "$LICENSE_KEY_BASE64_FILE" ]; then
		rm -f "$LICENSE_KEY_BASE64_FILE"
	fi
	if [ -n "$LICENSE_KEY_RAW_FILE" ]; then
		rm -f "$LICENSE_KEY_RAW_FILE"
	fi
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
SPARKLE_INSTALLER_ENABLED="$(plist_value SUEnableInstallerLauncherService)"
SPARKLE_DOWNLOADER_ENABLED="$(plist_value SUEnableDownloaderService)"

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

# Sparkle keeps Installer.xpc inside its framework, but every sandboxed host must
# explicitly enable that service and expose its matching -spks/-spki mach names.
# Vitrine already owns network.client for its direct channel, so the optional
# Downloader service must remain disabled.
if [ "$SPARKLE_INSTALLER_ENABLED" = "true" ] \
	|| [ "$SPARKLE_INSTALLER_ENABLED" = "1" ] \
	|| [ "$SPARKLE_INSTALLER_ENABLED" = "YES" ]; then
	pass "Sparkle Installer Launcher service is enabled for the sandboxed app"
else
	fail_app "SUEnableInstallerLauncherService is not enabled — Sparkle updates cannot install"
fi

if [ "$SPARKLE_DOWNLOADER_ENABLED" = "true" ] \
	|| [ "$SPARKLE_DOWNLOADER_ENABLED" = "1" ] \
	|| [ "$SPARKLE_DOWNLOADER_ENABLED" = "YES" ]; then
	fail_app "SUEnableDownloaderService must stay disabled when network.client is present"
else
	pass "Sparkle Downloader service is disabled; the app uses network.client directly"
fi

SPARKLE_INSTALLER_XPC="$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
if [ -d "$SPARKLE_INSTALLER_XPC" ]; then
	pass "Sparkle Installer.xpc is embedded inside Sparkle.framework"
else
	fail_app "Sparkle Installer.xpc is missing from the embedded framework"
fi

APP_ENTITLEMENTS_FILE="$(mktemp /tmp/vitrine-app-entitlements.XXXXXX)"
if codesign -d --entitlements :- "$APP" > "$APP_ENTITLEMENTS_FILE" 2>/dev/null; then
	APP_SANDBOX="$(/usr/libexec/PlistBuddy -c \
		'Print :com.apple.security.app-sandbox' "$APP_ENTITLEMENTS_FILE" 2>/dev/null || true)"
	NETWORK_CLIENT="$(/usr/libexec/PlistBuddy -c \
		'Print :com.apple.security.network.client' "$APP_ENTITLEMENTS_FILE" 2>/dev/null || true)"
	MACH_LOOKUPS="$(/usr/libexec/PlistBuddy -c \
		'Print :com.apple.security.temporary-exception.mach-lookup.global-name' \
		"$APP_ENTITLEMENTS_FILE" 2>/dev/null || true)"
	if [ "$APP_SANDBOX" = "true" ] \
		&& [ "$NETWORK_CLIENT" = "true" ] \
		&& [[ "$MACH_LOOKUPS" == *"$BUNDLE_ID-spks"* ]] \
		&& [[ "$MACH_LOOKUPS" == *"$BUNDLE_ID-spki"* ]]; then
		pass "Sparkle sandbox entitlements include network.client and matching -spks/-spki names"
	else
		fail_app "Sparkle sandbox entitlements are incomplete or do not match $BUNDLE_ID"
	fi
else
	fail_app "could not inspect app entitlements for the Sparkle sandbox contract"
fi

# The public direct-download app sells PRO activation, so a published artifact without
# the injected Ed25519 private key is functionally broken even when it is perfectly
# signed and notarized. Read the sensitive value straight into mode-0600 temporary files,
# decode it with stock macOS base64, and validate only the raw byte count. No command ever
# writes the value to stdout/stderr or the QA log.
LICENSE_KEY_BASE64_FILE="$(mktemp /tmp/vitrine-license-key-base64.XXXXXX)"
LICENSE_KEY_RAW_FILE="$(mktemp /tmp/vitrine-license-key-raw.XXXXXX)"
chmod 600 "$LICENSE_KEY_BASE64_FILE" "$LICENSE_KEY_RAW_FILE"
if plutil -extract VitrineLicenseSigningKey raw \
	-o "$LICENSE_KEY_BASE64_FILE" "$INFO_PLIST" 2>/dev/null \
	&& /usr/bin/base64 -D < "$LICENSE_KEY_BASE64_FILE" \
		> "$LICENSE_KEY_RAW_FILE" 2>/dev/null; then
	LICENSE_KEY_BYTES="$(wc -c < "$LICENSE_KEY_RAW_FILE" | tr -d '[:space:]')"
	if [ "$LICENSE_KEY_BYTES" = "32" ]; then
		pass "PRO activation signer is embedded and structurally valid (secret not printed)"
	else
		fail_app "VitrineLicenseSigningKey must decode to exactly 32 bytes — published PRO activation is broken"
	fi
else
	fail_app "VitrineLicenseSigningKey is missing or invalid — published PRO activation is broken"
fi

EXECUTABLE="$(plist_value CFBundleExecutable)"
if [ -n "$EXECUTABLE" ] && [ -x "$APP/Contents/MacOS/$EXECUTABLE" ]; then
	pass "Main executable present and executable: $EXECUTABLE"
else
	fail_app "main executable missing or not executable (Contents/MacOS/$EXECUTABLE)"
fi

MENU_BAR_HELPER="$APP/Contents/MacOS/VitrineMenuBarHelper"
if [ -x "$MENU_BAR_HELPER" ]; then
	pass "Menu-bar helper present and executable"
	HELPER_SIGNATURE_INFO="$(codesign -dvv "$MENU_BAR_HELPER" 2>&1 || true)"
	if printf '%s\n' "$HELPER_SIGNATURE_INFO" \
		| grep -Fqx 'Identifier=com.johnny4young.vitrine.menubar-helper'; then
		pass "Menu-bar helper has its stable sandbox identity"
	else
		fail_app "menu-bar helper is missing its stable com.johnny4young.vitrine.menubar-helper identity"
	fi
	HELPER_ENTITLEMENTS_FILE="$(mktemp /tmp/vitrine-helper-entitlements.XXXXXX)"
	if codesign -d --entitlements :- "$MENU_BAR_HELPER" \
		> "$HELPER_ENTITLEMENTS_FILE" 2>/dev/null \
		&& [ "$(/usr/libexec/PlistBuddy -c \
			'Print :com.apple.security.app-sandbox' \
			"$HELPER_ENTITLEMENTS_FILE" 2>/dev/null || true)" = "true" ] \
		&& [ "$(/usr/libexec/PlistBuddy -c \
			'Print :com.apple.security.inherit' \
			"$HELPER_ENTITLEMENTS_FILE" 2>/dev/null || true)" = "true" ]; then
		pass "Menu-bar helper inherits the app sandbox"
	else
		fail_app "menu-bar helper is missing app-sandbox + inherit entitlements"
	fi
else
	fail_app "menu-bar helper missing or not executable (Contents/MacOS/VitrineMenuBarHelper)"
fi

# A universal outer executable is insufficient when an embedded CLI, helper, framework,
# or XPC service is thin. Enumerate every executable Mach-O in the bundle so clean-Mac
# QA independently verifies the exact artifact rather than trusting the build log.
MACHO_COUNT=0
THIN_MACHO_COUNT=0
while IFS= read -r -d '' candidate; do
	if ! architectures="$(/usr/bin/lipo -archs "$candidate" 2>/dev/null)"; then
		continue
	fi

	MACHO_COUNT=$((MACHO_COUNT + 1))
	relative_path="${candidate#"$APP"/}"
	missing_architecture=""
	for required_architecture in arm64 x86_64; do
		if [[ " $architectures " != *" $required_architecture "* ]]; then
			missing_architecture="$required_architecture"
			break
		fi
	done

	if [ -n "$missing_architecture" ]; then
		THIN_MACHO_COUNT=$((THIN_MACHO_COUNT + 1))
		fail_app "$relative_path is not universal (architectures: $architectures; missing: $missing_architecture)"
	fi
done < <(find "$APP" -type f -perm -111 -print0)

if [ "$MACHO_COUNT" -eq 0 ]; then
	fail_app "no Mach-O payloads found in the app bundle"
elif [ "$THIN_MACHO_COUNT" -eq 0 ]; then
	pass "All $MACHO_COUNT Mach-O payloads contain arm64 + x86_64"
else
	note "$THIN_MACHO_COUNT of $MACHO_COUNT Mach-O payloads are not universal"
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

WEBKIT_QUALIFICATION_DIR="${VITRINE_WEBKIT_QUALIFICATION_DIR:-}"
if [ -z "$WEBKIT_QUALIFICATION_DIR" ] && [ -d "${SCRIPT_DIR}/webkit" ]; then
	WEBKIT_QUALIFICATION_DIR="${SCRIPT_DIR}/webkit"
elif [ -z "$WEBKIT_QUALIFICATION_DIR" ] && [ -d "${SCRIPT_DIR}/../qa/webkit" ]; then
	WEBKIT_QUALIFICATION_DIR="${SCRIPT_DIR}/../qa/webkit"
fi
if [ -n "$WEBKIT_QUALIFICATION_DIR" ] && [ -s "${WEBKIT_QUALIFICATION_DIR}/manifest.json" ]; then
	pass "WebKit qualification fixtures: ${WEBKIT_QUALIFICATION_DIR}"
	note "Record both platform runs in ${WEBKIT_QUALIFICATION_DIR}/qualification-log.json"
else
	warn "WebKit qualification fixtures are missing; use the candidate QA handoff ZIP before promotion"
fi

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
    [ ] 11. PRO activation    — while online, open a PRO-gated feature and paste
                                  the dedicated LIVE QA license. Activate it; the
                                  masked field must never expose the key in the log
                                  or screenshots, the sheet closes, and PRO unlocks.
    [ ] 12. Offline relaunch  — quit Vitrine, disconnect the Mac from every network,
                                  relaunch, and confirm PRO remains unlocked and a
                                  PRO-only multi-size export still completes.
    [ ] 13. PRO CLI           — still offline, run the bundled CLI's `multi-size`
                                  command and confirm it writes the requested images;
                                  this proves the out-of-process signed-token handoff.
    [ ] 14. Token permissions — without printing its contents, confirm the non-empty
                                  pro-license.token mirror has POSIX mode exactly 0600.
    [ ] 15. N to N+1 update  — install the previous published direct-download
                                  version on a disposable QA path, choose Check for
                                  Updates…, click Install Update, and confirm Vitrine
                                  relaunches on the candidate version without an
                                  installer or authorization error.
    [ ] 16. Local HTML WebKit — disconnect networking, paste local-safe.html, and
                                  require a real exported snapshot containing
                                  VITRINE_LOCAL_SAFE.
    [ ] 17. Remote blocked    — run verify-remote-probe.sh before and after pasting
                                  remote-resource-blocked.html; both controls must
                                  succeed with identical bytes, require the rendered
                                  REMOTE_REQUEST_FAILED marker, and treat REMOTE_LOADED
                                  as a release blocker.
    [ ] 18. Public URL WebKit — capture and export the real https://example.com page,
                                  not the deterministic UI-test placeholder.
    [ ] 19. Private resources — run private-subresource-probe.sh prepare, capture the
                                  public URL it copies through real WebKit, require the
                                  PRIVATE_SUBRESOURCE_PROBE_READY marker, then run verify
                                  and require zero observed loopback request bytes.
    [ ] 20. Loopback reject   — submit the 127.0.0.1 fixture and require an immediate
                                  domain rejection before WebKit navigation begins.
    [ ] 21. Private reject    — submit the private/link-local fixtures and require an
                                  immediate domain rejection before WebKit navigation.
    [ ] 22. Uninstall         — quit Vitrine, move it to the Trash (or
                                  `brew uninstall --cask vitrine`); it leaves no
                                  menu-bar icon and no login item behind.

    Evidence boundary: this manual journey does NOT validate a public-to-private
    redirect. That policy remains covered by deterministic navigation-delegate tests;
    it also does not validate DNS rebinding from a public hostname to a private address.
    Never claim either boundary as clean-Mac evidence from these fixtures.
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
