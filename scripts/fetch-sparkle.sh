#!/usr/bin/env bash
# Fetch Sparkle.framework into Vendor/ for the direct-download build.
#
# Sparkle is embedded as a LOCAL framework rather than through its Swift Package
# Manager binary artifact. That artifact's resolution hung intermittently on
# headless GitHub-hosted CI runners, stalling `xcodebuild` for 20+ minutes (the
# build that occasionally passed used a warm cache; a cold resolve hung). Downloading
# the official release tarball with curl and embedding Sparkle.framework directly is
# deterministic and verified against a pinned checksum.
#
# Idempotent: if Vendor/Sparkle.framework already exists at the pinned version
# (e.g. a cached CI directory or a prior local run), the fetch is skipped. The
# version actually staged is stamped in Vendor/.sparkle-version so bumping the
# pin re-fetches instead of silently keeping a stale framework.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# The pinned version + tarball checksum live in scripts/sparkle-version.env,
# shared with the appcast tooling in .github/workflows/release.yml so the
# embedded framework and the signed feed can never drift apart.
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/sparkle-version.env"

VENDOR="$REPO_ROOT/Vendor"
FRAMEWORK="$VENDOR/Sparkle.framework"
STAMP="$VENDOR/.sparkle-version"

if [ -d "$FRAMEWORK" ]; then
	if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$SPARKLE_VERSION" ]; then
		echo "==> Sparkle.framework $SPARKLE_VERSION already present in Vendor/ (skipping fetch)"
		exit 0
	fi
	echo "==> Vendor/Sparkle.framework is not the pinned $SPARKLE_VERSION (stamp: $(cat "$STAMP" 2>/dev/null || echo none)) — re-fetching"
	rm -rf "$FRAMEWORK" "$STAMP"
fi

echo "==> Fetching Sparkle $SPARKLE_VERSION framework into Vendor/"
mkdir -p "$VENDOR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
# --retry guards against transient network blips on CI (timeouts, 5xx); the pinned
# checksum below still rejects any corrupt or partial download.
curl -fsSL --retry 3 --retry-delay 2 -o "$TMP/Sparkle.tar.xz" "$URL"
echo "${SPARKLE_TARBALL_SHA256}  $TMP/Sparkle.tar.xz" | shasum -a 256 -c -

# The tarball stores Sparkle.framework at its root; extract only that.
tar -xf "$TMP/Sparkle.tar.xz" -C "$TMP" Sparkle.framework
cp -R "$TMP/Sparkle.framework" "$FRAMEWORK"
printf '%s' "$SPARKLE_VERSION" > "$STAMP"
echo "==> Sparkle.framework $SPARKLE_VERSION staged in Vendor/"
