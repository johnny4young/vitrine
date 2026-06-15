# Vitrine PRO — Monetization Architecture (CS-088 … CS-094)

A guide to the open-core PRO subsystem for anyone working on it. The governing principle:
**the entitlement gate lives at the edges (UI actions, CLI, Shortcuts, Services) and never
touches the render core (`ExportManager`, `SnapshotCanvas`) or the golden suite.** Every
shipped feature produces the same pixels with or without a license; PRO only adds *new*
output and unlocks *new* surfaces.

## Map

| Concern | Files |
| --- | --- |
| Entitlement state | `Vitrine/Pro/Entitlements.swift` — `Entitlements` (`@MainActor ObservableObject`, `isPro`), `ProFeature`, `EntitlementProvider`, `FreeProvider`, `#if DEBUG DebugUnlockProvider` |
| App Store provider | `Vitrine/Pro/StoreKitProvider.swift` — non-consumable IAP `com.johnny4young.vitrine.pro` |
| Direct-download provider | `Vitrine/Pro/LicenseKey.swift` — Ed25519 `LicenseToken`/`LicenseVerifier`/`LicenseSigner`, `#if VITRINE_DIRECT_DOWNLOAD LicenseKeyProvider` |
| CLI entitlement (out-of-process) | `Vitrine/CLI/CLIEntitlement.swift` — offline token verify + Debug bypass |
| Gating UI | `Vitrine/Pro/ProGate.swift` — `View.proGated(_:action:)`, `ProBadge`, `PaywallSheet` |
| Feature: Brand Kit | `Vitrine/Pro/BrandKit.swift` (`BrandKit`, `@MainActor BrandKitStore`), `Vitrine/Models/SnapshotConfig.swift` (`Watermark`), `Vitrine/Canvas/WatermarkBadge.swift` |
| Feature: multi-size export | `Vitrine/Export/ExportManager.swift` (`exportPresetSizes`), `Vitrine/Export/MultiSizeExportView.swift` |
| Feature: automation gating | `VitrineCLI/main.swift`, `Vitrine/AppIntents/RenderCodeImageIntent.swift`, `Vitrine/Services/CodeImageService.swift`, `Vitrine/CLI/CLIRenderer.swift` (`runBatch`) |
| Tests | `Tests/EntitlementsTests.swift`, `Tests/BrandKitTests.swift`, `Tests/MultiSizeExportTests.swift`, `Tests/CLIAutomationTests.swift` |

## Entitlement resolution

`Entitlements.shared` is a `@MainActor ObservableObject`; `isPro` is seeded synchronously from
the active provider's `cachedIsPro` at boot (no flicker, no network) and updated by `refresh()`.
The provider is chosen per build in `defaultProvider()`:

```
#if DEBUG && VITRINE_PRO_UNLOCK==1  → DebugUnlockProvider   (local QA only; see "Local unlock")
#if VITRINE_DIRECT_DOWNLOAD         → LicenseKeyProvider     (DMG: offline Ed25519 token)
#else                               → StoreKitProvider       (App Store: non-consumable IAP)
```

`ProFeature` (`brandKit`, `multiSizeExport`, `automation`) carries its own paywall copy.
`isUnlocked(_:)` follows `isPro` as a single v1 tier — the per-feature signature keeps call
sites honest and leaves room for finer gating later.

## The direct-download license model (offline, honor-based)

`LicenseSigner.sign` runs **server-side only** (the Ed25519 private key never ships). The app
embeds the matching public key in `LicenseVerifier.embedded` and verifies the stored token
**offline** at every launch (`LicenseKeyProvider.cachedIsPro = storedValidToken != nil`).
Tamper / wrong-key / malformed tokens all fail closed. The CLI is a separate process, so it
re-verifies the same token itself via `CLIEntitlement` (no StoreKit↔CLI bridge, no App Group) —
this is why `LicenseVerifier` is compiled unconditionally while `LicenseKeyProvider` is
`#if VITRINE_DIRECT_DOWNLOAD`.

## The export seam — how Brand Kit reaches output without touching the core

`Watermark` is a small, self-contained value (text + resolved logo bytes + tint + placement) so
`SnapshotConfig` stays `Equatable` and `SnapshotCanvas` draws it deterministically with no store
dependency. `SnapshotConfig.watermark` defaults `nil`; `WatermarkOverlay` (in `WatermarkBadge.swift`)
returns its content **unchanged** when nil — so the default render and every golden are
byte-for-byte identical.

The watermark is *derived presentation*, never part of the saved style. It is injected only at
the single seam `AppSettings.exportConfig`:

