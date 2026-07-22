#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/xcodegen-version.env"
# shellcheck disable=SC1091
source "$ROOT/scripts/sparkle-version.env"

latest_release() {
	local repository="$1"
	local headers=(-H "Accept: application/vnd.github+json")
	if [ -n "${GH_TOKEN:-}" ]; then
		headers+=(-H "Authorization: Bearer ${GH_TOKEN}")
	fi
	curl -fsSL --retry 3 "${headers[@]}" \
		"https://api.github.com/repos/${repository}/releases/latest" \
		| python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))'
}

status=0
check_pin() {
	local name="$1" repository="$2" pinned="$3" latest
	latest="$(latest_release "$repository")"
	if [ "$pinned" != "$latest" ]; then
		echo "error: $name pin $pinned is stale; latest release is $latest" >&2
		status=1
	else
		echo "$name $pinned is current."
	fi
}

check_pin XcodeGen yonaskolb/XcodeGen "$XCODEGEN_VERSION"
check_pin Sparkle sparkle-project/Sparkle "$SPARKLE_VERSION"
exit "$status"
