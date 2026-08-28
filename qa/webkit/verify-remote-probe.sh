#!/usr/bin/env bash
# Verify that the WebKit qualification probe is reachable immediately around the app run.
set -euo pipefail

readonly PROBE_URL="https://httpbin.org/image/png"

fail() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

OUTPUT_DIRECTORY="${1:-}"
PHASE="${2:-}"
[ -n "$OUTPUT_DIRECTORY" ] && [[ "$PHASE" =~ ^(before|after)$ ]] \
	|| fail "usage: $0 <evidence-directory> <before|after>"

mkdir -p "$OUTPUT_DIRECTORY"
OUTPUT_DIRECTORY="$(cd -- "$OUTPUT_DIRECTORY" && pwd)"
readonly OUTPUT_DIRECTORY PHASE
readonly IMAGE_PATH="${OUTPUT_DIRECTORY}/remote-probe-${PHASE}.png"
readonly HEADERS_PATH="${OUTPUT_DIRECTORY}/remote-probe-${PHASE}.headers.txt"
readonly METADATA_PATH="${OUTPUT_DIRECTORY}/remote-probe-${PHASE}.metadata.txt"

temporary_image="$(mktemp "${TMPDIR:-/tmp}/vitrine-remote-probe.XXXXXX.png")"
temporary_headers="$(mktemp "${TMPDIR:-/tmp}/vitrine-remote-probe.XXXXXX.headers")"
cleanup() { rm -f "$temporary_image" "$temporary_headers"; }
trap cleanup EXIT

curl --fail --silent --show-error --location --max-time 30 \
	--dump-header "$temporary_headers" \
	--output "$temporary_image" \
	-- "$PROBE_URL"
[ -s "$temporary_image" ] || fail "the controlled probe response is empty"
awk 'BEGIN { found = 0 }
	{ line = tolower($0); if (line ~ /^content-type:[[:space:]]*image\/png/) found = 1 }
	END { exit(found ? 0 : 1) }' "$temporary_headers" \
	|| fail "the controlled probe did not return image/png"

dimensions="$(sips -g pixelWidth -g pixelHeight "$temporary_image" 2>/dev/null \
	| awk '/pixelWidth:|pixelHeight:/')" \
	|| fail "the controlled probe bytes are not a decodable image"
grep -Eq 'pixelWidth: [1-9][0-9]*' <<< "$dimensions" \
	|| fail "the controlled probe has no positive pixel width"
grep -Eq 'pixelHeight: [1-9][0-9]*' <<< "$dimensions" \
	|| fail "the controlled probe has no positive pixel height"

mv "$temporary_image" "$IMAGE_PATH"
mv "$temporary_headers" "$HEADERS_PATH"
{
	printf 'url: %s\n' "$PROBE_URL"
	printf 'sha256: '
	shasum -a 256 "$IMAGE_PATH" | awk '{ print $1 }'
	printf '%s\n' "$dimensions"
} > "$METADATA_PATH"

if [ "$PHASE" = "after" ]; then
	readonly BEFORE_IMAGE="${OUTPUT_DIRECTORY}/remote-probe-before.png"
	[ -s "$BEFORE_IMAGE" ] \
		|| fail "the before-control image is missing from ${OUTPUT_DIRECTORY}"
	cmp --silent "$BEFORE_IMAGE" "$IMAGE_PATH" \
		|| fail "the before/after controlled probe bytes differ"
fi

printf 'Remote probe %s control passed: %s\n' "$PHASE" "$IMAGE_PATH"
