#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/xcodegen-version.env"

prefix="${XCODEGEN_INSTALL_PREFIX:-$HOME/.local}"
if [ -z "$prefix" ] || [ "$prefix" = "/" ]; then
	echo "error: XCODEGEN_INSTALL_PREFIX must name a dedicated install prefix" >&2
	exit 1
fi
archive_url="https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/vitrine-xcodegen.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

archive="$temporary_directory/xcodegen.zip"
curl -fsSL --retry 3 "$archive_url" -o "$archive"

actual_checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [ "$actual_checksum" != "$XCODEGEN_ARCHIVE_SHA256" ]; then
	echo "error: XcodeGen $XCODEGEN_VERSION checksum mismatch" >&2
	echo "expected: $XCODEGEN_ARCHIVE_SHA256" >&2
	echo "actual:   $actual_checksum" >&2
	exit 1
fi

unzip -q "$archive" -d "$temporary_directory"
source_directory="$temporary_directory/xcodegen"
if [ ! -x "$source_directory/bin/xcodegen" ] \
	|| [ ! -d "$source_directory/share/xcodegen/SettingPresets" ]; then
	echo "error: XcodeGen $XCODEGEN_VERSION archive has an unexpected layout" >&2
	exit 1
fi

mkdir -p "$prefix/bin" "$prefix/share"
rm -rf "$prefix/share/xcodegen"
install -m 0755 "$source_directory/bin/xcodegen" "$prefix/bin/xcodegen"
cp -R "$source_directory/share/xcodegen" "$prefix/share/xcodegen"

PATH="$prefix/bin:$PATH" "$ROOT/scripts/verify-xcodegen-version.sh" "$prefix/bin/xcodegen"

if [ -n "${GITHUB_PATH:-}" ]; then
	echo "$prefix/bin" >> "$GITHUB_PATH"
fi

echo "Installed XcodeGen $XCODEGEN_VERSION in $prefix."
