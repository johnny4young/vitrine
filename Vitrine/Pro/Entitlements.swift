import Foundation
import Observation

/// The single source of truth for Vitrine PRO state, the open-core monetization
/// gate. The gate lives at the **edges** (UI actions, CLI/Shortcuts entry points) and
/// never touches the render core (`ExportManager`, `SnapshotCanvas`) or the golden suite,
/// so every shipped feature keeps producing the same output with or without a license.
///
/// PRO state is provider-backed and **offline**: the boot path reads the provider's cached
/// flag instantly (no flicker, no network), and `refresh()` updates it asynchronously. The
/// provider is injectable (the same pattern as `PresetStore` / `SoftwareUpdater`), so the
/// StoreKit (App Store) and license-key (direct-download) providers live behind the same
/// interface without changing call sites, and tests drive a fake.
///
/// `WKWebView`-free and network-free by itself: nothing here logs or transmits anything
/// about purchases; the privacy rule extends to entitlement checks.
@MainActor
@Observable
final class Entitlements {
    /// The app-wide entitlement state, constructed by the composition root
    /// (``AppEnvironment``) and reached here as a thin forwarder so existing call sites and
    /// the non-view action layer are unchanged.
    static var shared: Entitlements { AppEnvironment.shared.entitlements }

    /// Whether the PRO tier is unlocked. Published so SwiftUI surfaces (the "PRO" badge,
    /// the paywall gate) update the moment it changes. Private setter: only a provider
    /// refresh moves it.
    private(set) var isPro: Bool

    private let provider: EntitlementProvider

    /// Seeds `isPro` from the provider's cached flag — instant and offline, so the first
    /// frame already reflects the last known state with no flash.
    init(provider: EntitlementProvider) {
        self.provider = provider
        self.isPro = provider.cachedIsPro
    }

    /// Whether `feature` is available. PRO unlocks as a single tier in v1, so every
    /// feature follows `isPro`; the per-feature signature keeps call sites honest and
    /// leaves room for finer gating later without churn.
    func isUnlocked(_ feature: ProFeature) -> Bool { isPro }

    /// Re-resolves the live entitlement from the provider (e.g. after a purchase, a
    /// restore, or a periodic re-validation) and publishes any change.
    func refresh() async {
        let current = await provider.currentIsPro()
        if current != isPro { isPro = current }
    }

    /// Begins live entitlement updates: re-resolves the entitlement now, and on the
    /// App Store build observes out-of-band `Transaction.updates` — a refund (revokes the
    /// transaction → `isPro` flips to `false`) or a purchase on another device — so PRO
    /// re-locks/unlocks without a relaunch. Call once at launch. Idempotent enough for the
    /// app-lifetime shared instance; the observation task is owned by the provider.
    func startLiveUpdates() {
        #if !VITRINE_DIRECT_DOWNLOAD
            (provider as? StoreKitProvider)?.startObservingUpdates {
                Task { await Entitlements.shared.refresh() }
            }
        #endif
        Task { await refresh() }
    }

    /// Starts a PRO purchase and reports the outcome (so the paywall can surface a failure
    /// instead of silently clearing), refreshing after. Delegates to the active provider —
    /// the StoreKit provider buys; the license-key/free/debug providers no-op.
    @discardableResult
    func purchase() async -> PurchaseOutcome {
        let outcome = await provider.purchase()
        await refresh()
        return outcome
    }

    /// Restore Purchases (an App Store requirement): asks the provider to restore, then
    /// refreshes so a prior purchase re-grants on a clean install. A no-op for providers
    /// without a purchase flow.
    func restorePurchases() async {
        _ = await provider.restore()
        await refresh()
    }

    #if VITRINE_DIRECT_DOWNLOAD
        /// Activates a Lemon Squeezy license key on the direct-download build (
        /// embedded-key activation model), returning whether PRO is unlocked afterward.
        ///
        /// Validates the key once online via `LicenseActivationService`, which on success mints
        /// a locally-signed token; that token is handed to the `LicenseKeyProvider`, which
        /// persists it to the Keychain and mirrors it to the CLI file, and a `refresh()`
        /// publishes the unlock. A build without the injected signing key cannot mint a token,
        /// so it reports `notConfigured` and stays free (the open-source / pre-key state).
        func activate(licenseKey: String) async -> Bool {
            let service = LicenseActivationService(
                validator: LemonSqueezyValidator(), signingKey: LicenseSigningKey.embedded)
            if case .activated(let signedToken) = await service.activate(licenseKey: licenseKey) {
                (provider as? LicenseKeyProvider)?.setToken(signedToken)
            }
            await refresh()
            return isPro
        }
    #endif

