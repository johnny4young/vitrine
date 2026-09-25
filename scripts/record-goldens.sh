#!/usr/bin/env bash
# Record reviewable synthetic fixtures through xcresult, without reading the app container.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="${GOLDEN_RECORD_RESULT_BUNDLE:-${root}/build/record-goldens.xcresult}"
destination="${GOLDEN_DEST_ROOT:-${root}/Tests/Fixtures}"
mkdir -p "$(dirname "$bundle")"
rm -rf "$bundle"
env SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1 xcodebuild \
    -project "${root}/${PROJECT:-Vitrine.xcodeproj}" -scheme "${SCHEME:-Vitrine}" \
    -configuration Debug -destination 'platform=macOS' -enableCodeCoverage NO \
    -resultBundlePath "$bundle" \
    -only-testing:VitrineTests/GoldenRecorderTests \
    '-only-testing:VitrineTests/SocialCardGoldenTests/recordDefaultFixture()' \
    VITRINE_RECORD_GOLDENS=1 VITRINE_RECORD_SOCIAL_CARD=1 test
python3 "${root}/scripts/check-golden-results.py" \
    --export-recording "$bundle" --fixtures "$destination"
echo "Review both fixture sets and their environment manifests before committing."
