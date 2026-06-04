#!/usr/bin/env bash
# PostToolUse hook: format an edited Swift file with swift-format (Apple's
# formatter, bundled with the Xcode toolchain). It reads the Claude Code hook
# payload from stdin, formats the file in place, and never fails the originating
# tool call. Configured by .swift-format (auto-discovered).
set -uo pipefail

payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

[ -n "$file" ] || exit 0
[ "${file##*.}" = "swift" ] || exit 0
[ -f "$file" ] || exit 0

dev="/Applications/Xcode.app/Contents/Developer"
[ -d "$dev" ] || dev="$(xcode-select -p 2>/dev/null || true)"

DEVELOPER_DIR="$dev" xcrun swift-format format --in-place "$file" >/dev/null 2>&1 || true
exit 0
