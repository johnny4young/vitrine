#!/usr/bin/env bash
#
# Builds a Release Vitrine.app, optionally signs + notarizes it with a Developer
# ID identity, and packages it into a DMG under dist/ (CS-012, CS-061).
#
# The pipeline degrades gracefully and is driven entirely by which environment
# variables are present:
#
#   * No signing identity            → an UNSIGNED, ad-hoc DMG for local/dev use.
#                                       This path is never production-ready.
#   * CODE_SIGN_IDENTITY set         → Developer ID Application signing with the
#                                       hardened runtime (required for a trusted
#                                       direct download).
#   * Notary credentials also set    → notarization via `notarytool` + stapling,
#                                       then a Gatekeeper assessment.
#
# Notarization accepts EITHER credential style; App Store Connect API keys take
# precedence over the Apple-ID style when both are present:
#
#   App Store Connect API key (preferred for CI; no app-specific password):
#     MACOS_NOTARY_KEY_ID         — App Store Connect API Key ID
#     MACOS_NOTARY_KEY_ISSUER_ID  — Issuer ID for that key
#     MACOS_NOTARY_KEY_P8         — path to the .p8 private-key file
#
#   Apple-ID style:
#     MACOS_NOTARY_APPLE_ID       — Apple ID for notarytool
#     MACOS_NOTARY_PASSWORD       — app-specific password
#     MACOS_NOTARY_TEAM_ID        — Developer Team ID
#
# Verification always runs against whatever was produced:
#   codesign --verify --deep --strict --verbose=2   (Developer ID builds)
#   spctl -a -vv                                     on the final artifact.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-${GITHUB_REF_NAME:-dev}}"
VERSION="${VERSION#v}"
DERIVED="build"
APP="$DERIVED/Build/Products/Release/Vitrine.app"

# Direct-download channel entitlements (CS-064). The DMG is the direct-download
# build, so it signs with the SUPERSET entitlements that add the network-client and
# Sparkle XPC mach-lookup exceptions Sparkle needs to auto-update a sandboxed app.
# The default project build and the App Store build keep the minimal
# Vitrine.entitlements (no network, no Sparkle), so the Phase 1 "no network" posture
# and the App Store exclusion of Sparkle are unchanged. The app sources still gate
# every Sparkle call behind VITRINE_DIRECT_DOWNLOAD (set on this build via project.yml).
DIRECT_DOWNLOAD_ENTITLEMENTS="Vitrine/Resources/Vitrine.DirectDownload.entitlements"

DEV_DIR="/Applications/Xcode.app/Contents/Developer"
[ -d "$DEV_DIR" ] || DEV_DIR="$(xcode-select -p)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$DEV_DIR}"

# A real Developer ID identity is anything other than the ad-hoc "-" sentinel.
# When set, we sign with the hardened runtime and run the full verification.
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGNED=0
if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "-" ]; then
	SIGNED=1
fi

echo "==> Generating project"
xcodegen generate

# Hardened runtime must stay enabled for any distributable build; the app target
# sets ENABLE_HARDENED_RUNTIME=YES in project.yml, and we pass it explicitly here
# so a Developer ID build can never accidentally ship without it (CS-061).
echo "==> Building Release ($VERSION)"
if [ "$SIGNED" -eq 1 ]; then
	echo "    Signing identity: $SIGN_IDENTITY (hardened runtime on)"
	echo "    Entitlements: $DIRECT_DOWNLOAD_ENTITLEMENTS (network + Sparkle XPC for auto-update)"
	xcodebuild \
		-project Vitrine.xcodeproj \
		-scheme Vitrine \
		-configuration Release \
		-derivedDataPath "$DERIVED" \
		CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
		CODE_SIGN_STYLE=Manual \
		VITRINE_CODE_SIGN_ENTITLEMENTS="$DIRECT_DOWNLOAD_ENTITLEMENTS" \
		ENABLE_HARDENED_RUNTIME=YES \
		${MACOS_SIGN_TEAM_ID:+DEVELOPMENT_TEAM="$MACOS_SIGN_TEAM_ID"} \
		build
else
	echo "    No Developer ID identity set — building UNSIGNED (ad-hoc). Not for distribution."
	xcodebuild \
		-project Vitrine.xcodeproj \
		-scheme Vitrine \
		-configuration Release \
		-derivedDataPath "$DERIVED" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGN_STYLE=Manual \
		VITRINE_CODE_SIGN_ENTITLEMENTS="$DIRECT_DOWNLOAD_ENTITLEMENTS" \
		build
fi

if [ ! -d "$APP" ]; then
	echo "error: $APP not found" >&2
	exit 1
fi

# --- Signature verification (Developer ID builds only) ----------------------
# Gatekeeper rejects an app whose code signature does not verify, so prove it
# here before we spend a notarization round-trip on it (CS-061 acceptance:
# `codesign --verify --deep --strict --verbose=2`).
if [ "$SIGNED" -eq 1 ]; then
	echo "==> Verifying code signature (codesign --verify --deep --strict --verbose=2)"
	codesign --verify --deep --strict --verbose=2 "$APP"
	# Surface the signing authority + hardened-runtime flag for the build log.
	codesign --display --verbose=4 "$APP" 2>&1 | grep -E 'Authority|flags|Identifier' || true
