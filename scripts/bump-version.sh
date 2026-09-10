#!/usr/bin/env bash
# Rewrites the mechanical half of the release version lockstep.
#
# A release moves the version through eleven places. Six of them are mechanical
# substitutions that a person retypes by hand today, and the release workflow refuses to
# tag if any one of them disagrees. The other half is prose — a changelog section, the
# in-app What's New — that has to be written, so this prints those instead of guessing.
#
# Every rewrite is anchored and must match exactly once. A pattern that stops matching
# is a hard failure rather than a silent skip: skipping is precisely how a site gets
# left behind, and the tag guard would then reject the release after the fact.
set -euo pipefail

usage() {
    cat >&2 <<'USAGE'
usage: bump-version.sh VERSION BUILD
       bump-version.sh --self-test

  VERSION   stable SemVer, e.g. 1.2.3 (the dialect the release tag guard enforces)
  BUILD     positive integer, must be greater than the current build
USAGE
    exit 2
}

# Each entry: file | description | sed expression. The expressions anchor on the
# surrounding syntax, never on the old version alone, so historical prose that mentions
# an older version (docs/RELEASING.md records which release removed CodeQL) is untouched.
rewrite_sites() {
    local v="$1" b="$2"
    cat <<SITES
project.yml|MARKETING_VERSION|s/^([[:space:]]*MARKETING_VERSION:[[:space:]]*")[^"]*(")/\\1${v}\\2/
project.yml|CURRENT_PROJECT_VERSION|s/^([[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*")[^"]*(")/\\1${b}\\2/
Vitrine/CLI/CLIVersion.swift|CLI fallback version|s/^([[:space:]]*static let fallbackMarketingVersion = ")[^"]*(")/\\1${v}\\2/
Vitrine/CLI/CLIVersion.swift|CLI fallback build|s/^([[:space:]]*static let fallbackBuildNumber = ")[^"]*(")/\\1${b}\\2/
packaging/Casks/vitrine.rb|Homebrew cask version|s/^([[:space:]]*version ")[^"]*(")/\\1${v}\\2/
site/src/components/Commercial.astro|site release version|s/^(const releaseVersion = ')[^']*(';)/\\1${v}\\2/
docs/APP-STORE.md|App Store marketing version|s/^(\\| Marketing version \\| \`)[^\`]*(\`)/\\1${v}\\2/
docs/APP-STORE.md|App Store build number|s/^(\\| Build number \\| \`)[^\`]*(\`)/\\1${b}\\2/
README.md|status badge|s/(status-v)[0-9][^-]*(--candidate-orange)/\\1${v}\\2/
README.md|status sentence|s/(\\*\\*v)[0-9][0-9.]*( \\(build )[0-9]+(\\) is the current release candidate)/\\1${v}\\2${b}\\3/
README.md|release-line sentence|s/(not part of the v)[0-9][0-9.]*( release line)/\\1${v}\\2/
SITES
}

apply_bump() {
    local v="$1" b="$2" root="$3" failures=0
    while IFS='|' read -r file description expression; do
        [ -n "$file" ] || continue
        local path="$root/$file"
        if [ ! -f "$path" ]; then
            echo "bump-version: missing $file" >&2
            failures=1
            continue
        fi
        local before after
        before="$(cat "$path")"
        after="$(printf '%s' "$before" | sed -E "$expression")"
        if [ "$before" = "$after" ]; then
            echo "bump-version: $file — '$description' matched nothing; the anchor moved" >&2
            failures=1
            continue
        fi
        printf '%s\n' "$after" > "$path"
        echo "  rewrote $file — $description"
    done < <(rewrite_sites "$v" "$b")
    return "$failures"
}

self_test() {
    local dir; dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' RETURN
    local root; root="$(cd "$(dirname "$0")/.." && pwd)"

    # Copy the real files, so the anchors are tested against the shapes actually shipped.
    while IFS='|' read -r file _ _; do
        [ -n "$file" ] || continue
        mkdir -p "$dir/$(dirname "$file")"
        cp "$root/$file" "$dir/$file"
    done < <(rewrite_sites 9.9.9 999)

    apply_bump 9.9.9 999 "$dir" >/dev/null

    local missed=0
    grep -q 'MARKETING_VERSION: "9.9.9"' "$dir/project.yml" || { echo "self-test: project version" >&2; missed=1; }
    grep -q 'CURRENT_PROJECT_VERSION: "999"' "$dir/project.yml" || { echo "self-test: project build" >&2; missed=1; }
    grep -q 'fallbackMarketingVersion = "9.9.9"' "$dir/Vitrine/CLI/CLIVersion.swift" || { echo "self-test: cli version" >&2; missed=1; }
    grep -q 'fallbackBuildNumber = "999"' "$dir/Vitrine/CLI/CLIVersion.swift" || { echo "self-test: cli build" >&2; missed=1; }
    grep -q 'version "9.9.9"' "$dir/packaging/Casks/vitrine.rb" || { echo "self-test: cask" >&2; missed=1; }
    grep -q "releaseVersion = '9.9.9'" "$dir/site/src/components/Commercial.astro" || { echo "self-test: site" >&2; missed=1; }
    grep -q 'status-v9.9.9--candidate' "$dir/README.md" || { echo "self-test: badge" >&2; missed=1; }
    grep -q '\*\*v9.9.9 (build 999) is the current release candidate' "$dir/README.md" || { echo "self-test: status sentence" >&2; missed=1; }
    grep -q 'not part of the v9.9.9 release line' "$dir/README.md" || { echo "self-test: release line" >&2; missed=1; }
    grep -q '| Marketing version | `9.9.9`' "$dir/docs/APP-STORE.md" || { echo "self-test: app store version" >&2; missed=1; }
    grep -q '| Build number | `999`' "$dir/docs/APP-STORE.md" || { echo "self-test: app store build" >&2; missed=1; }
    [ "$missed" -eq 0 ] || return 1

    # An anchor that no longer matches must fail loudly rather than skip the file.
    printf 'nothing to match here\n' > "$dir/project.yml"
    if apply_bump 9.9.9 999 "$dir" >/dev/null 2>&1; then
        echo "self-test: a moved anchor was accepted" >&2
        return 1
    fi

    echo "bump-version self-test passed"
}

[ $# -gt 0 ] || usage
if [ "$1" = "--self-test" ]; then self_test; exit 0; fi
[ $# -eq 2 ] || usage

VERSION="$1"
BUILD="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

printf '%s' "$VERSION" | grep -qE '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' || {
    echo "bump-version: '$VERSION' is not a stable SemVer version the release tag guard would accept" >&2
    exit 1
}
printf '%s' "$BUILD" | grep -qE '^[1-9][0-9]*$' || {
    echo "bump-version: build '$BUILD' must be a positive integer" >&2
    exit 1
}

CURRENT_BUILD="$("$ROOT/scripts/project-version.sh" --build --project "$ROOT/project.yml")"
if [ "$BUILD" -le "$CURRENT_BUILD" ]; then
    echo "bump-version: build $BUILD must be greater than the current $CURRENT_BUILD — Sparkle decides 'is this newer?' from it" >&2
    exit 1
fi

echo "Bumping to $VERSION (build $BUILD):"
apply_bump "$VERSION" "$BUILD" "$ROOT"

cat <<PROSE

Still yours to write — these carry meaning, not a substitution:
  CHANGELOG.md                    a '## [$VERSION]' section, plus its link definitions
  Vitrine/Help/ReleaseNotes.swift the in-app What's New entry for $VERSION

Then: open the bump as a pull request and tag only after it merges. A tag on the
pre-bump commit fails the release workflow's version guard (docs/RELEASING.md).
PROSE
