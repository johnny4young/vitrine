#!/usr/bin/env bash
# Reads the app's version out of project.yml, which is the single source of truth.
#
# Every consumer — the Makefile's changelog gate, the release workflow's tag guard,
# the site deploy — used to carry its own regex, in two dialects that disagreed. The
# permissive one accepted `1.3.0-beta.1`; the strict one matched nothing at all on the
# same input, so a prerelease version would have let the release workflow proceed while
# the site build failed. This script settles it in one place, using the dialect the tag
# guard already enforces: stable SemVer, no prereleases, no leading zeros.
set -euo pipefail

FIELD="MARKETING_VERSION"
PATTERN='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
PROJECT="project.yml"

usage() {
    cat >&2 <<'USAGE'
usage: project-version.sh [--build] [--project PATH]

  (no flag)        print MARKETING_VERSION   (stable SemVer, e.g. 1.2.2)
  --build          print CURRENT_PROJECT_VERSION (a positive integer)
  --project PATH   read PATH instead of ./project.yml
  --self-test      verify the parser against known-good and known-bad inputs
USAGE
    exit 2
}

read_field() {
    # `head -n1` keeps the project-wide `settings` block authoritative when a target
    # overrides the same key further down.
    sed -nE "s/^[[:space:]]*$1:[[:space:]]*\"?([^\"[:space:]]+)\"?[[:space:]]*\$/\1/p" "$2" | head -n1
}

self_test() {
    local dir value status
    dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' RETURN

    printf '    MARKETING_VERSION: "1.2.2"\n    CURRENT_PROJECT_VERSION: "37"\n' > "$dir/ok.yml"
    [ "$("$0" --project "$dir/ok.yml")" = "1.2.2" ] || { echo "self-test: marketing read failed" >&2; return 1; }
    [ "$("$0" --build --project "$dir/ok.yml")" = "37" ] || { echo "self-test: build read failed" >&2; return 1; }

    # A prerelease is what the two old dialects disagreed about; it must fail loudly
    # here rather than being accepted by one consumer and dropped by another.
    for bad in '1.3.0-beta.1' '01.2.3' '1.2' 'x.y.z'; do
        printf '    MARKETING_VERSION: "%s"\n' "$bad" > "$dir/bad.yml"
        status=0
        value="$("$0" --project "$dir/bad.yml" 2>/dev/null)" || status=$?
        [ "$status" -ne 0 ] || { echo "self-test: '$bad' was accepted as $value" >&2; return 1; }
    done

    printf '    CURRENT_PROJECT_VERSION: "37"\n' > "$dir/missing.yml"
    status=0
    "$0" --project "$dir/missing.yml" >/dev/null 2>&1 || status=$?
    [ "$status" -ne 0 ] || { echo "self-test: a missing version was accepted" >&2; return 1; }

    echo "project-version parser self-test passed"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --build) FIELD="CURRENT_PROJECT_VERSION"; PATTERN='^[1-9][0-9]*$'; shift ;;
        --project) [ $# -ge 2 ] || usage; PROJECT="$2"; shift 2 ;;
        --self-test) self_test; exit 0 ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
done

[ -f "$PROJECT" ] || { echo "project-version: no such file: $PROJECT" >&2; exit 1; }

VALUE="$(read_field "$FIELD" "$PROJECT")"
if [ -z "$VALUE" ]; then
    echo "project-version: $PROJECT does not set $FIELD" >&2
    exit 1
fi
if ! printf '%s' "$VALUE" | grep -qE "$PATTERN"; then
    echo "project-version: $FIELD is '$VALUE', which is not the form $PATTERN" >&2
    exit 1
fi
printf '%s\n' "$VALUE"
