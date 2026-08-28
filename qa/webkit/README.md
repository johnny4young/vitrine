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
2. Run `pbcopy < webkit/remote-resource-blocked.html` and trigger Vitrine.
3. Wait for the visible marker to settle, then export the result.
4. Pass only if it reads `REMOTE_BLOCKED`. `REMOTE_LOADED — FAIL` is a release blocker.

The fixture deliberately requests `https://example.com/favicon.ico`. The pasted-HTML
policy must block it; the marker makes an accidental successful load visible.

## 3. Real public URL capture

1. Run `pbcopy < webkit/public-url.txt` and trigger Vitrine.
2. Accept the first-use disclosure when shown and wait for the real page to finish.
3. Export the snapshot and confirm it is a non-placeholder capture of example.com.

## 4. Immediate local/private rejection

Copy each line from `blocked-destinations.txt` in turn and trigger Vitrine. Pass only if
the loopback and private destinations are rejected before a WebKit page begins loading.
Record the visible domain error, not any unrelated later timeout.

## Explicit evidence boundary

This manual journey does **not** certify public-to-private redirect revalidation. That
policy remains covered by deterministic navigation-delegate tests. Do not mark or describe
it as clean-Mac validated from these fixtures.
