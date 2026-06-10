#!/usr/bin/env bash
# Fetch Sparkle.framework into Vendor/ for the direct-download build (CS-064).
#
# Sparkle is embedded as a LOCAL framework rather than through its Swift Package
# Manager binary artifact. That artifact's resolution hung intermittently on
# headless GitHub-hosted CI runners, stalling `xcodebuild` for 20+ minutes (the
# build that occasionally passed used a warm cache; a cold resolve hung). Downloading
# the official release tarball with curl and embedding Sparkle.framework directly is
# deterministic and verified against a pinned checksum.
#
# Idempotent: if Vendor/Sparkle.framework already exists (e.g. a cached CI directory
# or a prior local run), the fetch is skipped.
set -euo pipefail

SPARKLE_VERSION="2.9.3"
# sha256 of Sparkle-<version>.tar.xz from the official GitHub release. Bump together
# with SPARKLE_VERSION; a mismatch fails the build rather than embedding an unverified
# binary. Keep in sync with the appcast tooling pin in .github/workflows/release.yml.
SPARKLE_TARBALL_SHA256="74a07da821f92b79310009954c0e15f350173374a3abe39095b4fc5096916be6"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$REPO_ROOT/Vendor"
FRAMEWORK="$VENDOR/Sparkle.framework"

if [ -d "$FRAMEWORK" ]; then
	echo "==> Sparkle.framework already present in Vendor/ (skipping fetch)"
	exit 0
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
echo "==> Sparkle.framework $SPARKLE_VERSION staged in Vendor/"
