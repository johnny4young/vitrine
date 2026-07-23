#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/xcodegen-version.env"

binary="${1:-${XCODEGEN:-xcodegen}}"
if ! command -v "$binary" >/dev/null 2>&1; then
	echo "error: XcodeGen $XCODEGEN_VERSION is required" >&2
	echo "Install the verified release with ./scripts/install-xcodegen.sh." >&2
	exit 1
fi

actual="$("$binary" --version | sed -E 's/^Version:[[:space:]]*//')"
if [ "$actual" != "$XCODEGEN_VERSION" ]; then
	echo "error: XcodeGen $XCODEGEN_VERSION is required, found ${actual:-unknown}" >&2
	echo "Install the verified release with ./scripts/install-xcodegen.sh." >&2
	exit 1
fi

echo "XcodeGen $actual verified."
