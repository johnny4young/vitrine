#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/xcodegen-version.env"

if ! command -v xcodegen >/dev/null 2>&1; then
	echo "error: xcodegen $XCODEGEN_VERSION is required; install it with Homebrew" >&2
	exit 1
fi

actual="$(xcodegen --version | sed -E 's/^Version:[[:space:]]*//')"
if [ "$actual" != "$XCODEGEN_VERSION" ]; then
	echo "error: xcodegen $XCODEGEN_VERSION is required, found $actual" >&2
	exit 1
fi

echo "XcodeGen $actual verified."