    /// The provider backing `shared`, chosen per build. The App Store build resolves PRO
    /// from the StoreKit non-consumable IAP; the direct-download build resolves
    /// from a locally stored signed license token and is free until activation
    /// succeeds. In a **Debug** build only, `VITRINE_PRO_UNLOCK=1` swaps in
    /// `DebugUnlockProvider` so PRO can be exercised locally — that override is compiled
    /// out of release, so a shipped binary has no path to PRO through it.
    static func defaultProvider() -> EntitlementProvider {
        #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if environment["VITRINE_PRO_UNLOCK"] == "1" {
                return DebugUnlockProvider()
            }
            // The app host for unit/UI tests must not touch the developer's real Keychain
            // or StoreKit account at launch. Tests that need PRO inject their own provider;
            // the shared app singleton stays deterministically locked.
            if environment["XCTestConfigurationFilePath"] != nil
                || environment["VITRINE_USER_DEFAULTS_SUITE"] != nil
            {
                return FreeProvider()
            }
        #endif
        #if VITRINE_DIRECT_DOWNLOAD
            // Direct-download build: PRO resolves from a locally-stored, signed license
            // token, verified offline. Free until a token is activated.
            return LicenseKeyProvider()
        #else
            // App Store build: PRO resolves from the StoreKit non-consumable IAP.
            return StoreKitProvider()
        #endif
    }
}

/// A gated PRO capability. Each case carries its own paywall copy so the
/// `PaywallSheet` reads its title and blurb straight from the feature the user
/// tried to use.
enum ProFeature: String, CaseIterable, Sendable {
    /// User logo + handle + accent color + watermark applied in one click.
    case brandKit
    /// One capture exported to many platform sizes in a single pass.
    case multiSizeExport
    /// A long snippet split into numbered 4:5 slides for a carousel post.
    /// Unlocks with the same tier as everything else; a distinct case so the paywall
    /// describes the feature the user actually tapped.
    case carouselExport
    /// The `vitrine` CLI, Shortcuts, and folder batch rendering.
    case automation
    /// The richer browser and device frames for beautified images. The plain image
    /// and macOS window frame stay free.
    case advancedFrames

    /// The paywall headline for this feature.
    var paywallTitle: String {
        switch self {
        case .brandKit: String(localized: "Brand Kit")
        case .multiSizeExport: String(localized: "Multi-size export")
        case .carouselExport: String(localized: "Carousel export")
        case .automation: String(localized: "Automation")
        case .advancedFrames: String(localized: "Image frames")
        }
    }

    /// The one-line paywall description of what the feature adds.
    var paywallBlurb: String {
        switch self {
        case .brandKit:
            String(localized: "Add your logo, handle, and accent color to every snapshot.")
        case .multiSizeExport:
            String(localized: "Export one capture to every platform size in a single pass.")
        case .carouselExport:
            String(localized: "Split a long snippet into numbered slides for a carousel post.")
        case .automation:
            String(
                localized: "Unlock the vitrine command line, Shortcuts, and folder batch rendering."
            )
        case .advancedFrames:
            String(localized: "Frame screenshots in a browser window and more.")
        }
    }
}

/// Resolves the current PRO entitlement for a build. Implementations are the
/// real StoreKit and license-key providers, plus the free default and
/// the test/dev fakes. `cachedIsPro` must be a synchronous, offline read (used at boot);
/// `currentIsPro()` may do async work (a StoreKit query, a token re-check).
protocol EntitlementProvider {
    /// The last known PRO state, readable instantly and offline at launch.
    var cachedIsPro: Bool { get }
    /// The freshly-resolved PRO state, awaited on a refresh.
    func currentIsPro() async -> Bool
    /// Starts a purchase (the App Store IAP). Providers without a purchase flow no-op.
    func purchase() async -> PurchaseOutcome
    /// Restores prior purchases (the App Store requirement). Providers without one no-op.
    func restore() async -> Bool
}

extension EntitlementProvider {
    /// Default no-ops, so only the StoreKit provider implements a real purchase/restore and
    /// `Entitlements` need not downcast to it.
    func purchase() async -> PurchaseOutcome { .cancelled }
    func restore() async -> Bool { cachedIsPro }
}

/// The always-free provider used by tests, unsupported build flavors, and providers without
/// a purchase/license flow.
struct FreeProvider: EntitlementProvider {
    var cachedIsPro: Bool { false }
    func currentIsPro() async -> Bool { false }
}

#if DEBUG
    /// A Debug-only local unlock: PRO is always on. Compiled **only** into Debug
    /// builds (`#if DEBUG`), so it is physically absent from any release binary — the
    /// "bypass locally, never in releases" guarantee. Activated via `VITRINE_PRO_UNLOCK=1`
    /// in `Entitlements.defaultProvider()`. Tests inject their own fake instead of this.
    struct DebugUnlockProvider: EntitlementProvider {
        var cachedIsPro: Bool { true }
        func currentIsPro() async -> Bool { true }
    }
#endif
