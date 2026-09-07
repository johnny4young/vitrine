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

# A version-behind pin is information, not a defect: the pinned release is still
# authentic, and this workflow runs on a schedule with no pull request to review, so
# failing on drift produced a recurring red run that trains maintainers to ignore it.
# A checksum that no longer matches the pinned version is different in kind — the
# published bytes changed under a tag we build against — and stays fatal.
note_drift() {
	local message="$1"
	echo "$message" >&2
	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		echo "- $message" >>"$GITHUB_STEP_SUMMARY"
	fi
	echo "::warning::$message"
}

check_pin() {
	local name="$1" repository="$2" pinned="$3" asset_template="$4" checksum="$5"
	local release latest digest
	release="$(latest_release "$repository" "$asset_template")"
	latest="${release%%$'\n'*}"
	digest="${release#*$'\n'}"
	if [ "$pinned" != "$latest" ]; then
		note_drift "$name pin $pinned is behind the latest release $latest"
		return
	fi
	if [ "$checksum" != "$digest" ]; then
		echo "error: $name $pinned checksum differs from the official release asset" >&2
		status=1
		return
	fi
	echo "$name $pinned and its release checksum are current."
}

# The tags endpoint orders by creation, not by version, so a maintenance tag cut on an
# old branch reads as "latest". The releases endpoint reports the release the project
# itself marks latest, which is the comparison this check means.
latest_version() {
	local repository="$1"
	local headers=(-H "Accept: application/vnd.github+json")
	if [ -n "${GH_TOKEN:-}" ]; then
		headers+=(-H "Authorization: Bearer ${GH_TOKEN}")
	fi
	curl -fsSL --retry 3 "${headers[@]}" \
		"https://api.github.com/repos/${repository}/releases/latest" \
		| python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"].removeprefix("v"))'
}

# The two SwiftPM packages are pinned to exact versions in project.yml, and the
# generated .xcodeproj (with its Package.resolved) is git-ignored, so Dependabot cannot
# see them. Without this they could sit unchanged through a security advisory with
# nothing raising a hand. They ship source, not release assets with published digests,
# so only the version is comparable.
check_tag() {
	local name="$1" repository="$2" latest
	local pinned
	pinned="$(sed -nE "/^  ${name}:/,/exactVersion/ s/.*exactVersion: \"([^\"]+)\".*/\1/p" \
		"$ROOT/project.yml" | head -1)"
	if [ -z "$pinned" ]; then
		echo "error: no exactVersion pin found for $name in project.yml" >&2
		status=1
		return
	fi
	latest="$(latest_version "$repository")"
	if [ "$pinned" != "$latest" ]; then
		note_drift "$name pin $pinned is behind the latest release $latest"
		return
	fi
	echo "$name $pinned is current."
}

check_pin XcodeGen yonaskolb/XcodeGen "$XCODEGEN_VERSION" xcodegen.zip \
	"$XCODEGEN_ARCHIVE_SHA256"
check_pin Sparkle sparkle-project/Sparkle "$SPARKLE_VERSION" 'Sparkle-{version}.tar.xz' \
	"$SPARKLE_TARBALL_SHA256"
check_tag Highlightr raspu/Highlightr
check_tag KeyboardShortcuts sindresorhus/KeyboardShortcuts
exit "$status"
