#!/usr/bin/env bash
# Render-only smoke and fail-closed strict comparison are separate contracts.
set -euo pipefail
mode="${GOLDEN_MODE:-strict}"
case "$mode" in strict|smoke) ;; *) echo "Invalid GOLDEN_MODE: $mode" >&2; exit 1 ;; esac
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="${RESULT_BUNDLE:-${root}/build/goldens.xcresult}"
log="${bundle}.log"
mkdir -p "$(dirname "$bundle")"
rm -rf "$bundle"
env SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1 xcodebuild \
    -project "${root}/${PROJECT:-Vitrine.xcodeproj}" -scheme "${SCHEME:-Vitrine}" \
    -configuration Debug -destination 'platform=macOS' -enableCodeCoverage NO \
    -resultBundlePath "$bundle" VITRINE_GOLDEN_MODE="$mode" \
    -only-testing:VitrineTests/GoldenImageTests \
    -only-testing:VitrineTests/GoldenValidationTests \
    -only-testing:VitrineTests/SocialCardGoldenTests \
    test 2>&1 | tee "$log"
if [ "$mode" = strict ]; then
    python3 "${root}/scripts/check-golden-results.py" --fixtures "${root}/Tests/Fixtures" --log "$log"
else
    echo "Render smoke only; no strict visual qualification claimed."
fi
