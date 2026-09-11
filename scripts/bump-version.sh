#!/usr/bin/env bash
# Rewrites the mechanical half of the release version lockstep.
#
# A release moves the version through eleven places. Six files carry mechanical
# substitutions that used to be retyped by hand, and the release workflow refuses to tag
# if any one of them disagrees. The other half is prose — a changelog section, the in-app
# What's New — that has to be written, so this prints those instead of guessing.
#
# The contract, and how each part is kept:
#
#   * Every site must match exactly once. That is counted, never inferred from
#     whether the file changed: a duplicated key changes the file too, and a same-version
#     resubmission legitimately changes nothing on its version-only sites.
#   * Nothing is written until every site has been checked. Rewrites are staged in a
#     temporary tree and copied into place only after all of them validate, so a failing
#     site leaves the checkout exactly as it was — including the build number, which is
#     what lets the same command succeed once the problem is fixed.
#   * Anchors sit on surrounding syntax, never on the old version string, so prose that
#     records an older release is untouched.
#
# Literal metacharacters are bracket expressions (`[|]`, `[*]`, `[(]`) so each pattern
# means the same thing to BSD tools on a Mac and GNU tools in CI.
set -euo pipefail

usage() {
    cat >&2 <<'USAGE'
usage: bump-version.sh VERSION BUILD
       bump-version.sh --self-test

  VERSION   stable SemVer, e.g. 1.2.3 (the dialect the release tag guard enforces).
            May equal the current version: an App Store resubmission keeps the
            marketing version and moves only the build (docs/APP-STORE.md).
  BUILD     positive integer, strictly greater than the current build
USAGE
    exit 2
}

# Four fields per site: file, description, match (POSIX ERE), replacement template.
# In the template, @V@ is the version and @B@ the build.
SITES=(
    'project.yml' 'MARKETING_VERSION'
    '^([[:space:]]*MARKETING_VERSION:[[:space:]]*")[^"]*(")' '\1@V@\2'
    'project.yml' 'CURRENT_PROJECT_VERSION'
    '^([[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*")[^"]*(")' '\1@B@\2'
    'Vitrine/CLI/CLIVersion.swift' 'CLI fallback version'
    '^([[:space:]]*static let fallbackMarketingVersion = ")[^"]*(")' '\1@V@\2'
    'Vitrine/CLI/CLIVersion.swift' 'CLI fallback build'
    '^([[:space:]]*static let fallbackBuildNumber = ")[^"]*(")' '\1@B@\2'
    'packaging/Casks/vitrine.rb' 'Homebrew cask version'
    '^([[:space:]]*version ")[^"]*(")' '\1@V@\2'
    'site/src/components/Commercial.astro' 'site release version'
    "^(const releaseVersion = ')[^']*(';)" '\1@V@\2'
    'docs/APP-STORE.md' 'App Store marketing version'
    '^([|] Marketing version [|] `)[^`]*(`)' '\1@V@\2'
    'docs/APP-STORE.md' 'App Store build number'
    '^([|] Build number [|] `)[^`]*(`)' '\1@B@\2'
    'README.md' 'status badge'
    '(status-v)[0-9][^-]*(--candidate-orange)' '\1@V@\2'
    'README.md' 'status sentence'
    '([*][*]v)[0-9][0-9.]*( [(]build )[0-9]+([)] is the current release candidate)' '\1@V@\2@B@\3'
    'README.md' 'release-line sentence'
    '(not part of the v)[0-9][0-9.]*( release line)' '\1@V@\2'
)

target_files() {
    local i
    for ((i = 0; i < ${#SITES[@]}; i += 4)); do
        printf '%s\n' "${SITES[i]}"
    done | awk '!seen[$0]++'
}

# Count occurrences, including repeated README phrases on the same line.
count_matches() {
    local matches status=0
    matches="$(grep -oE -- "$2" "$1")" || status=$?
    case "$status" in
        0) printf '%s\n' "$matches" | awk 'END { print NR }' ;;
        1) echo 0 ;;
        *) return "$status" ;;
    esac
}

