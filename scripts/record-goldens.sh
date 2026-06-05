#!/usr/bin/env bash
#
# Regenerate the golden-image fixtures + manifest (CS-025).
#
# The unit-test host is sandboxed and cannot write into the source tree, so the
# recorder test stages the PNGs and manifest in its own container temp and prints
# the (sandbox-remapped) path on a `GOLDEN OUTPUT <path>` line. This script runs
# that recorder, parses the staging path, and copies the staged files into
# Tests/Fixtures/Golden/ from outside the sandbox.
#
# Run on the pinned runner image when a deliberate visual change lands, then review
# and commit the diff. Invoked by `make record-goldens`.

set -euo pipefail

PROJECT="${PROJECT:-Vitrine.xcodeproj}"
SCHEME="${SCHEME:-Vitrine}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${REPO_ROOT}/Tests/Fixtures/Golden"

log="$(mktemp -t vitrine-record-goldens)"
trap 'rm -f "${log}"' EXIT

echo "Recording golden fixtures (this renders every scenario through the export path)…"
# VITRINE_RECORD_GOLDENS is passed as a build-setting argument so the scheme's
# $(VITRINE_RECORD_GOLDENS) environment-variable macro expands into the test
# runner; an exported shell var alone is not forwarded to the test process.
xcodebuild \
    -project "${REPO_ROOT}/${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -only-testing:VitrineTests/GoldenRecorderTests \
    VITRINE_RECORD_GOLDENS=1 \
    test 2>&1 | tee "${log}"

# The recorder prints exactly one `GOLDEN OUTPUT <abs path>` line.
staging="$(grep -m1 'GOLDEN OUTPUT ' "${log}" | sed 's/^.*GOLDEN OUTPUT //')"
if [ -z "${staging}" ] || [ ! -d "${staging}" ]; then
    echo "error: could not locate the recorder staging directory (no GOLDEN OUTPUT line)." >&2
    exit 1
fi

mkdir -p "${DEST}"
cp "${staging}"/*.png "${DEST}/"
cp "${staging}/manifest.json" "${DEST}/"

echo "Copied $(ls "${staging}"/*.png | wc -l | tr -d ' ') fixtures + manifest into ${DEST}"
echo "Review the diff and commit it on the pinned image."