```swift
var exportConfig: SnapshotConfig {
    var resolved = config
    resolved.watermark = BrandKitStore.shared.resolvedWatermark(isPro: Entitlements.shared.isPro)
    return resolved
}
```

`BrandKitStore.resolvedWatermark(isPro:)` is the only gate that turns a kit into a mark — it
returns `nil` unless `isEnabled && isPro && hasContent`. **Every image export surface renders
`exportConfig`, not the stored `config`** (editor save/copy/share/data-URI, QuickCapture's export
path, Shortcuts, Services). The stored `config` is never watermarked, so persistence, the
"diverged from preset" bookkeeping, per-window sessions (CS-053), and the golden suite are all
unaffected. *(Known follow-up in AUDIT.md P0-2: the File-menu commands still render `config` and
should move to `exportConfig` for parity with the toolbar.)*

## Gating UI

`ProGate.swift` provides `someLabel.proGated(.feature) { action }` — runs `action` when unlocked,
otherwise presents `PaywallSheet` and shows a discreet `ProBadge`. It is **non-nagging**: the
paywall appears only on a tap of a gated action, never on launch. Settings panes that hold many
controls (the Brand Kit sub-tab) use an explicit locked→upsell / unlocked→controls split instead
of the modifier. `PaywallSheet` reads its copy from the `ProFeature` and shows the per-build
unlock path (StoreKit buy + Restore, or a license-key field).

## Automation gating (CS-094)

In-process surfaces gate on `Entitlements.shared.isUnlocked(.automation)`:
`RenderCodeImageIntent.perform()` (→ `IntentRenderError`), `CodeImageService.process()`
(→ `.failed`, injectable for tests). The CLI is out-of-process: `main.swift` gates at the
boundary via `CLIEntitlement.isProUnlocked()` (which verifies the signed token and honors the
Debug bypass) before dispatching `render`/`batch`, so `CLIRenderer.run`/`runBatch` stay ungated
and fully testable. `vitrine batch <dir> --out <dir>` fans the per-file render over a folder.

## Build flags & local unlock

`VITRINE_DIRECT_DOWNLOAD` (project base) ships in the DMG and is stripped from the App Store
build. `DEBUG` is defined **only** in the Debug configuration (`project.yml` per-config settings:
app Debug = `VITRINE_DIRECT_DOWNLOAD DEBUG`, CLI Debug = `DEBUG`, Release = no `DEBUG`). A
config-level `SWIFT_ACTIVE_COMPILATION_CONDITIONS` *replaces* the base (even with `$(inherited)`),
so the Debug values are spelled out in full.

**Local unlock for QA:** launch with `VITRINE_PRO_UNLOCK=1` (app and CLI). It selects
`DebugUnlockProvider` / the CLI bypass, both wrapped in `#if DEBUG` and therefore physically
absent from any Release binary. `EntitlementsTests.debugUnlockProviderIsCompiledOutOfRelease`
and `CLIAutomationTests.theEnvBypassIsCompiledOutOfRelease` source-scan guardrail that the unlock
can never ship.

## Deferred until accounts exist (the only non-code blockers)

Built and tested against fakes/test-keys today; wire the real integrations last:

- **Lemon Squeezy** activation → signed token (`Entitlements.activate(licenseKey:)` /
  `LicenseKeyProvider.setToken` TODOs).
- **App Store Connect** non-consumable IAP product + a `.storekit` config for the live flow.
- **Real Ed25519 keypair** embedded into `LicenseVerifier.embedded` (currently a per-launch random
  placeholder → free by default; replace with a fixed public-key literal before the first PRO
  release, and add a CI assertion it is not random — see AUDIT.md P1-Security-6).
- **CLI token file write** by the app on activation + finalize the shared path under sandboxing
  (AUDIT.md notes the Keychain recommendation for the token store).
- **StoreKit lifecycle wiring** at launch (`refresh()` + `startObservingUpdates`) and
  `transaction.finish()` — see AUDIT.md P0-1.

## Invariants to preserve

1. Never resolve a watermark, read entitlements, or gate inside `ExportManager`/`SnapshotCanvas`
   or any golden-test path — only at edges and the `exportConfig` seam.
2. New PRO visuals are additive + default-off on `SnapshotConfig` (like `annotations`/`metadata`)
   so goldens stay byte-identical.
3. Any local unlock stays `#if DEBUG` with a source-scan guardrail test.
4. The CLI verifies tokens itself; it must never depend on `Entitlements.shared` (which resolves
   via StoreKit in a CLI process).
