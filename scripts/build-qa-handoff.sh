#!/usr/bin/env bash
# Build the self-contained clean-Mac qualification bundle for a release candidate.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPOSITORY_ROOT
readonly WEBKIT_FIXTURES="${REPOSITORY_ROOT}/qa/webkit"

fail() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

verify_candidate_digest() {
	local dmg_path="$1"
	local sidecar_path="$2"
	local dmg_name="$3"
	local declared_digest actual_digest
	declared_digest="$(awk -v expected="$dmg_name" \
		'$2 == expected || $2 == "*" expected { print $1; exit }' "$sidecar_path" \
		| tr '[:upper:]' '[:lower:]')"
	[[ "$declared_digest" =~ ^[0-9a-f]{64}$ ]] \
		|| fail "${dmg_name}.sha256 does not contain a valid digest for ${dmg_name}"
	actual_digest="$(shasum -a 256 "$dmg_path" | awk '{ print $1 }')"
	[ "$actual_digest" = "$declared_digest" ] \
		|| fail "${dmg_name}.sha256 does not match the candidate DMG bytes"
	printf '%s\n' "$declared_digest"
}

validate_fixtures() {
	local required
	for required in \
		README.md \
		manifest.json \
		qualification-log.json \
		local-safe.html \
		remote-resource-blocked.html \
		verify-remote-probe.sh \
		public-url.txt \
		blocked-destinations.txt
	do
		[ -s "${WEBKIT_FIXTURES}/${required}" ] \
			|| fail "missing WebKit qualification fixture: qa/webkit/${required}"
	done
	python3 -m json.tool "${WEBKIT_FIXTURES}/manifest.json" >/dev/null
	python3 -m json.tool "${WEBKIT_FIXTURES}/qualification-log.json" >/dev/null
	grep -q 'VITRINE_LOCAL_SAFE' "${WEBKIT_FIXTURES}/local-safe.html" \
		|| fail "local-safe.html is missing its qualification marker"
	[ -x "${WEBKIT_FIXTURES}/verify-remote-probe.sh" ] \
		|| fail "qa/webkit/verify-remote-probe.sh must be executable"
	grep -q 'https://httpbin.org/image/png' "${WEBKIT_FIXTURES}/remote-resource-blocked.html" \
		|| fail "remote-resource-blocked.html is missing the controlled probe URL"
	grep -q 'REMOTE_REQUEST_FAILED' "${WEBKIT_FIXTURES}/remote-resource-blocked.html" \
		|| fail "remote-resource-blocked.html is missing its request-failed marker"
	grep -q 'REMOTE_LOADED' "${WEBKIT_FIXTURES}/remote-resource-blocked.html" \
		|| fail "remote-resource-blocked.html is missing its failure marker"
	grep -q 'https://httpbin.org/image/png' "${WEBKIT_FIXTURES}/verify-remote-probe.sh" \
		|| fail "verify-remote-probe.sh does not validate the fixture probe URL"
}

if [ "${1:-}" = "--self-test" ]; then
	validate_fixtures
	self_test_root="$(mktemp -d "${TMPDIR:-/tmp}/vitrine-qa-handoff-self-test.XXXXXX")"
	trap 'rm -rf "$self_test_root"' EXIT
	self_test_dmg="${self_test_root}/Vitrine-0.0.0.dmg"
	printf 'candidate bytes' > "$self_test_dmg"
	self_test_digest="$(shasum -a 256 "$self_test_dmg" | awk '{ print $1 }')"
	printf '%s  %s\n' "$self_test_digest" "$(basename "$self_test_dmg")" \
		> "${self_test_dmg}.sha256"
	verified_digest="$(verify_candidate_digest \
		"$self_test_dmg" "${self_test_dmg}.sha256" "$(basename "$self_test_dmg")")"
	[ "$verified_digest" = "$self_test_digest" ] \
		|| fail "candidate digest self-test returned the wrong digest"
	printf 'changed' >> "$self_test_dmg"
	if (verify_candidate_digest \
		"$self_test_dmg" "${self_test_dmg}.sha256" "$(basename "$self_test_dmg")" \
		>/dev/null 2>&1); then
		fail "candidate digest self-test accepted mismatched DMG bytes"
	fi
	echo "QA handoff fixtures passed self-test."
	exit 0
fi

VERSION="${1:-}"
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
	|| fail "usage: $0 <stable-version> [output.zip]"

