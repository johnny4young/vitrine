#!/usr/bin/env bash
# PostToolUse hook: when project.yml (the XcodeGen source of truth) is edited,
# regenerate Vitrine.xcodeproj so the generated project never drifts out of sync.
# Reads the Claude Code hook payload from stdin; never fails the originating call.
set -uo pipefail

payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

[ -n "$file" ] || exit 0
[ "$(basename "$file")" = "project.yml" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
command -v xcodegen >/dev/null 2>&1 || exit 0

xcodegen generate >/dev/null 2>&1 || true
exit 0
