# Vitrine PRO — Monetization Architecture

A guide to the open-core PRO subsystem for anyone working on it. The governing principle:
**the entitlement gate lives at the edges (UI actions, CLI, Shortcuts, Services) and never
touches the render core (`ExportManager`, `SnapshotCanvas`) or the golden suite.** Every
shipped feature produces the same pixels with or without a license; PRO only adds *new*
output and unlocks *new* surfaces.

## Map

| Concern | Files |
| --- | --- |
| Entitlement state | `Vitrine/Pro/Entitlements.swift` — `Entitlements` (`@MainActor @Observable`, `isPro`), `ProFeature`, `EntitlementProvider`, `FreeProvider`, `#if DEBUG DebugUnlockProvider` |
| App Store provider | `Vitrine/Pro/StoreKitProvider.swift` — non-consumable IAP `com.johnny4young.vitrine.pro` |
| Direct-download provider | `Vitrine/Pro/LicenseKey.swift` — Ed25519 `LicenseToken`/`LicenseVerifier`/`LicenseSigner`, `#if VITRINE_DIRECT_DOWNLOAD LicenseKeyProvider` |
| CLI entitlement (out-of-process) | `Vitrine/CLI/CLIEntitlement.swift` — offline token verify + Debug bypass |
| Gating UI | `Vitrine/Pro/ProGate.swift` — `View.proGated(_:action:)`, `ProBadge`, `PaywallSheet` |
| Feature: Brand Kit | `Vitrine/Pro/BrandKit.swift` (`BrandKit`, `@MainActor BrandKitStore`), `Vitrine/Models/SnapshotConfig.swift` (`Watermark`), `Vitrine/Canvas/WatermarkBadge.swift` |
| Feature: multi-size export | `Vitrine/Export/ExportManager+Batch.swift` (`exportPresetSizes`), `Vitrine/Export/MultiSizeExportView.swift` |
| Feature: carousel export | `Vitrine/Export/ExportManager+Batch.swift` (`exportCarousel`), `Vitrine/Export/CarouselExportView.swift`, `Vitrine/Export/CarouselPaginator.swift` |
| Feature: automation gating | `VitrineCLI/main.swift`, `Vitrine/CLI/CLIOptions.swift` (`Command.requiresPro`), `Vitrine/AppIntents/RenderCodeImageIntent.swift`, `Vitrine/Services/CodeImageService.swift`, `Vitrine/CLI/CLIRenderer.swift` (`runBatch`) |
| Tests | `Tests/EntitlementsTests.swift`, `Tests/BrandKitTests.swift`, `Tests/MultiSizeExportTests.swift`, `Tests/CLIAutomationTests.swift` |

## Entitlement resolution

`Entitlements.shared` is a `@MainActor @Observable` reference; `isPro` is seeded synchronously from
the active provider's `cachedIsPro` at boot (no flicker, no network) and updated by `refresh()`.
The provider is chosen per build in `defaultProvider()`:

```
#if DEBUG && VITRINE_PRO_UNLOCK==1  → DebugUnlockProvider   (local QA only; see "Local unlock")
#if VITRINE_DIRECT_DOWNLOAD         → LicenseKeyProvider     (DMG: offline Ed25519 token)
#else                               → StoreKitProvider       (App Store: non-consumable IAP)
```

`ProFeature` (`brandKit`, `multiSizeExport`, `carouselExport`, `automation`, `advancedFrames`) carries its own paywall copy.
`isUnlocked(_:)` follows `isPro` as a single v1 tier — the per-feature signature keeps call
sites honest and leaves room for finer gating later.

## The direct-download license model (offline, honor-based)

The official direct-download build validates a Lemon Squeezy license key once, confirms that the
response belongs to the source-pinned Vitrine store/product (and is not a test-mode key), then signs the
offline `LicenseToken` **locally** with the build-injected Ed25519 private key
(`LicenseSigningKey.embedded`). This is a deliberate honor/convenience model, not server-side
DRM: the private key is injected only into the signed release binary, never committed, while a
from-source build has no key and cannot mint a token.

