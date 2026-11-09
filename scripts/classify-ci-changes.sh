#!/usr/bin/env bash
# Classify a pull request without Python. Unit suites still run for documentation changes.
# stdout is a GitHub Actions output; diagnostics belong on stderr.
set -euo pipefail

usage() {
    printf 'usage: classify-ci-changes.sh --event EVENT [--base REV]\n       classify-ci-changes.sh --self-test\n'
}

argument_error() {
    usage >&2
    exit 2
}

event=""
base=""
self_test=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --event|--base)
            [ "$#" -ge 2 ] && [[ "$2" != -* ]] || argument_error
            if [ "$1" = --event ]; then event="$2"; else base="$2"; fi
            shift 2
            ;;
        --event=*) event="${1#*=}"; shift ;;
        --base=*) base="${1#*=}"; shift ;;
        --self-test) self_test=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) argument_error ;;
    esac
done

if "$self_test"; then
    exec "$BASH" "$(dirname "${BASH_SOURCE[0]}")/test-ci-changes.sh"
fi
[ -n "$event" ] || argument_error

changed=""
if [ -n "$base" ]; then
    # List both sides of a rename, so moving application code into docs still runs gates.
    # Check the command's status before reading: a process substitution would hide failure.
    changed="$(git diff --name-only --no-renames "${base}...HEAD")" || exit 1
fi

count=0
documentation_only=true
while IFS= read -r path; do
    [ -n "$path" ] || continue
    count=$((count + 1))
    case "$path" in
        docs/*|site/*|.design-sync/*|.github/ISSUE_TEMPLATE/*|LICENSE) ;;
        *)
            if [[ "$path" != */* && "$path" == *.md ]]; then continue; fi
            documentation_only=false
            ;;
    esac
done <<< "$changed"

app=true
decision=required
if [ "$event" = pull_request ] && [ "$count" -gt 0 ] && "$documentation_only"; then
    app=false
    decision=skipped
fi
printf '%s changed file(s); app gates %s.\n' "$count" "$decision" >&2
printf 'app=%s\n' "$app"
