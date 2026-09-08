#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/xcodegen-version.env"
# shellcheck disable=SC1091
source "$ROOT/scripts/sparkle-version.env"

# The digest published for an asset of a *specific* tag. Separate from the newest-version
# lookup on purpose: the supply-chain question — did the bytes under the tag we build
# against change? — is about the pinned release and must be answerable whatever upstream
# has shipped since.
pinned_release_digest() {
	local repository="$1" tag="$2" asset_template="$3"
	local headers=(-H "Accept: application/vnd.github+json")
	if [ -n "${GH_TOKEN:-}" ]; then
		headers+=(-H "Authorization: Bearer ${GH_TOKEN}")
	fi
	curl -fsSL --retry 3 "${headers[@]}" \
		"https://api.github.com/repos/${repository}/releases/tags/${tag}" \
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
print(digest)
' "$asset_template"
}

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
	local latest digest
	# Checksum first, and unconditionally. Reporting drift used to return before this
	# ran, which meant the tamper check switched itself off the moment upstream shipped
	# anything newer — and since drift is only a warning now, a pin can stay behind
	# indefinitely, so that was the whole check going quiet rather than a brief gap.
	digest="$(pinned_release_digest "$repository" "$pinned" "$asset_template")"
	if [ "$checksum" != "$digest" ]; then
		echo "error: $name $pinned checksum differs from its published release asset" >&2
		status=1
		return
	fi
	latest="$(latest_release "$repository" "$asset_template")"
	latest="${latest%%$'\n'*}"
	if [ "$pinned" != "$latest" ]; then
		note_drift "$name pin $pinned is behind the latest release $latest"
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
# Reads a package's pinned version from its own block in project.yml. Bounded to that
# block on purpose: a range that simply ran to the next `exactVersion` would jump over a
# package pinned by branch or version range and report its neighbour's version as this
# one's — reporting a dependency current when it is not.
package_pin_program='
	$0 ~ "^  " pkg ":[[:space:]]*$" { inpkg = 1; next }
	/^  [A-Za-z]/ { inpkg = 0 }
	inpkg && /exactVersion:/ {
		line = $0
		sub(/.*exactVersion: "/, "", line)
		sub(/".*/, "", line)
		print line
		exit
	}
'

check_tag() {
	local name="$1" repository="$2" latest
	local pinned
	# Bounded to this package's own block. A range that simply ran to the next
	# `exactVersion` would jump over a package pinned by branch or version range and
	# report its neighbour's version as if it were this one's.
	pinned="$(awk -v pkg="$name" "$package_pin_program" "$ROOT/project.yml")"
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
