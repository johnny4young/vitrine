# Mac App Store distribution readiness — CS-062

> The canonical, reviewable record of how Vitrine ships through the **optional** Mac App
> Store channel without weakening the direct-download app. App Store discoverability is
> useful, but its review constraints and sandbox rules must be **explicit**: this document
> lists the app metadata, the minimal entitlement set and its justification, the privacy
> labels (kept in sync with `PrivacyInfo.xcprivacy`), the TestFlight upload path, and the
> App Review notes. `Tests/AppStoreReadinessTests.swift` fails if this document or the
> shipped resources drift from what is documented here.

The App Store build is **post-v0.1 and optional** — the primary channel is the signed,
notarized DMG (see [`docs/RELEASING.md`](RELEASING.md)). The **same** app target ships
through both channels: there is no separate "App Store build" that secretly drops or adds a
capability. This file is the App Store companion to two existing references:

- [`docs/PERMISSIONS.md`](PERMISSIONS.md) — the per-phase, per-channel entitlement audit
  table (CS-065). Its "Distribution channels — App Store vs. direct download" section is the
  authoritative matrix; this document explains the submission posture around it.
- [`docs/PROJECT.md`](PROJECT.md#app-store-privacy-labels) — the narrative privacy promise
  and the App Store privacy labels.

The single source of truth for what actually ships is `project.yml` (the generated
`Vitrine.xcodeproj` is git-ignored), [`Vitrine/Resources/Info.plist`](../Vitrine/Resources/Info.plist),
[`Vitrine/Resources/Vitrine.entitlements`](../Vitrine/Resources/Vitrine.entitlements), and
[`Vitrine/Resources/PrivacyInfo.xcprivacy`](../Vitrine/Resources/PrivacyInfo.xcprivacy).
This document describes them; the tests assert the two agree.

## App metadata

Everything App Store Connect and a submission archive need, with the source of truth for
each value. None of these are new settings invented for the App Store — they are the
already-shipping identity of the app, listed here so a submission is reproducible.

| Field | Value | Source of truth |
| --- | --- | --- |
| Bundle identifier | `com.johnny4young.vitrine` | `project.yml` → `PRODUCT_BUNDLE_IDENTIFIER` (the `Info.plist` `CFBundleIdentifier` expands from it). |
| App name (display) | `Vitrine` | `Info.plist` → `CFBundleDisplayName`; `CFBundleName` expands from `PRODUCT_NAME`. |
| Primary category | Developer Tools (`public.app-category.developer-tools`) | `Info.plist` → `LSApplicationCategoryType`. |
| Marketing version | `0.10.0` | `project.yml` → `MARKETING_VERSION` (the `Info.plist` `CFBundleShortVersionString` expands from it). |
| Build number | `10` | `project.yml` → `CURRENT_PROJECT_VERSION` (the `Info.plist` `CFBundleVersion` expands from it). |
| Copyright | `© 2026 johnny4young. MIT-licensed.` | `Info.plist` → `NSHumanReadableCopyright`. |
| Minimum macOS | 14.0 (Sonoma) | `project.yml` → `deploymentTarget.macOS`; `Info.plist` `LSMinimumSystemVersion` expands from `MACOSX_DEPLOYMENT_TARGET`. |
| App icon | `AppIcon` asset set | `project.yml` → `ASSETCATALOG_COMPILER_APPICON_NAME`. |
| Localizations | English (development language), Spanish | `Info.plist` → `CFBundleLocalizations`; strings live in `Localizable.xcstrings` (CS-047). |
| Agent (no Dock icon) | `LSUIElement = true` | `Info.plist`. A menu-bar agent; documented in the App Review notes below so a reviewer expects no Dock icon. |

### Versioning policy

- `MARKETING_VERSION` is the user-visible version (e.g. `0.1.0`) and matches the GitHub
  release tag and the Homebrew cask. It also drives the in-app "What's New" window
  (`Vitrine/Help/ReleaseNotes.swift`, CS-049) — see the version-bump checklist in
  [`docs/RELEASING.md`](RELEASING.md#release-notes-whats-new--cs-049).
- `CURRENT_PROJECT_VERSION` is the build number. **App Store Connect requires the build
  number to be unique and strictly increasing for a given marketing version**, so a
  resubmission of the same `0.1.0` (e.g. to fix a rejected binary) must bump
  `CURRENT_PROJECT_VERSION` even though the marketing version is unchanged.
- Both live in `project.yml` (the source of truth) and flow into the `Info.plist` through
  build-setting expansion, so the DMG and an App Store archive always carry identical
  version strings.

### Signing identity (App Store vs. direct download)

The App Store and direct-download channels differ in signing identity, review posture, and
the auto-update mechanism. The App Store-relevant entitlement set is otherwise identical; the
one deliberate capability difference is **auto-update** (CS-064): the direct-download DMG
bundles Sparkle and signs with a superset entitlements file
(`Vitrine.DirectDownload.entitlements`) that adds outbound network + Sparkle's XPC exceptions,
while the **App Store build excludes Sparkle** and stays network-free (see
[`docs/PERMISSIONS.md`](PERMISSIONS.md#distribution-channels--app-store-vs-direct-download) and
[Auto-update — App Store excludes Sparkle](#auto-update--app-store-excludes-sparkle-cs-064)).

| | Direct-download DMG | Mac App Store |
| --- | --- | --- |
| Signing identity | **Developer ID Application** (+ notarization, stapling) | **Apple Distribution** / "3rd Party Mac Developer" (App Store provisioning profile) |
| Distribution | Signed, notarized DMG attached to a GitHub release; Homebrew cask | App Store Connect submission |
| Trust check | Gatekeeper (`spctl`) validates the notarized, stapled artifact offline | App Review + the App Store delivery pipeline |
| Auto-update | **Sparkle** (signed EdDSA appcast) | **Excluded** — the App Store updates the app |
| `DEVELOPMENT_TEAM` | Set from `MACOS_NOTARY_TEAM_ID` for signing (CS-061) | The same Team ID, supplied to the App Store archive/export |

### Auto-update — App Store excludes Sparkle (CS-064)

The direct-download build updates itself with [Sparkle](https://sparkle-project.org); the
**Mac App Store build excludes Sparkle entirely**, because the App Store provides its own
update mechanism and a third-party updater is not permitted there. The exclusion is enforced,
not just intended:

- The App Store archive builds with `SWIFT_ACTIVE_COMPILATION_CONDITIONS` overridden to remove
  `VITRINE_DIRECT_DOWNLOAD`, so every `#if VITRINE_DIRECT_DOWNLOAD` block (the whole Sparkle
  integration and the **Check for Updates…** menu item) compiles out — `SoftwareUpdater.isSupported`
  is `false`.
- The archive then **strips the Sparkle framework** from the app bundle and fails the job if any
  Sparkle payload remains (see `.github/workflows/appstore.yml`).
- The App Store build keeps the minimal `Vitrine.entitlements` (no network, no Sparkle XPC
  exceptions), so the documented "no network" App Store posture is unchanged.

The full direct-download update flow (EdDSA keys, the signed appcast, publishing it per release,
and testing an update from N to N+1) is documented in
[`docs/RELEASING.md`](RELEASING.md#auto-update-sparkle--cs-064).

`project.yml` keeps `DEVELOPMENT_TEAM` empty and `CODE_SIGN_STYLE: Automatic` by default so
the repo builds and tests without an Apple account; a real submission supplies the Team ID
and the App Store provisioning profile at archive/export time (manually in Xcode Organizer
or via the `ExportOptions.plist` `method: app-store` flow described below). No account
credentials are committed.

### Embedded CLI — App Store archive must address it (CS-033)

The app bundle embeds the `vitrine` command-line renderer at
`Contents/MacOS/vitrine-cli` (for the Homebrew cask's `binary` stanza). App Store
review requires **every** executable in the bundle to opt into the App Sandbox,
and the CLI is signed without sandbox entitlements on the direct-download
channel. Before an actual App Store submission, the archive step must either
**strip `Contents/MacOS/vitrine-cli`** (the App Store install has no PATH
integration, so the CLI adds no value there — mirroring how Sparkle is
stripped), or re-sign it with `com.apple.security.app-sandbox` +
`com.apple.security.inherit`. The DMG channel is unaffected.

## App Sandbox and entitlements (App Store-compatible)

**The App Sandbox stays enabled and the entitlement set is minimal and justified.** The Mac
App Store **requires** the App Sandbox; Vitrine already runs sandboxed for the direct
download, so nothing changes for the App Store. The complete, reviewable per-entitlement
table — reason, user-facing behavior, whether it is required, the test/review check, and
App Store impact — is [`docs/PERMISSIONS.md`](PERMISSIONS.md). The App Store-relevant
summary:

| Entitlement | App Store posture | Why it is acceptable |
| --- | --- | --- |
| `com.apple.security.app-sandbox` | **Required** and present. | The baseline containment the App Store mandates; Vitrine is already sandboxed. |
| `com.apple.security.files.user-selected.read-write` | Present; minimal. | Only user-initiated file access (save panel for exports; open panel / drag-in for presets, themes, backgrounds, a source file). Reviewers expect and accept user-initiated file access. |
| `com.apple.security.network.client` | **Absent in Phase 1.** | Phase 1 reports **no network**; there is nothing to justify. See the Phase 2 gate below. |
| Screen Recording (TCC) | **Absent** (arbitrary screen/window capture is parked, CS-046). | Avoids the heaviest privacy-sensitive review scrutiny. No `NSScreenCaptureUsageDescription` and no capture API ship. |

The only declared `Info.plist` usage string is `NSPasteboardUsageDescription` (clipboard),
which is the core feature: Vitrine turns the code (or, in Phase 2, the URL) you copied into
an image. `Tests/PrivacyManifestTests.swift` asserts this is the **only** usage string and
that no broader file entitlement, network entitlement, or Screen Recording entitlement is
present.

### Phase 1 App Store builds request no network

The network client entitlement is **absent** for Phase 1 App Store builds, exactly as for
the Phase 1 DMG. `NetworkCapability` reads the entitlement at runtime and refuses any URL
capture while it is absent, so a Phase 1 App Store build **provably cannot reach the
network**. The App Store privacy posture for Phase 1 is therefore "no network, no data
collected".

### If Phase 2 URL capture ships, update the network entitlement and privacy copy first

Product Phase 2 (CS-043/CS-045) lets a copied **URL** be captured by loading the requested
webpage **locally in WebKit on this Mac** (`WKWebView`) and rasterizing it on-device — there
is **no remote screenshot service**. It is deferred and opt-in. **Before** an App Store
submission that enables it, the following must be updated in the same change:

1. Add `com.apple.security.network.client` to `Vitrine.entitlements` (this is the single
   switch that enables URL capture). `Tests/PrivacyManifestTests.swift` currently asserts
   the key is **absent**, so adding it forces a deliberate matrix + test update.
2. Update the privacy copy in [`README.md`](../README.md), [`docs/PROJECT.md`](PROJECT.md),
   and [`docs/PERMISSIONS.md`](PERMISSIONS.md) to describe the outbound request, and re-check
   the App Store review narrative ("loads the user's URL locally in WebKit, no remote
   service, no data collected").
3. Confirm the first-use disclosure (`WebPrivacyDisclosureView`) is shown before any page
   loads.

The privacy **labels** do not change — loading a user-requested page locally introduces no
required-reason API beyond UserDefaults and collects no data, so the label stays **Data Not
Collected** (see below). What changes is the *network* entitlement and the *review
narrative*, not the data-collection posture.

## App Store privacy labels (match `PrivacyInfo.xcprivacy`)

The App Store privacy labels are kept in sync with the bundled privacy manifest
([`Vitrine/Resources/PrivacyInfo.xcprivacy`](../Vitrine/Resources/PrivacyInfo.xcprivacy)).
Vitrine does not track users and collects no data:

| App Store privacy label | Value | Manifest key it mirrors |
| --- | --- | --- |
| Data Used to Track You | **None** | `NSPrivacyTracking = false`, `NSPrivacyTrackingDomains` empty |
| Data Linked to You | **None** | `NSPrivacyCollectedDataTypes` empty |
| Data Not Linked to You | **None** | `NSPrivacyCollectedDataTypes` empty |
| **Overall label** | **Data Not Collected** | the manifest declares no collection |
| Required-reason API | `NSPrivacyAccessedAPICategoryUserDefaults` (reason `CA92.1`), used only to store the app's own settings | `NSPrivacyAccessedAPITypes` |

Phase 2 URL capture does **not** change these labels (see the Phase 2 gate above). The
manifest — and therefore the labels — changes only if a new required-reason API or data
collection is actually introduced. `Tests/PrivacyManifestTests.swift` asserts the manifest
stays "no tracking, no collected data, UserDefaults-only", so the labels documented here
cannot silently drift from the binary.

## TestFlight and submission upload path

Archive in Xcode (Product ▸ Archive on the `Vitrine` scheme), then deliver the validated
build to App Store Connect / TestFlight through **any** of these paths. All three are
equivalent uploads of the same archived, Apple-Distribution-signed build; none require a
credential committed to the repo.

1. **Xcode Organizer (interactive).** In the Organizer, select the archive ▸ **Validate
   App** (runs Apple's pre-submission checks), then ▸ **Distribute App** ▸ **App Store
   Connect** ▸ **Upload**. This is the simplest path and the one to use first. The uploaded
   build appears under TestFlight in App Store Connect.

2. **Transporter (GUI) or the Transporter CLI** — for delivering an already-exported
   `.pkg`. Export the archive with an App Store export method, then drag the resulting
   `.pkg` into the **Transporter** app, or use the command-line
   `xcrun iTMSTransporter` / Transporter CLI to upload it. Useful when archiving and
   uploading happen on different machines.

3. **`xcrun altool` / `notarytool`-adjacent command line.** Export, then upload the `.pkg`
   non-interactively:

   ```bash
   # 1. Export the archive for the App Store (ExportOptions.plist has method: app-store).
   xcodebuild -exportArchive \
     -archivePath Vitrine.xcarchive \
     -exportPath build/appstore \
     -exportOptionsPlist ExportOptions.plist

   # 2. Validate, then upload to App Store Connect / TestFlight.
   #    Authenticate with an App Store Connect API key (preferred) — the same key
   #    style used for notarization (CS-061): MACOS_NOTARY_KEY_ID / _ISSUER_ID / _P8.
   xcrun altool --validate-app -f build/appstore/Vitrine.pkg -t macos \
     --apiKey "$MACOS_NOTARY_KEY_ID" --apiIssuer "$MACOS_NOTARY_KEY_ISSUER_ID"
   xcrun altool --upload-app   -f build/appstore/Vitrine.pkg -t macos \
     --apiKey "$MACOS_NOTARY_KEY_ID" --apiIssuer "$MACOS_NOTARY_KEY_ISSUER_ID"
   ```

   A minimal `ExportOptions.plist` for the App Store method:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>method</key>            <string>app-store</string>
     <key>teamID</key>            <string>YOUR_TEAM_ID</string>
     <key>signingStyle</key>      <string>automatic</string>
     <key>uploadSymbols</key>     <true/>
   </dict>
   </plist>
   ```

The optional [`.github/workflows/appstore.yml`](../.github/workflows/appstore.yml) is a
**manually-triggered dry run** of the archive + `validate-app` steps, gated on the same App
Store Connect API-key secrets. It never auto-submits and skips itself cleanly when the
secrets are absent, so it is safe to keep on a repo without an Apple account. See "CI dry
run" below.

## App Review notes

Paste the following into App Store Connect's **App Review Information ▸ Notes** so a
reviewer understands the menu-bar, local-rendering, no-telemetry design before testing:

> Vitrine is a **menu-bar agent** (`LSUIElement`) — it intentionally shows **no Dock icon**
> and no app-switcher entry. After launch, click the menu-bar icon (or use the editor
> window) to use it.
>
> **Clipboard usage.** Vitrine reads the clipboard (`NSPasteboardUsageDescription`) to turn
> the code you copied into a styled image. This is the core feature. Clipboard reads happen
> on an explicit user action (the menu-bar "Quick Capture" or the editor); the app does not
> poll or read the clipboard in the background.
>
> **Local rendering, no server.** Rendering is **entirely on-device**: SwiftUI →
> `ImageRenderer` → PNG/PDF. Nothing is uploaded; there is no account, no remote rendering
> service, and no companion backend. The app works fully offline.
>
> **Launch at login (optional).** Vitrine can optionally start at login via
> `SMAppService` (`ServiceManagement`). It is **off by default** and toggled by the user in
> Settings; macOS shows it under Login Items, where the user can revoke it.
>
> **No telemetry.** There is **no analytics SDK and no telemetry anywhere** in the app. The
> privacy manifest declares no tracking and no collected data, so the privacy label is
> **Data Not Collected**. The only required-reason API is `UserDefaults`, used solely to
> store the app's own settings.
>
> **No network in this build.** This Phase 1 build requests **no network entitlement** and
> cannot reach the network. (A future opt-in feature may load a user-requested URL **locally
> in WebKit** to image it; if and when that ships, the network entitlement and this note
> will be updated and the behavior remains on-device with no remote screenshot service.)
>
> **File access.** Only user-initiated: a save panel when you export an image, and an open
> panel / drag-in when you import a theme, preset, background, or source file.

## Pre-submission checklist

- [ ] `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` bumped in `project.yml` (the build
      number is unique and increasing for this marketing version).
- [ ] Release note added to `Vitrine/Help/ReleaseNotes.swift` (newest first; version matches
      `MARKETING_VERSION`) — see [`docs/RELEASING.md`](RELEASING.md).
- [ ] `make lint && make build && make test` green (includes `AppStoreReadinessTests` and the
      permission/privacy drift guards).
- [ ] Entitlements unchanged from the documented App Store-compatible set, **or** the Phase 2
      gate above was followed (network entitlement + privacy copy + matrix + tests updated
      together).
- [ ] App icon up to date (`make icon`).
- [ ] Archived on the `Vitrine` scheme; **Validate App** passes in Xcode Organizer (or
      `xcrun altool --validate-app`).
- [ ] App Store privacy labels in App Store Connect set to **Data Not Collected**, matching
      `PrivacyInfo.xcprivacy`.
- [ ] App Review notes (above) pasted into App Store Connect.
- [ ] Uploaded to TestFlight via Organizer, Transporter, or `xcrun altool` and the build
      appears in App Store Connect.

## CI dry run (optional, no account required)

[`.github/workflows/appstore.yml`](../.github/workflows/appstore.yml) is a
`workflow_dispatch`-only job that archives the app and runs **App Store validation as a dry
run** when the App Store Connect API-key secrets (`MACOS_NOTARY_KEY_ID`,
`MACOS_NOTARY_KEY_ISSUER_ID`, `MACOS_NOTARY_KEY_P8`) are configured. It **never auto-submits
or auto-uploads** a build. When the secrets are absent (a fork, or before an Apple account
exists) the archive still builds and the validation step is skipped, so the workflow stays
green without credentials. This matches the graceful-degradation posture of the signed DMG
pipeline (CS-061): the secret-gated stages skip cleanly rather than failing the run.
