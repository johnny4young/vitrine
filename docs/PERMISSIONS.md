# Permission and entitlement matrix — CS-065

> The canonical, reviewable record of **every** entitlement and privacy-sensitive
> permission Vitrine declares, per product phase and per distribution channel. The goal
> is to keep the permission set **minimal and reviewable**: permission creep damages
> trust and can break App Store review, so any change to the shipped entitlements must be
> reflected here in the same change. `Tests/PrivacyManifestTests.swift` fails if the
> shipped entitlements, `Info.plist` usage strings, or privacy manifest drift from this
> matrix without an explicit update.

This document is the per-phase, per-channel companion to the narrative posture in
[`docs/PROJECT.md`](PROJECT.md#privacy-and-permissions). Where that file explains the
*promise*, this one is the *audit table*: each entitlement with its reason, user-facing
behavior, whether it is required, the test/review check that guards it, and its App Store
impact.

## How to read this

- A **product phase** is a capability tier of the app: Phase 1 (code rendering, today),
  Product Phase 2 (URL capture, deferred and opt-in), and the parked optional
  screen/window capture. See [`docs/RENDER-PHASES.md`](RENDER-PHASES.md) and
  [`docs/SCREEN-CAPTURE-DISCOVERY.md`](SCREEN-CAPTURE-DISCOVERY.md).
- A **distribution channel** is how a build reaches users: the direct-download build
  (signed + notarized DMG) and the optional App Store build. The CLI (`vitrine`) is a
  separate first-party target with its own (empty) permission profile.
- **Required** means the capability does not function without the entitlement/permission.
  **Optional** means the app degrades gracefully when it is absent or denied.
- An **entitlement** is granted at build time (the app target's
  `Vitrine.entitlements`); a **TCC permission** (e.g. Screen Recording) is granted by the
  *user* at runtime and can be revoked. Both are tracked here.

The single source of truth for what actually ships is
[`Vitrine/Resources/Vitrine.entitlements`](../Vitrine/Resources/Vitrine.entitlements),
[`Vitrine/Resources/Info.plist`](../Vitrine/Resources/Info.plist), and
[`Vitrine/Resources/PrivacyInfo.xcprivacy`](../Vitrine/Resources/PrivacyInfo.xcprivacy).
This matrix describes them; the tests assert the two agree.

## Phase 1 — code rendering (today, shipping)

Phase 1 is the entire shipping app. Turning copied code into an image is fully local and
on-device (SwiftUI → `ImageRenderer` → PNG/PDF). **Phase 1 requests no network and no
Screen Recording.** The only declared usage is reading the clipboard to render what you
copied.

| Entitlement / permission | Reason | User-facing behavior | Required? | Test / review check | App Store impact |
| --- | --- | --- | --- | --- | --- |
| `com.apple.security.app-sandbox` | Run under the App Sandbox; the baseline containment for a Mac app. | None visible; the app is sandboxed. | **Required** | `PrivacyManifestTests` asserts the key is present and `true`. | Required for App Store; expected for a sandboxed direct-download build. |
| `com.apple.security.files.user-selected.read-write` | Save rendered images via `NSSavePanel` and import/open files the user explicitly selects or drags (presets, themes, backgrounds, a source file). | A standard save/open panel; a dragged file is a user-selected, security-scoped resource. | **Required** | `PrivacyManifestTests` asserts the key is present and `true`, and that no broader file entitlement is added. | Benign; user-initiated file access is expected and not flagged. |
| `NSPasteboardUsageDescription` (Info.plist) | Read the clipboard to turn copied code (or, in Phase 2, a copied URL) into an image. | macOS shows the usage string the first time the app reads the pasteboard. | **Required** | `PrivacyManifestTests` asserts the string exists and keeps the Phase 1 promise ("never leaves your Mac"). | Benign; a clear, demonstrable reason for clipboard access. |
| `com.apple.security.network.client` | — **not requested in Phase 1.** | — | **Absent** | `PrivacyManifestTests` asserts the key is **absent**; `NetworkCapability` reads it at runtime and refuses any URL capture while absent. | Phase 1 reports **no network**; nothing to justify. |
| Screen Recording (TCC) | — **not requested in Phase 1.** | No TCC prompt; the app cannot see the screen. | **Absent** | `PrivacyManifestTests` and `ScreenCaptureDecisionTests` assert no Screen Recording entitlement, usage string, or capture API ships. | Phase 1 reports **no Screen Recording**; nothing to justify. |
| Accessibility (TCC) | — **not requested.** | No TCC prompt. | **Absent** | No `AXUIElement`/Accessibility API in the shipped sources. | None. |

**Privacy manifest (Phase 1).** `PrivacyInfo.xcprivacy` declares `NSPrivacyTracking =
false`, an empty `NSPrivacyCollectedDataTypes`, and a single required-reason API,
`NSPrivacyAccessedAPICategoryUserDefaults` (reason `CA92.1`), used only to store the app's
own settings. App Store privacy label: **Data Not Collected.**

## Product Phase 2 — URL capture (deferred, opt-in)

Product Phase 2 lets a copied **URL** be captured by loading the requested webpage
**locally in WebKit on this Mac** (`WKWebView`) and rasterizing it on-device. There is
**no remote screenshot service**. This phase is deferred: the code path exists but stays
disabled until the app target deliberately adds the network entitlement.

**The network client entitlement is required only for URL loading.** Nothing else in the
app needs it; code rendering remains fully local without it.

| Entitlement / permission | Reason | User-facing behavior | Required? | Test / review check | App Store impact |
| --- | --- | --- | --- | --- | --- |
| `com.apple.security.network.client` | **Required only for URL loading.** Lets a sandboxed build make the outbound request that loads a user-requested `http`/`https` page into an offscreen `WKWebView`. | URL capture becomes available; a first-use disclosure (`WebPrivacyDisclosureView`) explains the local-WebKit behavior and restates the Phase 1 promise before any page loads — nothing loads until the user confirms. | **Required for Phase 2** (and only Phase 2). Absent in Phase 1; when absent, `NetworkCapability.isURLCaptureEnabled` is `false` and the renderer refuses early. | When added, `PrivacyManifestTests` forces this matrix, the privacy copy (`README`, `PROJECT.md`), and the App Store posture to be revisited in the same change. Today the test asserts it is **absent**. | Adding outbound network changes the App Store privacy posture and review narrative; reviewers expect the documented "loads locally, no remote service" justification. Still **Data Not Collected** (no tracking, no telemetry). |
| `NSPasteboardUsageDescription` (Info.plist) | Already present from Phase 1; its copy already covers reading a copied URL and notes the URL is captured **locally in WebKit**. | The same clipboard usage string. | **Required** (shared with Phase 1) | `WebSnapshotPrivacyUXTests` asserts the string names local-WebKit capture. | Unchanged. |
| Screen Recording (TCC) | — **not used by URL capture.** Rasterizing a `WKWebView` Vitrine drew itself never touches the screen, so no Screen Recording permission is involved. | No TCC prompt. | **Absent** | `ScreenCaptureDecisionTests` asserts no capture API in the web-rendering surface. | None. |

**Privacy manifest (Phase 2).** Unchanged from Phase 1. Loading a user-requested page in a
local `WKWebView` introduces **no** required-reason API beyond UserDefaults and collects no
data, so `NSPrivacyTracking` stays `false`, `NSPrivacyCollectedDataTypes` stays empty, and
the label remains **Data Not Collected**. The manifest changes only if a new required-reason
API or data collection is actually introduced.

## Optional arbitrary screen / window capture — parked (⏸ Future)

This is a *different product* from "Vitrine renders its own pixels": capturing the **real
desktop** — other apps' windows or a display region — rather than a view Vitrine draws.
The discovery in [`docs/SCREEN-CAPTURE-DISCOVERY.md`](SCREEN-CAPTURE-DISCOVERY.md) (CS-046)
concluded **park it**, ship no capture code in the app target, and revive it only behind a
separate, explicit approval.

**Arbitrary screen/window capture requires the Screen Recording permission and must stay
out of core until approved.** Holding it at all — even unused — would erase the "no Screen
Recording" line the rest of this matrix guarantees.

| Entitlement / permission | Reason | User-facing behavior | Required? | Test / review check | App Store impact |
| --- | --- | --- | --- | --- | --- |
| Screen Recording (TCC) — *Screen & System Audio Recording* on macOS 15+ | The **only** way to capture arbitrary windows/displays; `ScreenCaptureKit` returns nothing capturable until the user grants it. | A TCC prompt on first capture (re-confirmed periodically by recent macOS); denial cannot be worked around. Would also require an `NSScreenCaptureUsageDescription` usage string and a first-use explanation. | **Required if ever built** — but **must stay out of core until approved**; not shipped today. | `ScreenCaptureDecisionTests` fails if any Screen Recording entitlement, `NSScreenCaptureUsageDescription`, or capture API (`ScreenCaptureKit`/`SCScreenshotManager`/legacy Quartz/AVFoundation) appears in the shipped targets without re-opening the decision. | Heaviest privacy-sensitive permission Vitrine could ask for; materially changes the App Store privacy posture and review narrative and invites extra scrutiny. Not justified by the feature's value today. |

**If ever revived,** the only acceptable implementation is `ScreenCaptureKit` +
`SCScreenshotManager` behind the prototype-validation checklist in the discovery doc, with
this matrix, `PrivacyInfo.xcprivacy`, the App Store privacy labels, and the entitlement set
(CS-062) updated *before* any merge to the app target. The legacy Quartz/AVFoundation/
Accessibility paths remain permanently rejected.

## CLI (`vitrine`) — command-line renderer

The CLI (CS-033) is a separate first-party target (`VitrineCLI`, a `tool`), **not** a
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
Sparkle entirely and stays network-free (CS-064, see the Auto-update row). Outside of that,
there is no "App Store build" that secretly drops a capability or "direct build" that secretly
adds one.

| Capability | Direct-download build (signed + notarized DMG) | App Store build (optional, post-v0.1) |
| --- | --- | --- |
| App Sandbox | On (`com.apple.security.app-sandbox`). | On — **required** by the App Store. |
| User-selected file access | `com.apple.security.files.user-selected.read-write`. | Same; user-initiated file access is expected and accepted. |
| Clipboard | `NSPasteboardUsageDescription` present. | Same; a clear reason satisfies review. |
| Network (Phase 1) | Present **only** for Sparkle auto-update (`com.apple.security.network.client`, in `Vitrine.DirectDownload.entitlements`); the core render path is still fully local. | **Absent**; reported as no network. |
| Network (Phase 2, if enabled) | `com.apple.security.network.client` already present for updates; URL capture is additionally gated by `NetworkCapability` + a first-use disclosure. | Network entitlement added deliberately before submission; review narrative is "loads the user's URL locally in WebKit, no remote service, no data collected." |
| Auto-update (CS-064) | **Sparkle.** Bundled and gated by `VITRINE_DIRECT_DOWNLOAD`; signs a signed EdDSA appcast; needs the network + `com.apple.security.temporary-exception.mach-lookup.global-name` (`…-spks`/`…-spki`) entitlements in `Vitrine.DirectDownload.entitlements`. No analytics (`SUEnableSystemProfiling = NO`). | **Excluded.** The App Store provides updates; a third-party updater is disallowed. The build removes `VITRINE_DIRECT_DOWNLOAD` and strips the Sparkle framework, so no Sparkle, no network entitlement, no update UI. |
| Screen Recording | **Absent** (parked). | **Absent** (parked); avoids the heaviest review scrutiny. |
| Privacy label | Manifest declares no tracking / no collected data. | **Data Not Collected**, kept in sync with `PrivacyInfo.xcprivacy`. |
| Hardened Runtime | On (`ENABLE_HARDENED_RUNTIME = YES`), required for notarization. | On. |
| Notarization | Required for Gatekeeper on a direct download. | Handled by App Store submission. |

See [`docs/RELEASING.md`](RELEASING.md) for the signing/notarization workflow and
[`docs/PROJECT.md`](PROJECT.md#distribution-oss) for the distribution plan.

## Change policy — keep this matrix and the build in sync

1. **No silent permission additions.** Adding any entitlement, `Info.plist` usage string,
   or required-reason API to the shipped app target requires a row here describing its
   reason, user-facing behavior, whether it is required, its test/review check, and its
   App Store impact — in the same change.
2. **The tests are the guard.** `Tests/PrivacyManifestTests.swift` reads the committed
   `Vitrine.entitlements`, `Info.plist`, and `PrivacyInfo.xcprivacy` and fails if they
   drift from this matrix (e.g. a network or Screen Recording entitlement appears, the
   clipboard usage string loses the Phase 1 promise, or the manifest starts declaring
   tracking or collected data). A drift forces a deliberate update to both the matrix and
   the tests, not a quiet expansion of the permission set.
3. **Phase gates stay enforced in code, not just docs.** `NetworkCapability` reads the
   network entitlement at runtime so a Phase 1 build provably cannot reach the network;
   the screen-capture decision is enforced by `ScreenCaptureDecisionTests` scanning the
   shipped sources. The matrix documents these gates; the code and tests enforce them.
