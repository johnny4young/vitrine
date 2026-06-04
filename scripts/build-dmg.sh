#!/usr/bin/env bash
#
# Builds a Release Vitrine.app and packages it into a DMG under dist/ (CS-012).
# Code signing and notarization run only when the relevant env vars are present,
# so this also works for unsigned local/CI builds.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-${GITHUB_REF_NAME:-dev}}"
VERSION="${VERSION#v}"
DERIVED="build"
APP="$DERIVED/Build/Products/Release/Vitrine.app"

DEV_DIR="/Applications/Xcode.app/Contents/Developer"
[ -d "$DEV_DIR" ] || DEV_DIR="$(xcode-select -p)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$DEV_DIR}"

echo "==> Generating project"
xcodegen generate

echo "==> Building Release ($VERSION)"
xcodebuild \
	-project Vitrine.xcodeproj \
	-scheme Vitrine \
	-configuration Release \
	-derivedDataPath "$DERIVED" \
	CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
	CODE_SIGN_STYLE=Manual \
	build

if [ ! -d "$APP" ]; then
	echo "error: $APP not found" >&2
	exit 1
fi

# Optional notarization (needs Apple ID credentials in the environment).
if [ -n "${MACOS_NOTARY_APPLE_ID:-}" ] \
	&& [ -n "${MACOS_NOTARY_PASSWORD:-}" ] \
	&& [ -n "${MACOS_NOTARY_TEAM_ID:-}" ]; then
	echo "==> Notarizing"
	ZIP="$DERIVED/Vitrine.zip"
	ditto -c -k --keepParent "$APP" "$ZIP"
	xcrun notarytool submit "$ZIP" \
		--apple-id "$MACOS_NOTARY_APPLE_ID" \
		--password "$MACOS_NOTARY_PASSWORD" \
		--team-id "$MACOS_NOTARY_TEAM_ID" \
		--wait
	xcrun stapler staple "$APP"
else
	echo "==> Skipping notarization (set MACOS_NOTARY_* to enable)"
fi

echo "==> Creating DMG"
mkdir -p dist
DMG="dist/Vitrine-$VERSION.dmg"
rm -f "$DMG"
hdiutil create \
	-volname "Vitrine $VERSION" \
	-srcfolder "$APP" \
	-ov -format UDZO \
	"$DMG"

echo "==> Wrote $DMG"
shasum -a 256 "$DMG"
