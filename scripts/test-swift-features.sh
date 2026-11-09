#!/usr/bin/env bash
# Synthetic compiler logs only; never invokes a compiler or Python.
set -euo pipefail
guard="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-swift-features.mjs"
directory="$(mktemp -d "${TMPDIR:-/tmp}/vitrine-swift-features.XXXXXX")"
trap 'rm -rf "$directory"' EXIT
cd "$directory"
modules=(Vitrine VitrineCLICore VitrineDomain VitrineMenuBarHelper VitrineRendering vitrine_cli)
all='Vitrine, VitrineCLICore, VitrineDomain, VitrineMenuBarHelper, VitrineRendering, vitrine_cli'
success="MemberImportVisibility is on for every app-owned module: $all"

write_log() {
    local module command="${1:-swiftc}" skip="${2:-}" bad="${3:-}"
    : > build.log
    for module in "${modules[@]}"; do
        [ "$module" != "$skip" ] || continue
        if [ "$module" = "$bad" ]; then
            printf '%s -module-name %s -enable-upcoming-feature InferIsolatedConformances -O\n' "$command" "$module"
        else
            printf '%s -module-name %s -enable-upcoming-feature MemberImportVisibility -O\n' "$command" "$module"
        fi
    done > build.log
}
cases=0
check() {
    local label="$1" expected_status="$2" expected_out="$3" expected_err="$4" status=0
    shift 4
    node "$guard" "$@" > stdout 2> stderr || status=$?
    [ "$status" = "$expected_status" ] || {
        printf 'FAIL: %s (exit %s, expected %s)\n' "$label" "$status" "$expected_status" >&2
        cat stderr >&2
        exit 1
    }
    : > expected
    if [ -n "$expected_out" ]; then printf '%s\n' "$expected_out" > expected; fi
    cmp -s expected stdout || { printf 'FAIL: %s (stdout)\n' "$label" >&2; exit 1; }
    if [ "$expected_err" = nonempty ]; then
        [ -s stderr ] || { printf 'FAIL: %s (missing stderr)\n' "$label" >&2; exit 1; }
    else
        : > expected
        if [ -n "$expected_err" ]; then printf '%s\n' "$expected_err" > expected; fi
        cmp -s expected stderr || { printf 'FAIL: %s (stderr)\n' "$label" >&2; cat stderr >&2; exit 1; }
    fi
    cases=$((cases + 1))
}

write_log
check 'all owned modules' 0 "$success" '' build.log

# Preserve the original mixed-log self-test: a missing flag takes precedence over absent modules.
printf '%s\n' \
    'swiftc -module-name VitrineDomain -enable-upcoming-feature MemberImportVisibility -O' \
    'swiftc -module-name Highlightr -O' \
    'swiftc -module-name Vitrine -enable-upcoming-feature InferIsolatedConformances -O' \
    'note: -module-name vitrine_cli mentioned in a note, not a compile' > mixed.log
check 'original mixed log' 1 '' 'MemberImportVisibility is off for: Vitrine' mixed.log
: > empty.log
check 'original empty log' 1 '' "the log compiles no Swift for: $all; build clean so every module is checked" empty.log

for module in "${modules[@]}"; do
    write_log swiftc "$module"
    check "absent $module" 1 '' "the log compiles no Swift for: $module; build clean so every module is checked" build.log
    write_log swiftc '' "$module"
    check "wrong feature for $module" 1 '' "MemberImportVisibility is off for: $module" build.log
done

write_log swift-frontend
check 'frontend invocations' 0 "$success" '' build.log
write_log
printf '%s\n' 'swiftc -module-name Highlightr -O' >> build.log
check 'third-party modules excluded' 0 "$success" '' build.log
write_log
printf '%s\n' 'swiftc -module-name Vitrine -O' >> build.log
check 'one bad invocation is not hidden by another good one' 1 '' 'MemberImportVisibility is off for: Vitrine' build.log

write_log
cp build.log 'build log with spaces.txt'
check 'log path with spaces' 0 "$success" '' 'build log with spaces.txt'
cp build.log ./-build.log
check 'dash-prefixed log after terminator' 0 "$success" '' -- -build.log

printf '\377 harmless invalid UTF-8\n' > invalid.log
cat build.log >> invalid.log
check 'invalid UTF-8 outside compiler arguments' 0 "$success" '' invalid.log

printf '%s\n' "swiftc -module-name Vitrine -enable-upcoming-feature MemberImportVisibility \$(touch canary)" >> build.log
check 'log text is never evaluated' 0 "$success" '' build.log
[ ! -e canary ] || { printf 'FAIL: evaluated a log\n' >&2; exit 1; }

: > unicode.log
for module in "${modules[@]}"; do
    printf 'swiftc -module-name\342\200\203%s -enable-upcoming-feature MemberImportVisibility -O\n' "$module" >> unicode.log
done
check 'Unicode whitespace after module option' 0 "$success" '' unicode.log

: > unicode.log
for module in "${modules[@]}"; do
    printf 'swiftc -module-name\302\240%s -enable-upcoming-feature MemberImportVisibility -O\n' "$module" >> unicode.log
done
check 'non-breaking space after module option' 0 "$success" '' unicode.log

: > unicode.log
for module in "${modules[@]}"; do
    printf 'swiftc -module-name\037%s -enable-upcoming-feature MemberImportVisibility -O\n' "$module" >> unicode.log
done
check 'information separator remains whitespace' 0 "$success" '' unicode.log

write_log
while IFS= read -r line; do printf '%s\342\200\250' "$line"; done < build.log > unicode-lines.log
check 'Unicode line separators' 0 "$success" '' unicode-lines.log
while IFS= read -r line; do printf '%s\r\n' "$line"; done < build.log > crlf.log
check 'CRLF lines' 0 "$success" '' crlf.log

write_log swiftc Vitrine
printf 'swiftc -module-name\357\273\277Vitrine -enable-upcoming-feature MemberImportVisibility\n' >> build.log
check 'BOM is not module whitespace' 1 '' 'the log compiles no Swift for: Vitrine; build clean so every module is checked' build.log

check 'missing log' 2 '' nonempty
check 'unknown option' 2 '' nonempty --unknown
check 'extra positional argument' 2 '' nonempty build.log extra.log
check 'unreadable path' 1 '' nonempty no-such.log
printf 'swift feature guard self-test passed (%s cases)\n' "$cases"
