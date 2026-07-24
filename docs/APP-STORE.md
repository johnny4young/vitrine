# Mac App Store Distribution Readiness

> The canonical, reviewable record of how Vitrine ships through the **optional** Mac App
> Store channel without weakening the direct-download app. App Store discoverability is
> useful, but its review constraints and sandbox rules must be **explicit**: this document
> lists the app metadata, the minimal entitlement set and its justification, the privacy
> labels (kept in sync with `PrivacyInfo.xcprivacy`), the TestFlight upload path, and the
> App Review notes. `Tests/AppStoreReadinessTests.swift` fails if this document or the
> shipped resources drift from what is documented here.

The App Store channel is optional; the primary channel is the signed,
notarized DMG (see [`docs/RELEASING.md`](RELEASING.md)). The **same** app target ships
through both channels: there is no separate "App Store build" that secretly drops or adds a
capability. This file is the App Store companion to two existing references:

- [`docs/PERMISSIONS.md`](PERMISSIONS.md) — the per-channel entitlement audit
  table. Its "Distribution channels — App Store vs. direct download" section is the
  authoritative matrix; this document explains the submission posture around it.
- [`docs/PROJECT.md`](PROJECT.md#privacy-and-permissions) — the narrative privacy promise
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
| Marketing version | `0.24.0` | `project.yml` → `MARKETING_VERSION` (the `Info.plist` `CFBundleShortVersionString` expands from it). |
| Build number | `25` | `project.yml` → `CURRENT_PROJECT_VERSION` (the `Info.plist` `CFBundleVersion` expands from it). |
| Copyright | `© 2026 johnny4young. MIT-licensed.` | `Info.plist` → `NSHumanReadableCopyright`. |
| Minimum macOS | 14.0 (Sonoma) | `project.yml` → `deploymentTarget.macOS`; `Info.plist` `LSMinimumSystemVersion` expands from `MACOSX_DEPLOYMENT_TARGET`. |
| App icon | `AppIcon` asset set | `project.yml` → `ASSETCATALOG_COMPILER_APPICON_NAME`. |
| Localizations | English (development language), Spanish | `Info.plist` → `CFBundleLocalizations`; strings live in `Localizable.xcstrings`. |
| Agent (no Dock icon) | `LSUIElement = true` | `Info.plist`. A menu-bar agent; documented in the App Review notes below so a reviewer expects no Dock icon. |

### Versioning policy

- `MARKETING_VERSION` is the user-visible version (e.g. `0.1.0`) and matches the GitHub
  release tag and the Homebrew cask. It also drives the in-app "What's New" window
  (`Vitrine/Help/ReleaseNotes.swift`) — see the version-bump checklist in
  [`docs/RELEASING.md`](RELEASING.md#release-notes-whats-new).
- `CURRENT_PROJECT_VERSION` is the build number. **App Store Connect requires the build
  number to be unique and strictly increasing for a given marketing version**, so a
  resubmission of the same `0.1.0` (e.g. to fix a rejected binary) must bump
  `CURRENT_PROJECT_VERSION` even though the marketing version is unchanged.
- Both live in `project.yml` (the source of truth) and flow into the `Info.plist` through
  build-setting expansion, so the DMG and an App Store archive always carry identical
  version strings.

### Signing identity (App Store vs. direct download)

The App Store and direct-download channels deliberately differ in signing identity,
updates, and network capabilities. The direct-download DMG bundles Sparkle and signs
with a superset entitlements file (`Vitrine.DirectDownload.entitlements`) that adds
outbound network access and Sparkle's XPC exceptions, while the **App Store build
excludes Sparkle and stays network-free** (see
[`docs/PERMISSIONS.md`](PERMISSIONS.md#distribution-channels--app-store-vs-direct-download) and
[Auto-update — App Store excludes Sparkle](#auto-update--app-store-excludes-sparkle)).

| | Direct-download DMG | Mac App Store |
| --- | --- | --- |
| Signing identity | **Developer ID Application** (+ notarization, stapling) | **Apple Distribution** / "3rd Party Mac Developer" (App Store provisioning profile) |
| Distribution | Signed, notarized DMG attached to a GitHub release; Homebrew cask | App Store Connect submission |
| Trust check | Gatekeeper (`spctl`) validates the notarized, stapled artifact offline | App Review + the App Store delivery pipeline |
| Auto-update | **Sparkle** (signed EdDSA appcast) | **Excluded** — the App Store updates the app |
| `DEVELOPMENT_TEAM` | Set from `MACOS_NOTARY_TEAM_ID` for signing | The same Team ID, supplied to the App Store archive/export |

### Auto-update — App Store excludes Sparkle

The direct-download build updates itself with [Sparkle](https://sparkle-project.org); the
**Mac App Store build excludes Sparkle entirely**, because the App Store provides its own
update mechanism and a third-party updater is not permitted there. The exclusion is enforced,
not just intended:

- The App Store archive builds with `SWIFT_ACTIVE_COMPILATION_CONDITIONS` overridden to remove
  `VITRINE_DIRECT_DOWNLOAD`, so every `#if VITRINE_DIRECT_DOWNLOAD` block (the whole Sparkle
  integration and the **Check for Updates…** menu item) compiles out — `SoftwareUpdater.isSupported`
  is `false`.
- Because `project.yml` declares the checksum-pinned local framework as a link dependency, a clean
  runner stages it before linking; this is a build input only and does not change the channel.
- The archive then **strips the Sparkle framework** from the app bundle and fails the job if any
  Sparkle payload remains (see `.github/workflows/appstore.yml`).
- The App Store build keeps the minimal `Vitrine.entitlements` (no network, no Sparkle XPC
  exceptions), so the documented "no network" App Store posture is unchanged.

The full direct-download update flow (EdDSA keys, the signed appcast, publishing it per release,
and testing an update from N to N+1) is documented in
[`docs/RELEASING.md`](RELEASING.md#auto-update-sparkle).

`project.yml` keeps `DEVELOPMENT_TEAM` empty and `CODE_SIGN_STYLE: Automatic` by default so
the repo builds and tests without an Apple account; a real submission supplies the Team ID
and the App Store provisioning profile at archive/export time (manually in Xcode Organizer
or via the `ExportOptions.plist` `method: app-store-connect` flow described below). No account
credentials are committed.

### Embedded CLI — App Store archive must address it

The app bundle embeds the `vitrine` command-line renderer at
`Contents/MacOS/vitrine-cli` (for the Homebrew cask's `binary` stanza). App Store
review requires **every** executable in the bundle to opt into the App Sandbox.
The App Store workflow strips `Contents/MacOS/vitrine-cli` before distribution export,
because an App Store install has no PATH integration and the CLI adds no value
there. The CLI target also uses `SKIP_INSTALL=YES`: it remains available for the
app's embed phase without becoming a second top-level archive product, which
would make Xcode classify the result as a generic, non-distributable archive.
The DMG channel is unaffected.

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
| `com.apple.security.network.client` | **Absent.** | The current App Store channel is network-free; URL capture and remote image import remain direct-download capabilities. |
| Screen Recording (TCC) | **Absent by product design.** | Vitrine imports user-captured images instead. No `NSScreenCaptureUsageDescription` and no capture API ship. |

The only declared `Info.plist` usage string is `NSPasteboardUsageDescription` (clipboard),
which is the core feature: Vitrine turns the code (or, in web capture, the URL) you copied into
an image. `Tests/PrivacyManifestTests.swift` asserts this is the **only** usage string and
that no broader file entitlement, network entitlement, or Screen Recording entitlement is
present.

### App Store builds request no network

The network client entitlement is **absent** from App Store builds. `NetworkCapability`
reads the entitlement at runtime and refuses any remote URL capture while it is absent,
so an App Store build **provably cannot reach the
network**. The App Store privacy posture is therefore "no network, no data collected".

The direct-download channel can capture a copied **URL** by loading the requested webpage
**locally in WebKit on this Mac** (`WKWebView`) and rasterizing it on-device, with no remote
screenshot service. `NetworkCapability` and a first-use disclosure keep that
network-backed behavior unavailable in the App Store channel. The channel distinction is
enforced by `Tests/PrivacyManifestTests.swift` and documented in
[`docs/PERMISSIONS.md`](PERMISSIONS.md).

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

Direct-download URL capture does **not** change these labels. The
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

3. **Xcode command line (supported automation path).** Use `xcodebuild -exportArchive`
   with `method: app-store-connect` and `destination: export` for a no-upload distribution
   preflight, or change the destination to `upload` for delivery. Authenticate with
   `-authenticationKeyPath`, `-authenticationKeyID`, and
   `-authenticationKeyIssuerID`; no legacy `altool` step is required.

   A minimal dry-run `ExportOptions.plist` uses:

   ```xml
   <plist version="1.0"><dict>
     <key>method</key><string>app-store-connect</string>
     <key>destination</key><string>export</string>
     <key>teamID</key><string>YOUR_TEAM_ID</string>
     <key>signingStyle</key><string>automatic</string>
   </dict></plist>
   ```

   Run the export with `-allowProvisioningUpdates` and the App Store Connect
   authentication-key arguments. Xcode 26 requires `destination: upload` for its
   `validation` method, so the no-upload CI preflight deliberately uses a local App Store
   Connect export instead. To deliver later, change the destination to `upload` and use
   the same authenticated `xcodebuild -exportArchive` command.

The optional [`.github/workflows/appstore.yml`](../.github/workflows/appstore.yml) is a
**manually-triggered dry run** of the archive + local App Store export steps, gated on the same App
Store Connect API-key secrets and the `APPSTORE_CLOUD_SIGNING_ENABLED=true` repository variable.
It never auto-submits. Once cloud signing, the distribution certificate, and the provisioning
profile are ready, the opt-in creates an automatically signed archive before export; otherwise it
builds an unsigned structural archive and skips distribution export cleanly. See "CI dry run"
below.

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
> **No network in this build.** This App Store build requests **no network entitlement**
> and cannot reach the network. URL capture and remote image import are available only in
> the direct-download channel; normal rendering remains entirely on-device in both channels.
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
- [ ] Entitlements match the documented App Store-compatible set and the permission matrix.
- [ ] App icon up to date (`make icon`).
- [ ] Archived on the `Vitrine` scheme; **Validate App** passes in Xcode Organizer (or the
      no-upload App Store distribution export succeeds).
- [ ] App Store privacy labels in App Store Connect set to **Data Not Collected**, matching
      `PrivacyInfo.xcprivacy`.
- [ ] App Review notes (above) pasted into App Store Connect.
- [ ] Uploaded to TestFlight via Organizer, Transporter, or authenticated `xcodebuild` and the build
      appears in App Store Connect.

## CI dry run (optional, no account required)

[`.github/workflows/appstore.yml`](../.github/workflows/appstore.yml) is a
`workflow_dispatch`-only job that archives the app and runs an **App Store distribution export as a
dry run** when the App Store Connect API-key secrets (`MACOS_NOTARY_KEY_ID`,
`MACOS_NOTARY_KEY_ISSUER_ID`, `MACOS_NOTARY_KEY_P8`) are configured **and** the repository variable
`APPSTORE_CLOUD_SIGNING_ENABLED` is exactly `true`. It **never auto-submits or auto-uploads** a
build. The explicit opt-in must only be enabled after the App Store distribution certificate,
provisioning profile, and cloud-signing permissions are ready; notarization credentials by
themselves are insufficient. When export access is not ready, an unsigned structural archive still
builds and the distribution-export step is skipped, so the workflow stays green. Once enabled, any
signing or export failure remains a hard failure instead of being hidden.
