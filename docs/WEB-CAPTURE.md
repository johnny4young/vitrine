# Web capture privacy and validation

## Existing transport and session boundary

Web capture uses local WebKit, not a remote rendering service. The first-use
network disclosure and direct-download network capability gate remain in place.
Authentication is opt-in and the interactive sign-in window uses Vitrine's own
persistent store; it does not borrow another browser's cookies. Interactive sign-in
keeps normal cross-site navigation for SSO. Captures recheck navigation destinations
and install the existing private-host content rules before loading any page.

A fresh nonpersistent store is created for each capture by default. A page may set
and send temporary cookies during that capture; nonpersistent does **not** mean
cookie-free. Retaining website data across captures requires explicit opt-in.

Settings displays WebKit's site labels for saved website data. These labels are
not an exhaustive hostname inventory or proof that a login is still valid. The
inventory refreshes after closing sign-in, clearing data, or returning to Vitrine.
**Clear All Web Data** closes the sign-in window and removes all WebKit website data
in Vitrine's store, including cookies, local storage, cached responses, and service
worker registrations. New activity may create new data. It does not revoke a
server-side session, delete backups, or change another application's storage.

The capture filter rejects literal private/local destinations. Explicit localhost
opt-in admits only loopback, not the LAN. This is not DNS resolver isolation:
public-host DNS rebinding remains a residual risk. No alternate production
transport, blanket ATS exception, or system proxy is introduced.

## Controlled execution lane

Run on a macOS host with Xcode and a functioning WebKit process environment:

```sh
make test-web-capture WEB_CAPTURE_OUTPUT=/tmp/vitrine-web-capture-evidence
```

The dedicated pull-request workflow runs the same diagnostic lane on macOS 15 and
26 at the exact submitted head and retains its receipts and result bundle. It does
not turn a diagnostic pass into sandbox or provider qualification. It also runs a
separate native Web Snapshot UI journey with the signed Direct Download entitlement:
without loading a URL or entering credentials, the journey verifies the default-off
sign-in hint, a site-named sign-in action after opt-in, and withdrawal after opt-out.
Its fail-closed xcresult receipt requires the one selected UI case to pass, not skip.
The ordinary network-free UI lane instead verifies that URL capture and sign-in stay
unavailable even when the Debug binary carries the Direct compilation condition.
Neither lane substitutes for real VoiceOver or a live identity-provider login.

The output directory must not already exist. The runner starts an owned loopback
fixture, waits for its port, runs the selected suite, verifies **every expected
passed test** in the xcresult, and stops its own server even on failure. An empty
selection, missing scenario, skipped test, or failing test is not success.
`make web-capture-check` tests those fail-closed receipt rules without Xcode.
The fixture binds numeric loopback without reverse DNS and publishes its port
atomically. `fixture.log` retains startup output even if readiness fails. The
dedicated lane also runs five fixture regressions covering DNS independence, real
local HTTP, synthetic cross-host sign-in cookies, child failure diagnostics, and
fail-closed readiness timeout.

Some ad-hoc sandboxed test hosts cannot launch WebKit child processes. For local
diagnosis only, the existing coverage-lane signing overrides can be requested:

```sh
make test-web-capture WEB_CAPTURE_OUTPUT=/tmp/vitrine-web-capture-diagnostic \
  WEB_CAPTURE_HOST_FLAGS=--diagnostic-host
```

This changes only the command-line test host, not product settings or entitlements.
The receipt explicitly records diagnostic mode, HEAD, dirty working-tree state,
Xcode, and test devices. A diagnostic pass is **not** production sandbox, SSO
provider, native accessibility, or hosted CI qualification. Keep those acceptance
evidence categories separate.

The suite covers:

- Real relative redirects and exact snapshot dimensions.
- A private redirect refused before its target is requested.
- Private image, CSS, JavaScript, and frame requests blocked, with an unfiltered
  positive control proving that each fake private destination is reachable.
- Loopback subresources refused by default and requested only with explicit opt-in.
- Cancellation after the server observes a pending load, plus a real load timeout.
- A full-page snapshot clipped to its configured height cap.
- Synthetic app-to-identity-provider-to-app sign-in redirects: a cookie acquired
  through the sign-in WebView's data store is available to the next opted-in
  capture, while clearing that store removes it. The test injects a nonpersistent
  store to avoid writing synthetic credentials to the user's profile; production
  uses the default persistent store for both windows. This exercises WebKit's
  shared-store contract across `127.0.0.1` and `localhost` without changing
  product ATS, not a live identity provider or the complete sign-in window UI.
- Temporary cookies isolated from the next capture, site inventory, and actual
  Cache Storage removal on sign-out. The original partial purge left the cached
  synthetic private response readable; this regression must stay covered.

For fake private addresses, only the test's isolated data store uses a nonforwarding
loopback HTTP CONNECT fixture with failover disabled. It serves responses locally
and never resolves or forwards a destination. System DNS/proxy settings are not
changed. Plain HTTP fixtures do not qualify TLS, every resource category, live
SSO providers, or DNS-rebinding behavior. The default unit lane skips this suite
unless the runner supplies its explicit fixture port; only the dedicated lane
proves execution.
