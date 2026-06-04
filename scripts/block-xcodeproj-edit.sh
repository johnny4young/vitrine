#!/usr/bin/env bash
# PreToolUse hook (Edit|Write): block hand-edits to the generated Xcode project.
# Vitrine.xcodeproj is generated from project.yml by XcodeGen and is git-ignored;
# any manual edit is overwritten on the next `xcodegen generate`.
# Exit code 2 tells Claude Code to block the tool call and surface the message.
set -uo pipefail

payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

case "$file" in
  *.xcodeproj | *.xcodeproj/*)
    echo "Refusing to edit the generated Xcode project: $file" >&2
    echo "Vitrine.xcodeproj is produced by XcodeGen from project.yml and is git-ignored." >&2
    echo "Edit project.yml instead — the PostToolUse hook regenerates the project automatically." >&2
    exit 2
    ;;
esac
exit 0