readonly SOURCE_DIR="${QA_HANDOFF_SOURCE_DIR:-${REPOSITORY_ROOT}/dist}"
OUTPUT="${2:-${SOURCE_DIR}/Vitrine-${VERSION}-qa-handoff.zip}"
mkdir -p "$(dirname -- "$OUTPUT")"
OUTPUT="$(cd -- "$(dirname -- "$OUTPUT")" && pwd)/$(basename -- "$OUTPUT")"

readonly DMG="Vitrine-${VERSION}.dmg"
readonly REQUIRED_CANDIDATE_FILES=(
	"${DMG}"
	"${DMG}.sha256"
	"Vitrine-${VERSION}.spdx.json"
	"vitrine-cask-update.txt"
	"appcast.xml"
	"release-notes.md"
)

for candidate_file in "${REQUIRED_CANDIDATE_FILES[@]}"; do
	[ -s "${SOURCE_DIR}/${candidate_file}" ] \
		|| fail "candidate handoff input is missing or empty: ${SOURCE_DIR}/${candidate_file}"
done
validate_fixtures

DMG_SHA256="$(verify_candidate_digest \
	"${SOURCE_DIR}/${DMG}" "${SOURCE_DIR}/${DMG}.sha256" "$DMG")"
readonly DMG_SHA256

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vitrine-qa-handoff.XXXXXX")"
readonly STAGING_ROOT
readonly BUNDLE_NAME="Vitrine-${VERSION}-qa-handoff"
readonly BUNDLE_ROOT="${STAGING_ROOT}/${BUNDLE_NAME}"
cleanup() { rm -rf "$STAGING_ROOT"; }
trap cleanup EXIT

mkdir -p "${BUNDLE_ROOT}/webkit" "${BUNDLE_ROOT}/evidence"
for candidate_file in "${REQUIRED_CANDIDATE_FILES[@]}"; do
	cp "${SOURCE_DIR}/${candidate_file}" "${BUNDLE_ROOT}/${candidate_file}"
done
cp "${REPOSITORY_ROOT}/scripts/qa-release.sh" "${BUNDLE_ROOT}/qa-release.sh"
chmod 0755 "${BUNDLE_ROOT}/qa-release.sh"
cp "${REPOSITORY_ROOT}/docs/RELEASING.md" "${BUNDLE_ROOT}/RELEASING.md"
cp "${WEBKIT_FIXTURES}"/* "${BUNDLE_ROOT}/webkit/"

python3 - "${BUNDLE_ROOT}/webkit/qualification-log.json" "$VERSION" "$DMG_SHA256" <<'PY'
import json
import sys

path, version, digest = sys.argv[1:]
with open(path, encoding="utf-8") as source:
    log = json.load(source)
log["candidate"] = {"tag": f"v{version}", "version": version, "dmgSHA256": digest}
with open(path, "w", encoding="utf-8") as destination:
    json.dump(log, destination, indent=2, ensure_ascii=False)
    destination.write("\n")
PY

cat > "${BUNDLE_ROOT}/README.md" <<README
# Vitrine ${VERSION} clean-Mac QA handoff

This bundle contains the exact private candidate and the evidence template used to
qualify it on clean Sequoia and Tahoe Macs. It does not certify the candidate by itself.

1. Verify the bundle payload: \`shasum -a 256 -c SHA256SUMS\`.
2. Run \`./qa-release.sh ${DMG}\` and retain its complete output.
3. Follow \`webkit/README.md\` against the app installed from this DMG.
4. Record both platform runs in \`webkit/qualification-log.json\`; store screenshots
   and exported captures under \`evidence/\` without credentials or private content.
5. Require every scenario to pass on one clean macOS 15 Sequoia Mac and one clean
   macOS 26 Tahoe Mac before entering \`CLEAN-MAC-QA-PASSED\`.

The public-to-private redirect policy is not manually certified by these fixtures.
It remains a deterministic navigation-delegate test and must not be claimed as clean-Mac
evidence from this handoff.
README

(
	cd "$BUNDLE_ROOT"
	LC_ALL=C find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort \
		| while IFS= read -r file; do shasum -a 256 "$file"; done > SHA256SUMS
)

rm -f "$OUTPUT"
/usr/bin/ditto -c -k --keepParent "$BUNDLE_ROOT" "$OUTPUT"
/usr/bin/unzip -tq "$OUTPUT" >/dev/null
echo "QA handoff created: $OUTPUT"