run_bump() (
    local root="$1" v="$2" b="$3"
    local i file description match template replacement path count stage
    local current_version current_build failures=0

    [[ "$v" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
        echo "bump-version: '$v' is not a stable SemVer version the release tag guard would accept" >&2
        return 1
    }
    [[ "$b" =~ ^[1-9][0-9]*$ ]] || {
        echo "bump-version: build '$b' must be a positive integer" >&2
        return 1
    }

    current_version="$("$root/scripts/project-version.sh" --project "$root/project.yml")" || return 1
    current_build="$("$root/scripts/project-version.sh" --build --project "$root/project.yml")" || return 1
    # Positive decimal strings compare by length, then lexically. Shell integer
    # comparisons overflow for long builds and their error must not admit a downgrade.
    local LC_ALL=C
    if [ "${#b}" -lt "${#current_build}" ] ||
        { [ "${#b}" -eq "${#current_build}" ] && [[ ! "$b" > "$current_build" ]]; }; then
        echo "bump-version: build $b must be greater than the current $current_build — Sparkle and App Store Connect both order builds by it" >&2
        return 1
    fi

    # Preflight: every site is writable and matches exactly once, before anything is written.
    for ((i = 0; i < ${#SITES[@]}; i += 4)); do
        file="${SITES[i]}"
        description="${SITES[i + 1]}"
        match="${SITES[i + 2]}"
        path="$root/$file"
        if [ ! -f "$path" ]; then
            echo "bump-version: missing $file" >&2
            failures=1
            continue
        fi
        if [ ! -w "$path" ]; then
            echo "bump-version: $file is not writable; nothing was written" >&2
            return 1
        fi
        count="$(count_matches "$path" "$match")" || return 1
        if [ "$count" != "1" ]; then
            echo "bump-version: $file — '$description' matched $count occurrences, expected exactly 1" >&2
            failures=1
        fi
    done
    if [ "$failures" -ne 0 ]; then
        echo "bump-version: nothing was written" >&2
        return 1
    fi

    # Stage every rewrite; publish only once all of them validate.
    # Publication is sequential, not crash-atomic: an interruption or new I/O failure
    # during the final copies can still require recovering the checkout manually.
    stage="$(mktemp -d)" || return 1
    # A subshell owns the trap so staging failures clean up even under the self-test's
    # conditional calls, where Bash deliberately disables implicit errexit handling.
    trap 'rm -rf "$stage"' EXIT
    while IFS= read -r file; do
        mkdir -p "$stage/$(dirname "$file")" || return 1
        cp "$root/$file" "$stage/$file" || return 1
    done < <(target_files)

    for ((i = 0; i < ${#SITES[@]}; i += 4)); do
        file="${SITES[i]}"
        match="${SITES[i + 2]}"
        template="${SITES[i + 3]}"
        replacement="${template//@V@/$v}"
        replacement="${replacement//@B@/$b}"
        sed -E "s/$match/$replacement/" "$stage/$file" > "$stage/$file.next" || return 1
        mv "$stage/$file.next" "$stage/$file" || return 1
        if [ "$(count_matches "$stage/$file" "$match")" != "1" ]; then
            echo "bump-version: $file — rewriting '${SITES[i + 1]}' did not leave exactly one match; nothing was written" >&2
            rm -rf "$stage"
            return 1
        fi
    done

    while IFS= read -r file; do
        cp "$stage/$file" "$root/$file" || {
            echo "bump-version: could not publish $file; inspect the checkout for partial writes" >&2
            return 1
        }
    done < <(target_files)
    rm -rf "$stage"

    if [ "$v" = "$current_version" ]; then
        echo "Resubmission of $v: marketing version unchanged, build $current_build → $b"
    else
        echo "Bumped $current_version (build $current_build) → $v (build $b)"
    fi
    for ((i = 0; i < ${#SITES[@]}; i += 4)); do
        echo "  ${SITES[i]} — ${SITES[i + 1]}"
    done
)

# Set by self_test and read by its EXIT trap, so it must not be local: the trap fires when
# the script exits, after self_test has returned and its locals are gone. Under `set -u` a
# local here made a fully passing self-test print its success line and then exit 1.
SELF_TEST_ROOT=""

self_test() {
    local here dir before cv cb args
    here="$(cd "$(dirname "$0")/.." && pwd)"
    SELF_TEST_ROOT="$(mktemp -d)"
    trap 'rm -rf "$SELF_TEST_ROOT"' EXIT

    fixture() {
        local fixture_dir="$SELF_TEST_ROOT/$1" fixture_file
        mkdir -p "$fixture_dir/scripts"
        cp "$here/scripts/project-version.sh" "$fixture_dir/scripts/"
        while IFS= read -r fixture_file; do
            mkdir -p "$fixture_dir/$(dirname "$fixture_file")"
            cp "$here/$fixture_file" "$fixture_dir/$fixture_file"
        done < <(target_files)
        printf '%s' "$fixture_dir"
    }
    # Byte-level fingerprint of every target file, so "wrote nothing" is measured.
    fingerprint() {
        local fingerprint_file
        while IFS= read -r fingerprint_file; do
            cat "$1/$fingerprint_file"
        done < <(target_files) | cksum
    }
    fail() {
        echo "bump-version self-test: $1" >&2
        exit 1
    }

    cv="$("$here/scripts/project-version.sh" --project "$here/project.yml")"
    cb="$("$here/scripts/project-version.sh" --build --project "$here/project.yml")"

    # A normal bump rewrites all eleven sites, against the shapes actually shipped.
    dir="$(fixture normal)"
    run_bump "$dir" 9.9.9 999 >/dev/null || fail "a valid bump was refused"
    grep -q 'MARKETING_VERSION: "9.9.9"' "$dir/project.yml" || fail "project version"
    grep -q 'CURRENT_PROJECT_VERSION: "999"' "$dir/project.yml" || fail "project build"
    grep -q 'fallbackMarketingVersion = "9.9.9"' "$dir/Vitrine/CLI/CLIVersion.swift" || fail "cli version"
    grep -q 'fallbackBuildNumber = "999"' "$dir/Vitrine/CLI/CLIVersion.swift" || fail "cli build"
    grep -q 'version "9.9.9"' "$dir/packaging/Casks/vitrine.rb" || fail "cask"
    grep -q "releaseVersion = '9.9.9'" "$dir/site/src/components/Commercial.astro" || fail "site"
    grep -q '| Marketing version | `9.9.9`' "$dir/docs/APP-STORE.md" || fail "app store version"
    grep -q '| Build number | `999`' "$dir/docs/APP-STORE.md" || fail "app store build"
    grep -q 'status-v9.9.9--candidate' "$dir/README.md" || fail "badge"
    grep -q '\*\*v9.9.9 (build 999) is the current release candidate' "$dir/README.md" || fail "status sentence"
    grep -q 'not part of the v9.9.9 release line' "$dir/README.md" || fail "release-line sentence"

    # A resubmission keeps the marketing version and moves only the build.
    dir="$(fixture resubmission)"
    run_bump "$dir" "$cv" "$((cb + 1))" >/dev/null || fail "a same-version resubmission was refused"
    [ "$("$dir/scripts/project-version.sh" --project "$dir/project.yml")" = "$cv" ] ||
        fail "a resubmission changed the marketing version"
    [ "$("$dir/scripts/project-version.sh" --build --project "$dir/project.yml")" = "$((cb + 1))" ] ||
        fail "a resubmission did not move the build"
    grep -q "version \"$cv\"" "$dir/packaging/Casks/vitrine.rb" || fail "a resubmission changed the cask"

    # A duplicated anchor is refused, and nothing is written.
    dir="$(fixture duplicate)"
    printf '  version "%s"\n' "$cv" >> "$dir/packaging/Casks/vitrine.rb"
    before="$(fingerprint "$dir")"
    if run_bump "$dir" 9.9.9 999 >/dev/null 2>&1; then fail "a duplicated anchor was accepted"; fi
    [ "$(fingerprint "$dir")" = "$before" ] || fail "a duplicated anchor still wrote files"

    # Two unanchored occurrences on one line must not leave the second version stale.
    dir="$(fixture duplicate_inline)"
    sed 's/ release line/ release line; not part of the v0.0.0 release line/' \
        "$dir/README.md" > "$dir/README.md.next"
    mv "$dir/README.md.next" "$dir/README.md"
    before="$(fingerprint "$dir")"
    if run_bump "$dir" 9.9.9 999 >/dev/null 2>&1; then fail "a same-line duplicate was accepted"; fi
    [ "$(fingerprint "$dir")" = "$before" ] || fail "a same-line duplicate still wrote files"

    # A predictable publication failure is rejected before the build number moves.
    dir="$(fixture readonly)"
    chmod a-w "$dir/README.md"
    if [ ! -w "$dir/README.md" ]; then
        before="$(fingerprint "$dir")"
        if run_bump "$dir" 9.9.9 999 >/dev/null 2>&1; then fail "a read-only target was accepted"; fi
        [ "$(fingerprint "$dir")" = "$before" ] || fail "a read-only target left partial writes"
    fi
    chmod u+w "$dir/README.md"
    run_bump "$dir" 9.9.9 999 >/dev/null || fail "a bump failed after restoring write permission"

    # Staging I/O failures must return failure even when called from a conditional.
    dir="$(fixture staging_failure)"
    before="$(fingerprint "$dir")"
    if (
        cp() { return 1; }
        run_bump "$dir" 9.9.9 999
    ) >/dev/null 2>&1; then fail "a failed staging copy was accepted"; fi
    [ "$(fingerprint "$dir")" = "$before" ] || fail "a failed staging copy wrote files"

    # Decimal ordering remains exact beyond the machine integer range, including equality.
    dir="$(fixture large_build)"
    run_bump "$dir" "$cv" 9223372036854775809 >/dev/null || fail "a large build was refused"
    before="$(fingerprint "$dir")"
    for args in 9223372036854775808 9223372036854775809 999; do
        if run_bump "$dir" "$cv" "$args" >/dev/null 2>&1; then fail "a large build did not move forward"; fi
    done
    [ "$(fingerprint "$dir")" = "$before" ] || fail "a refused large build wrote files"
    run_bump "$dir" "$cv" 9223372036854775810 >/dev/null || fail "a larger build was refused"

    # A site that fails late writes nothing, so the same command works once it is fixed.
    dir="$(fixture recovery)"
    sed 's/--candidate-orange/--stable-green/' "$dir/README.md" > "$dir/README.md.next"
    mv "$dir/README.md.next" "$dir/README.md"
    before="$(fingerprint "$dir")"
    if run_bump "$dir" 9.9.9 999 >/dev/null 2>&1; then fail "a moved anchor was accepted"; fi
    [ "$(fingerprint "$dir")" = "$before" ] || fail "a failed bump left files half-rewritten"
    sed 's/--stable-green/--candidate-orange/' "$dir/README.md" > "$dir/README.md.next"
    mv "$dir/README.md.next" "$dir/README.md"
    run_bump "$dir" 9.9.9 999 >/dev/null || fail "the same bump failed after its anchor was restored"

    # Refused inputs write nothing: a prerelease, a build that does not move, a zero build.
    dir="$(fixture refusals)"
    before="$(fingerprint "$dir")"
    for args in "1.3.0-beta.1 $((cb + 1))" "9.9.9 $cb" "9.9.9 0"; do
        # shellcheck disable=SC2086
        if run_bump "$dir" $args >/dev/null 2>&1; then fail "run_bump $args was accepted"; fi
    done
    if run_bump "$dir" $'9.9.9\ninvalid' 999 >/dev/null 2>&1; then fail "a multiline version was accepted"; fi
    if run_bump "$dir" 9.9.9 $'999\ninvalid' >/dev/null 2>&1; then fail "a multiline build was accepted"; fi
    [ "$(fingerprint "$dir")" = "$before" ] || fail "a refused bump wrote files"

    echo "bump-version self-test passed"
}

[ $# -gt 0 ] || usage
if [ "$1" = "--self-test" ]; then
    self_test
    exit 0
fi
[ $# -eq 2 ] || usage

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREVIOUS_VERSION="$("$ROOT/scripts/project-version.sh" --project "$ROOT/project.yml")"
run_bump "$ROOT" "$1" "$2"

if [ "$1" = "$PREVIOUS_VERSION" ]; then
    cat <<'PROSE'

A resubmission keeps its CHANGELOG section and What's New entry, so there is no prose to
write. Open the bump as a pull request and tag only after it merges.
PROSE
else
    cat <<PROSE

Still yours to write — these carry meaning, not a substitution:
  CHANGELOG.md                    a '## [$1]' section, plus its link definitions
  Vitrine/Help/ReleaseNotes.swift the in-app What's New entry for $1

Then: open the bump as a pull request and tag only after it merges. A tag on the
pre-bump commit fails the release workflow's version guard (docs/RELEASING.md).
PROSE
fi