fi

# --- Notarization -----------------------------------------------------------
# notarytool needs a zip of the .app (a flat .app cannot be submitted directly).
# Build the credential argument set from whichever style is configured; the
# App Store Connect API key is preferred when present.
notary_args=()
if [ -n "${MACOS_NOTARY_KEY_ID:-}" ] \
	&& [ -n "${MACOS_NOTARY_KEY_ISSUER_ID:-}" ] \
	&& [ -n "${MACOS_NOTARY_KEY_P8:-}" ]; then
	echo "==> Notarization credentials: App Store Connect API key"
	notary_args=(
		--key "$MACOS_NOTARY_KEY_P8"
		--key-id "$MACOS_NOTARY_KEY_ID"
		--issuer "$MACOS_NOTARY_KEY_ISSUER_ID"
	)
elif [ -n "${MACOS_NOTARY_APPLE_ID:-}" ] \
	&& [ -n "${MACOS_NOTARY_PASSWORD:-}" ] \
	&& [ -n "${MACOS_NOTARY_TEAM_ID:-}" ]; then
	echo "==> Notarization credentials: Apple ID"
	notary_args=(
		--apple-id "$MACOS_NOTARY_APPLE_ID"
		--password "$MACOS_NOTARY_PASSWORD"
		--team-id "$MACOS_NOTARY_TEAM_ID"
	)
fi

NOTARIZED=0
if [ "$SIGNED" -eq 1 ] && [ "${#notary_args[@]}" -gt 0 ]; then
	echo "==> Notarizing the app (notarytool submit --wait)"
	ZIP="$DERIVED/Vitrine.zip"
	rm -f "$ZIP"
	ditto -c -k --keepParent "$APP" "$ZIP"
	xcrun notarytool submit "$ZIP" "${notary_args[@]}" --wait
	echo "==> Stapling the notarization ticket to the app"
	xcrun stapler staple "$APP"
	xcrun stapler validate "$APP"
	NOTARIZED=1
elif [ "$SIGNED" -eq 1 ]; then
	echo "==> Skipping notarization (set MACOS_NOTARY_* credentials to enable)"
else
	echo "==> Skipping notarization (unsigned build)"
fi

# --- DMG --------------------------------------------------------------------
echo "==> Creating DMG"
mkdir -p dist
DMG="dist/Vitrine-$VERSION.dmg"
rm -f "$DMG"
hdiutil create \
	-volname "Vitrine $VERSION" \
	-srcfolder "$APP" \
	-ov -format UDZO \
	"$DMG"

# Sign + (re-)staple the DMG itself so the downloaded container is trusted too.
# Stapling the DMG lets first launch validate offline once it is mounted.
if [ "$SIGNED" -eq 1 ]; then
	echo "==> Signing the DMG"
	codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
	if [ "$NOTARIZED" -eq 1 ]; then
		echo "==> Notarizing + stapling the DMG"
		# The app inside is already notarized + stapled; submit the DMG too so the
		# container itself carries a stapled ticket. Best-effort: a freshly created
		# DMG of an already-notarized app is normally accepted quickly.
		xcrun notarytool submit "$DMG" "${notary_args[@]}" --wait || \
			echo "    (DMG notarization submission skipped/failed; the app inside is already notarized + stapled)"
		xcrun stapler staple "$DMG" || \
			echo "    (DMG stapling skipped; the stapled app inside remains valid)"
	fi
fi

# --- Gatekeeper assessment --------------------------------------------------
# Run the same check macOS runs on first launch (CS-061 acceptance: `spctl -a
# -vv`). For an unsigned dev DMG this is expected to be rejected — we report it
# without failing the build, because the unsigned path is explicitly a
# development artifact, never production-ready.
echo "==> Gatekeeper assessment (spctl -a -vv)"
if [ "$SIGNED" -eq 1 ]; then
	# Assess the app bundle (execute rule) and the DMG (open/quarantine rule).
	spctl -a -vv "$APP"
	spctl -a -vv -t open --context context:primary-signature "$DMG" || \
		spctl -a -vv "$DMG" || true
else
	echo "    Unsigned build: Gatekeeper will reject this artifact. This DMG is for"
	echo "    local development only and is NOT production-ready."
	spctl -a -vv "$APP" || true
fi

echo "==> Wrote $DMG"
if [ "$SIGNED" -eq 1 ]; then
	if [ "$NOTARIZED" -eq 1 ]; then
		echo "    Signed (Developer ID) + notarized + stapled."
	else
		echo "    Signed (Developer ID). NOT notarized — not production-ready until notarized."
	fi
else
	echo "    UNSIGNED development build — NOT production-ready."
fi
shasum -a 256 "$DMG"
