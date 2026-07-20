#!/usr/bin/env bash
set -euo pipefail

readonly self_path="scripts/check-repository-hygiene.sh"
readonly identifier_pattern='C''S-?[0-9]{3}|ENG-[0-9]+|Phase[0-9]|phase[0-9]|Product Phase|Architecture [A-Z]|deep-review|analysis §|audit (UX|Perf|S|I|A)-?[0-9]+|P[0-9]+-(UX|Perf|Security)-[0-9]+|WOW[ -]?#[0-9]+|(Feature|Features|Decision|PR) ?#[0-9]+|acceptance'
readonly forbidden_path_pattern='(^|/)(ROADMAP|PLANNING|BACKLOG|TICKETS?)([-_.]|$)|docs/.*(FEATURE-IDEAS|HANDOFF|DEEP-REVIEW|ANALYSIS|PRE-LAUNCH|AUDIT)'

status=0

if matches="$(git grep -I -n -E "$identifier_pattern" -- . ":!$self_path" || true)" && [[ -n "$matches" ]]; then
  printf '%s\n' 'Tracked files contain private planning identifiers:' >&2
  printf '%s\n' "$matches" >&2
  status=1
fi

if matches="$(git ls-files | grep -E "$forbidden_path_pattern" || true)" && [[ -n "$matches" ]]; then
  printf '%s\n' 'Maintainer-only planning artifacts are tracked:' >&2
  printf '%s\n' "$matches" >&2
  status=1
fi

if (( status != 0 )); then
  printf '%s\n' 'Move planning to ignored local files and describe behavior directly in tracked prose.' >&2
  exit "$status"
fi

printf '%s\n' '✓ tracked files contain no private planning identifiers or planning artifacts.'
