# Permission and Entitlement Matrix

This is the reviewable record of every entitlement and privacy-sensitive permission
Vitrine declares. The build configuration and resources are authoritative; this matrix
explains why they exist and the tests prevent silent drift.

## Sources of truth

- [`Vitrine.entitlements`](../Vitrine/Resources/Vitrine.entitlements) is the minimal
  App Store-compatible entitlement set.
- [`Vitrine.DirectDownload.entitlements`](../Vitrine/Resources/Vitrine.DirectDownload.entitlements)
  adds the narrowly scoped capabilities used by the signed direct-download channel.
- [`Info.plist`](../Vitrine/Resources/Info.plist) contains user-facing usage text.
- [`PrivacyInfo.xcprivacy`](../Vitrine/Resources/PrivacyInfo.xcprivacy) declares no
  tracking and no collected data.

A TCC permission is granted by the user at runtime and can be revoked. An entitlement
is selected at build time. Both must stay minimal and reviewable.

## Local rendering baseline

Code, terminal, HTML, social-card, and imported-image rendering is local and on-device.
The minimal App Store build requests **no network** and **no Screen Recording**.

| Entitlement or permission | Status | Reason and guard |
| --- | --- | --- |
| `com.apple.security.app-sandbox` | Required | Contains the app in the macOS App Sandbox. Tests require the key to be `true`. |
| `com.apple.security.files.user-selected.read-write` | Required | Supports explicit open, drop, import, and save operations. Tests reject broader file access. |
| `NSPasteboardUsageDescription` | Required | Explains clipboard input. The text states that copied code never leaves the Mac and that webpage capture loads locally in WebKit. |
| `com.apple.security.network.client` | Absent from the App Store-compatible set | The local render core needs no network. `NetworkCapability` refuses remote URL capture when the entitlement is absent. |
| Screen Recording | Absent | Vitrine does not capture displays or other apps. Tests reject capture APIs and usage strings. |
| Accessibility | Absent | No accessibility-control API is required. |

The privacy manifest declares `NSPrivacyTracking = false`, an empty
`NSPrivacyCollectedDataTypes`, and only the UserDefaults required-reason category
(`CA92.1`) for the app's own settings. The App Store privacy label is **Data Not
Collected**.

## Webpage capture

A requested webpage is loaded **locally in WebKit** and rasterized on the Mac. There is
**no remote screenshot service**, account, analytics, or telemetry. The network client
entitlement is **required only for URL loading** and remote image import.

The signed direct-download build already carries that entitlement for Sparkle and exposes
URL capture behind strict URL validation and a first-use disclosure. The App Store build
uses the minimal entitlement set, so remote URL capture is unavailable there unless the
channel policy, review copy, and entitlement set are deliberately changed together. Local
HTML rendering remains available because it performs no network request.

Redirects and final destinations are revalidated, private/local destinations are rejected,
downloads are bounded, and website data is non-persistent unless the user explicitly opts
into a logged-in session. These controls do not change the privacy manifest because
Vitrine collects no data.

## Arbitrary screen or window capture

Arbitrary capture requires Screen Recording and **must stay out of core until approved**.
It is intentionally absent. [`SCREEN-CAPTURE.md`](SCREEN-CAPTURE.md) records the product
boundary and the supported alternative: import an image captured by macOS, then frame,
annotate, redact, and export it locally.

If reconsidered, ScreenCaptureKit would require a separately reviewed permission flow,
App Store disclosure, entitlement and privacy review, denial/revocation tests, and a
prototype outside the shipping target. Legacy Quartz, AVFoundation screen input, and
Accessibility scraping remain rejected.

## CLI (`vitrine`) — command-line renderer

The CLI is a separate first-party target (`VitrineCLI`, a `tool`), **not** a
sandboxed `.app`. It renders **code only** and is the scriptable path itself.

| Entitlement / permission | Reason | User-facing behavior | Required? | Test / review check | App Store impact |
| --- | --- | --- | --- | --- | --- |
| App Sandbox | — **not applied.** A command-line tool is not a sandboxed app; it has no `Contents/Resources` and is not distributed through the App Store. | None; standard CLI file access. | **N/A** | The `VitrineCLI` target in `project.yml` sets no `CODE_SIGN_ENTITLEMENTS`; it excludes `WebRendering`, `AppIntents`, and `Services`. | Not an App Store artifact. |
| Network client | — **not used.** Code rendering is fully local; the CLI excludes the entire web-rendering surface, so it cannot load a URL. | None; works offline. | **Absent** | The CLI target excludes `Vitrine/WebRendering`, so `NetworkCapability` and `WKWebView` are not compiled into it. | N/A (not an App Store artifact). |
| Screen Recording | — **not used.** | None. | **Absent** | `ScreenCaptureDecisionTests` scans the shipped roots (`Vitrine`, `VitrineCLI`) for capture APIs and finds none. | N/A. |

