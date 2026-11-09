#!/usr/bin/env bash
# Black-box parity fixtures for the classifier; never starts Python or the app.
set -euo pipefail
classifier="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/classify-ci-changes.sh"
directory="$(mktemp -d "${TMPDIR:-/tmp}/vitrine-ci-changes.XXXXXX")"
trap 'rm -rf "$directory"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

mkdir "$directory/repo" "$directory/hooks"
cd "$directory/repo"
git init --quiet
git config user.name 'CI Classifier Tests'
git config user.email 'ci-classifier@example.invalid'
git config commit.gpgsign false
git config core.hooksPath "$directory/hooks"
git config core.quotePath true
mkdir -p docs Vitrine/Resources
printf 'initial\n' > Vitrine/App.swift
printf 'initial\n' > Vitrine/Resources/README.md
git add .
git commit --quiet -m 'Initial synthetic files'

cases=0
check() {
    local label="$1" expected_status="$2" expected_output="$3" status=0
    shift 3
    "$BASH" "$classifier" "$@" > "$directory/stdout" 2> "$directory/stderr" || status=$?
    [ "$status" = "$expected_status" ] || {
        printf 'FAIL: %s (exit %s, expected %s)\n' "$label" "$status" "$expected_status" >&2
        cat "$directory/stderr" >&2
        exit 1
    }
    : > "$directory/expected"
    if [ -n "$expected_output" ]; then printf '%s\n' "$expected_output" > "$directory/expected"; fi
    cmp -s "$directory/expected" "$directory/stdout" || {
        printf 'FAIL: %s (stdout protocol)\n' "$label" >&2
        cat "$directory/stdout" >&2
        exit 1
    }
    [ -s "$directory/stderr" ] || { printf 'FAIL: %s (missing diagnostic)\n' "$label" >&2; exit 1; }
    cases=$((cases + 1))
}

commit() {
    git add -A
    git commit --quiet -m 'Update synthetic fixture'
}
base="$(git rev-parse HEAD)"
mkdir -p .github/ISSUE_TEMPLATE .design-sync
printf 'docs\n' > docs/RELEASING.md
printf 'readme\n' > README.md
printf 'license\n' > LICENSE
printf 'template\n' > .github/ISSUE_TEMPLATE/bug.md
printf 'design\n' > .design-sync/note.md
commit
check 'docs only' 0 app=false --event pull_request --base "$base"
check 'push' 0 app=true --event push --base "$base"
check 'schedule' 0 app=true --event schedule --base "$base"

base="$(git rev-parse HEAD)"
mkdir -p site/src/i18n
printf 'site\n' > site/src/i18n/content.ts
commit
check 'site only' 0 app=false --event pull_request --base "$base"

base="$(git rev-parse HEAD)"
printf 'help\n' > docs/HELP.md
printf 'changed app\n' > Vitrine/App.swift
commit
check 'docs plus app' 0 app=true --event pull_request --base "$base"

base="$(git rev-parse HEAD)"
mkdir scripts
# The historical self-test names this path; it is inert fixture text, never executed.
printf 'fixture\n' > scripts/check-perf.py
commit
check 'scripts run in CI' 0 app=true --event pull_request --base "$base"

base="$(git rev-parse HEAD)"
mkdir -p .github/workflows
printf 'fixture\n' > .github/workflows/ci.yml
commit
check 'workflows' 0 app=true --event pull_request --base "$base"

base="$(git rev-parse HEAD)"
printf 'changed nested Markdown\n' > Vitrine/Resources/README.md
commit
check 'nested Markdown' 0 app=true --event pull_request --base "$base"
check 'empty diff' 0 app=true --event pull_request --base HEAD

base="$(git rev-parse HEAD)"
git mv Vitrine/App.swift docs/App.swift
commit
check 'rename into docs still runs app gates' 0 app=true --event pull_request --base "$base"

base="$(git rev-parse HEAD)"
rm Vitrine/Resources/README.md
commit
check 'deleted application file' 0 app=true --event pull_request --base "$base"

base="$(git rev-parse HEAD)"
printf 'spaces\n' > 'docs/with spaces.md'
printf 'spaces\n' > 'Release Notes.md'
commit
check 'spaces in document paths' 0 app=false --event pull_request --base "$base"

base="$(git rev-parse HEAD)"
printf 'Unicode\n' > 'docs/café.md'
commit
check 'Git-quoted Unicode stays conservative' 0 app=true --event pull_request --base "$base"
git config core.quotePath false
check 'unquoted Unicode follows its prefix' 0 app=false --event pull_request --base "$base"
git config core.quotePath true

base="$(git rev-parse HEAD)"
printf 'newline\n' > $'docs/line\nbreak.md'
commit
check 'Git-quoted newline stays conservative' 0 app=true --event pull_request --base "$base"

base="$(git rev-parse HEAD)"
printf 'literal\n' > "docs/\$(touch canary).md"
commit
check 'shell metacharacters are literal paths' 0 app=false --event pull_request --base "$base"
[ ! -e canary ] || { printf 'FAIL: evaluated a path\n' >&2; exit 1; }

check 'missing base runs gates' 0 app=true --event pull_request
check 'empty base runs gates' 0 app=true --event=pull_request --base=
check 'equals options' 0 app=false --event=pull_request --base="$base"
check 'invalid Git revision' 1 '' --event pull_request --base no-such-revision
check 'non-PR still reports an invalid base' 1 '' --event push --base no-such-revision
check 'missing event' 2 ''
check 'empty event' 2 '' --event=
check 'missing event value' 2 '' --event
check 'missing base value' 2 '' --event pull_request --base
check 'option is not an event value' 2 '' --event --base HEAD
check 'unknown option' 2 '' --unknown
check 'unexpected positional argument' 2 '' --event pull_request extra

printf 'CI change classification passed (%s cases).\n' "$cases"
