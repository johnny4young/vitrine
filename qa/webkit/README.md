# Installed-candidate WebKit qualification

Run every scenario against **Vitrine installed from the candidate DMG**, once on a clean
macOS 15 Sequoia Mac and once on a clean macOS 26 Tahoe Mac. Keep the deterministic fake
UI-test renderer out of this journey: the purpose is to exercise the real `WKWebView`
process, sandbox, and packaged entitlements.

Record exact environment data and pass/fail evidence in `qualification-log.json`. Store
screenshots and exported captures in the handoff's `evidence/` directory. Do not record
credentials, private pages, cookies, or local file paths that identify a user.

## 1. Local HTML without network

1. Disconnect every network interface.
2. Run `pbcopy < webkit/local-safe.html` from the handoff directory.
3. Trigger Vitrine and export the Web Snapshot.
4. Pass only if the rendered result visibly contains `VITRINE_LOCAL_SAFE`.

This fixture contains no remote URL or subresource. A pass proves the installed candidate
can launch real WebKit and render pasted HTML while offline.

## 2. Pasted HTML blocks a remote subresource

1. Reconnect the Mac.
2. Run `webkit/verify-remote-probe.sh evidence before`. This must download and validate
   the exact control PNG successfully.
3. Run `pbcopy < webkit/remote-resource-blocked.html` and trigger Vitrine.
4. Wait for the visible marker to settle, then export the result.
5. Run `webkit/verify-remote-probe.sh evidence after`. This must succeed and confirm the
   before/after control PNG bytes are identical.
6. Pass only if both control runs succeeded and the rendered marker reads
   `REMOTE_REQUEST_FAILED — VERIFY CONTROL`. `REMOTE_LOADED — FAIL` is a release blocker.

The fixture and control script both request `https://httpbin.org/image/png`. An `onerror`
marker alone is insufficient evidence because DNS, TLS, HTTP, or image-decoding failures
could produce the same event. The two successful controls prove the public image was
available immediately around the installed-candidate run; the rendered failure between
them is the clean-Mac qualification evidence. Deterministic content-rule tests remain the
policy proof.

## 3. Real public URL capture

1. Run `pbcopy < webkit/public-url.txt` and trigger Vitrine.
2. Accept the first-use disclosure when shown and wait for the real page to finish.
3. Export the snapshot and confirm it is a non-placeholder capture of example.com.

## 4. Public page blocks literal-private subresources

1. Run `webkit/private-subresource-probe.sh evidence prepare`. It downloads and
   validates a public HTML control, starts a loopback wire listener, and copies the
   generated public fixture URL to the clipboard.
2. Trigger Vitrine's **URL capture** (not pasted-HTML capture), export the real WebKit
   result, and require the visible marker `PRIVATE_SUBRESOURCE_PROBE_READY`.
3. Run `webkit/private-subresource-probe.sh evidence verify`.
4. Pass only when the verify command reports **zero private request bytes observed**.

The public page attempts an image, stylesheet, script, child frame, `fetch`, and
WebSocket against a literal `127.0.0.1` HTTPS origin. HTTPS ensures mixed-content
blocking cannot create a false pass; if Vitrine's content rule is absent, the local
listener observes at least the TLS handshake. Keep the exported snapshot and generated
`private-subresource-probe.metadata.txt` together as evidence.

## 5. Immediate local/private rejection

Copy each line from `blocked-destinations.txt` in turn and trigger Vitrine. Pass only if
the loopback and private destinations are rejected before a WebKit page begins loading.
Record the visible domain error, not any unrelated later timeout.

## Explicit evidence boundary

This manual journey does **not** certify public-to-private redirect revalidation. That
policy remains covered by deterministic navigation-delegate tests. It also does not
certify a public hostname that DNS resolves or rebinds to a private address: WebKit content
rules inspect the request URL, not the resolver result, so that DNS/TOCTOU case remains a
documented residual risk. Do not mark either boundary as clean-Mac validated from these
fixtures.
