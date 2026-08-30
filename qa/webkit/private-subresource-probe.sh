#!/usr/bin/env bash
# Observe whether URL capture attempts any literal-loopback subresource request.
set -euo pipefail

readonly PUBLIC_FIXTURE_ORIGIN="https://httpbin.org/base64"

fail() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

OUTPUT_DIRECTORY="${1:-}"
ACTION="${2:-}"
[ -n "$OUTPUT_DIRECTORY" ] && [[ "$ACTION" =~ ^(prepare|verify)$ ]] \
	|| fail "usage: $0 <evidence-directory> <prepare|verify>"

mkdir -p "$OUTPUT_DIRECTORY"
OUTPUT_DIRECTORY="$(cd -- "$OUTPUT_DIRECTORY" && pwd)"
readonly OUTPUT_DIRECTORY ACTION
readonly PID_PATH="${OUTPUT_DIRECTORY}/private-subresource-probe.pid"
readonly PORT_PATH="${OUTPUT_DIRECTORY}/private-subresource-probe.port"
readonly URL_PATH="${OUTPUT_DIRECTORY}/private-subresource-probe.url.txt"
readonly WIRE_PATH="${OUTPUT_DIRECTORY}/private-subresource-probe.wire.bin"
readonly STDERR_PATH="${OUTPUT_DIRECTORY}/private-subresource-probe.stderr.txt"
readonly CONTROL_PATH="${OUTPUT_DIRECTORY}/private-subresource-probe.control.html"
readonly METADATA_PATH="${OUTPUT_DIRECTORY}/private-subresource-probe.metadata.txt"

if [ "$ACTION" = "prepare" ]; then
	command -v nc >/dev/null || fail "the macOS nc command is required"
	command -v openssl >/dev/null || fail "the macOS openssl command is required"
	command -v pbcopy >/dev/null || fail "the macOS pbcopy command is required"

	if [ -s "$PID_PATH" ]; then
		old_pid="$(cat "$PID_PATH")"
		if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
			fail "a previous private-subresource probe is still running (PID ${old_pid})"
		fi
	fi

	port="${VITRINE_PRIVATE_PROBE_PORT:-43127}"
	[[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] \
		|| fail "VITRINE_PRIVATE_PROBE_PORT must be an integer from 1024 through 65535"

	private_origin="https://127.0.0.1:${port}"
	html="$(cat <<HTML
<!doctype html><meta charset=utf-8><title>Vitrine private subresource probe</title>
<link rel=stylesheet href=${private_origin}/private/style.css>
<script src=${private_origin}/private/script.js></script>
<body><h1>PRIVATE_SUBRESOURCE_PROBE_READY</h1>
<img src=${private_origin}/private/image.png alt="private image must stay blocked">
<iframe src=${private_origin}/private/frame.html title="private frame must stay blocked"></iframe>
<script>
fetch('${private_origin}/private/fetch').catch(() => {});
try { new WebSocket('wss://127.0.0.1:${port}/private/socket'); } catch (_) {}
</script></body>
HTML
)"
	encoded="$(printf '%s' "$html" | openssl base64 -A)"
	encoded="${encoded//+/%2B}"
	encoded="${encoded//\//%2F}"
	encoded="${encoded//=/%3D}"
	probe_url="${PUBLIC_FIXTURE_ORIGIN}/${encoded}"

	# Prove the public top-level fixture is available before listening. curl does
	# not evaluate its subresources, so it cannot touch the private probe itself.
	curl --fail --silent --show-error --location --max-time 30 \
		--output "$CONTROL_PATH" -- "$probe_url"
	grep -q 'PRIVATE_SUBRESOURCE_PROBE_READY' "$CONTROL_PATH" \
		|| fail "the public control page did not contain its expected marker"

	: > "$WIRE_PATH"
	: > "$STDERR_PATH"
	nohup nc -4 -l 127.0.0.1 "$port" </dev/null >"$WIRE_PATH" 2>"$STDERR_PATH" &
	probe_pid=$!
	printf '%s\n' "$probe_pid" > "$PID_PATH"
	printf '%s\n' "$port" > "$PORT_PATH"
	printf '%s\n' "$probe_url" > "$URL_PATH"
	sleep 0.25
	if ! kill -0 "$probe_pid" 2>/dev/null; then
		fail "the loopback listener could not bind port ${port}; choose VITRINE_PRIVATE_PROBE_PORT"
	fi

	printf '%s' "$probe_url" | pbcopy
	printf 'Private-subresource probe prepared on loopback port %s.\n' "$port"
	printf 'The public fixture URL is on the clipboard; capture it in Vitrine now.\n'
	printf 'After the exported snapshot shows PRIVATE_SUBRESOURCE_PROBE_READY, run:\n'
	printf '  %s %q verify\n' "$0" "$OUTPUT_DIRECTORY"
	exit 0
fi

[ -s "$PID_PATH" ] || fail "prepare evidence is missing: ${PID_PATH}"
[ -s "$PORT_PATH" ] || fail "prepare evidence is missing: ${PORT_PATH}"
[ -s "$URL_PATH" ] || fail "prepare evidence is missing: ${URL_PATH}"
probe_pid="$(cat "$PID_PATH")"
[[ "$probe_pid" =~ ^[0-9]+$ ]] || fail "the recorded listener PID is invalid"

# A failed policy normally causes TLS ClientHello bytes to arrive and nc to exit.
# Requiring the listener to remain alive closes the empty-log false positive where
# a listener crashed or accepted a connection that sent no payload.
kill -0 "$probe_pid" 2>/dev/null \
	|| fail "the listener stopped before verification; a private connection may have occurred"
kill "$probe_pid"
sleep 0.1

[ ! -s "$WIRE_PATH" ] \
	|| fail "WebKit sent bytes to the literal-loopback probe; private subresources were not isolated"
[ ! -s "$STDERR_PATH" ] \
	|| fail "the loopback listener reported an error; the observation is inconclusive"

{
	printf 'publicFixtureOrigin: %s\n' "$PUBLIC_FIXTURE_ORIGIN"
	printf 'privateDestination: literal IPv4 loopback\n'
	printf 'resourceTypes: image, style-sheet, script, child-document, fetch, websocket\n'
	printf 'observedPrivateBytes: 0\n'
	printf 'result: pass\n'
} > "$METADATA_PATH"
rm -f "$PID_PATH"

printf 'Private-subresource probe passed: zero private request bytes observed.\n'