The app embeds the matching public key in `LicenseVerifier.embedded` and verifies the stored
token **offline** at every launch (`LicenseKeyProvider.cachedIsPro = storedValidToken != nil`).
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
"diverged from preset" bookkeeping, per-window sessions, and the golden suite are all
unaffected.

## Gating UI

`ProGate.swift` provides `someLabel.proGated(.feature) { action }` — runs `action` when unlocked,
otherwise presents `PaywallSheet` and shows a discreet `ProBadge`. It is **non-nagging**: the
paywall appears only on a tap of a gated action, never on launch. Settings panes that hold many
controls (the Brand Kit sub-tab) use an explicit locked→upsell / unlocked→controls split instead
of the modifier. `PaywallSheet` reads its copy from the `ProFeature` and shows the per-build
unlock path (StoreKit buy + Restore, or a license-key field).

## Automation gating

In-process surfaces gate on `Entitlements.shared.isUnlocked(.automation)`:
`RenderCodeImageIntent.perform()` (→ `IntentRenderError`), `CodeImageService.process()`
(→ `.failed`, injectable for tests). The CLI is out-of-process and applies capability policy
before file I/O. `terminal-capture` is the constrained free operation emitted by `vgrab`: it
forces terminal language, requires clipboard copy or editor handoff, and accepts only terminal
width plus filename/title context. The parser rejects every general style, output, sidecar, and
automation flag on that command. `render`, `multi-size`, and `batch` remain PRO; `main.swift`
calls `CLIEntitlement.isProUnlocked()` for those commands before dispatch, so the unchanged
`CLIRenderer` operations stay ungated and fully testable. `vpane` deliberately uses general
`render` and remains PRO. `vitrine batch <dir> --out <dir>` fans the per-file render over a folder;
`--recursive` opts into nested folders while preserving their relative output paths, and
`--fail-on-skipped` turns any skipped file into a non-zero automation exit after the
readable files are rendered. `--skipped-report <json>` can be paired with either mode
to save a local skipped-files artifact for CI upload.

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

## Release/account status and certification

The direct-download production path is wired: the app and website point at the live Vitrine PRO
checkout, the release workflow injects `VITRINE_LICENSE_SIGNING_KEY`, the runtime pins the public
key plus Lemon Squeezy store/product identifiers, and `scripts/qa-release.sh` rejects a published
artifact whose private signer is missing or malformed. None of those static facts proves that a
real buyer journey succeeded.

Every direct-download release still needs the secret-safe published-artifact procedure in
[`ACTIVATION.md`](ACTIVATION.md) and [`RELEASING.md`](RELEASING.md): online activation with a
dedicated live QA license, offline relaunch, a PRO-only GUI action, the PRO-only CLI `multi-size`
path, and a non-empty mode-`0600` token mirror. Record pass/fail evidence, but never the raw
license key, private signing key, or token contents.

The App Store channel remains separate: its StoreKit non-consumable and real purchase/restore
journey must be certified before that channel is distributed.

**Known direct-download lifecycle boundary:** v1 has no in-app Restore or Deactivate control and
does not retain the Lemon Squeezy `instanceID` after minting the offline token. Upgrades and
offline relaunches preserve the local entitlement; moving to a clean Mac requires activating the
license again. Do not claim remote seat deactivation, periodic refund revocation, or a restore
workflow until those contracts are deliberately designed and tested.

## Invariants to preserve

1. Never resolve a watermark, read entitlements, or gate inside `ExportManager`/`SnapshotCanvas`
   or any golden-test path — only at edges and the `exportConfig` seam.
2. New PRO visuals are additive + default-off on `SnapshotConfig` (like `annotations`/`metadata`)
   so goldens stay byte-identical.
3. Any local unlock stays `#if DEBUG` with a source-scan guardrail test.
4. Advanced CLI commands verify tokens themselves; they must never depend on
   `Entitlements.shared` (which resolves via StoreKit in a CLI process). The free
   `terminal-capture` command must stay constrained by an explicit parser allowlist.
5. A successful provider response is not enough: direct-download activation must match the
   pinned Lemon Squeezy store/product and reject test-mode, foreign, incomplete, or inactive keys.
