#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/xcodegen-version.env"
# shellcheck disable=SC1091
source "$ROOT/scripts/sparkle-version.env"

latest_release() {
	local repository="$1" asset_template="$2"
	local headers=(-H "Accept: application/vnd.github+json")
	if [ -n "${GH_TOKEN:-}" ]; then
		headers+=(-H "Authorization: Bearer ${GH_TOKEN}")
	fi
	curl -fsSL --retry 3 "${headers[@]}" \
		"https://api.github.com/repos/${repository}/releases/latest" \
		| python3 -c '
import json
import sys

release = json.load(sys.stdin)
version = release["tag_name"].removeprefix("v")
asset_name = sys.argv[1].replace("{version}", version)
asset = next((item for item in release["assets"] if item["name"] == asset_name), None)
if asset is None:
    raise SystemExit(f"error: release asset {asset_name!r} was not found")
digest = (asset.get("digest") or "").removeprefix("sha256:")
if not digest:
    raise SystemExit(f"error: release asset {asset_name!r} has no published SHA-256 digest")
print(version)
print(digest)
' "$asset_template"
}

status=0
check_pin() {
	local name="$1" repository="$2" pinned="$3" asset_template="$4" checksum="$5"
	local release latest digest
	release="$(latest_release "$repository" "$asset_template")"
	latest="${release%%$'\n'*}"
	digest="${release#*$'\n'}"
	if [ "$pinned" != "$latest" ]; then
		echo "error: $name pin $pinned is stale; latest release is $latest" >&2
		status=1
		return
	fi
	if [ "$checksum" != "$digest" ]; then
		echo "error: $name $pinned checksum differs from the official release asset" >&2
		status=1
		return
	fi
	echo "$name $pinned and its release checksum are current."
}

check_pin XcodeGen yonaskolb/XcodeGen "$XCODEGEN_VERSION" xcodegen.zip \
	"$XCODEGEN_ARCHIVE_SHA256"
check_pin Sparkle sparkle-project/Sparkle "$SPARKLE_VERSION" 'Sparkle-{version}.tar.xz' \
	"$SPARKLE_TARBALL_SHA256"
exit "$status"