The CLI needs no entitlements, no network, no Screen Recording, and no Accessibility. It
reads a file or stdin you point it at and writes an image where you ask.

## Distribution channels — App Store vs. direct download

The **same** app target ships through both channels, and the App Store-relevant
entitlement set is identical; only the signing/notarization, the auto-update mechanism, and
the review posture differ. The **one** deliberate capability difference is the auto-update
channel: the direct-download DMG bundles Sparkle and signs with a superset entitlements file
that adds outbound network + Sparkle's XPC exceptions, while the App Store build excludes
Sparkle entirely and stays network-free (see the Auto-update row). Outside of that,
there is no "App Store build" that secretly drops a capability or "direct build" that secretly
adds one.

| Capability | Direct-download build (signed + notarized DMG) | App Store build |
| --- | --- | --- |
| App Sandbox | On (`com.apple.security.app-sandbox`). | On — **required** by the App Store. |
| User-selected file access | `com.apple.security.files.user-selected.read-write`. | Same; user-initiated file access is expected and accepted. |
| Clipboard | `NSPasteboardUsageDescription` present. | Same; a clear reason satisfies review. |
| Network (local rendering) | Present for Sparkle updates and explicit remote inputs (`com.apple.security.network.client`, in `Vitrine.DirectDownload.entitlements`); the core render path remains local. | **Absent**; normal editing, import, and export remain network-free. |
| Network (web capture) | Available; URL capture is gated by `NetworkCapability`, strict URL validation, and a first-use disclosure. | Unavailable in the current channel because its entitlement set is intentionally network-free. |
| Auto-update | **Sparkle.** Bundled and gated by `VITRINE_DIRECT_DOWNLOAD`; signs a signed EdDSA appcast; needs the network + `com.apple.security.temporary-exception.mach-lookup.global-name` (`…-spks`/`…-spki`) entitlements in `Vitrine.DirectDownload.entitlements`. No analytics (`SUEnableSystemProfiling = NO`). | **Excluded.** The App Store provides updates; a third-party updater is disallowed. The build removes `VITRINE_DIRECT_DOWNLOAD` and strips the Sparkle framework, so no Sparkle, no network entitlement, no update UI. |
| Screen Recording | **Absent** by product design. | **Absent** by product design; Vitrine imports images instead of capturing other apps. |
| Privacy label | Manifest declares no tracking / no collected data. | **Data Not Collected**, kept in sync with `PrivacyInfo.xcprivacy`. |
| Hardened Runtime | On (`ENABLE_HARDENED_RUNTIME = YES`), required for notarization. | On. |
| Notarization | Required for Gatekeeper on a direct download. | Handled by App Store submission. |

See [`docs/RELEASING.md`](RELEASING.md) for the signing/notarization workflow and
[`docs/PROJECT.md`](PROJECT.md#distribution-and-business-model) for the distribution model.

## Change policy — keep this matrix and the build in sync

1. **No silent permission additions.** Adding any entitlement, `Info.plist` usage string,
   or required-reason API to the shipped app target requires a row here describing its
   reason, user-facing behavior, whether it is required, its test/review check, and its
   App Store impact — in the same change.
2. **The tests are the guard.** `Tests/PrivacyManifestTests.swift` reads the committed
   `Vitrine.entitlements`, `Info.plist`, and `PrivacyInfo.xcprivacy` and fails if they
   drift from this matrix (e.g. a network or Screen Recording entitlement appears, the
   clipboard usage string loses the local-rendering promise, or the manifest starts declaring
   tracking or collected data). A drift forces a deliberate update to both the matrix and
   the tests, not a quiet expansion of the permission set.
3. **Capability gates stay enforced in code, not just docs.** `NetworkCapability` reads the
   network entitlement at runtime so a network-free build provably cannot reach the network;
   the screen-capture decision is enforced by `ScreenCaptureDecisionTests` scanning the
   shipped sources. The matrix documents these gates; the code and tests enforce them.
