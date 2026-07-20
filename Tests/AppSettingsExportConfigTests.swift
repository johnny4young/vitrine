import Foundation
import Testing

@testable import Vitrine

// `AppSettings.exportConfig` resolves the Brand Kit watermark from injected
// dependencies (the shared instances by default) rather than reaching for the app-global
// singletons, so the export-config derivation is unit-testable. Previously it hard-wired
// `BrandKitStore.shared`/`Entitlements.shared`, which no test could vary.

@MainActor
@Suite("AppSettings.exportConfig uses the injected Brand Kit and entitlement")
struct AppSettingsExportConfigTests {
    /// An entitlement provider pinned to PRO, so the test doesn't depend on the build's
    /// real StoreKit/license state.
    private struct ProProvider: EntitlementProvider {
        var cachedIsPro: Bool { true }
        func currentIsPro() async -> Bool { true }
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "VitrineExportConfig-\(UUID().uuidString)")!
    }

    private func brandKit(enabled: Bool) -> BrandKitStore {
        let store = BrandKitStore(defaults: defaults())
        store.isEnabled = enabled
        store.brandKit = BrandKit(handle: "@jane")
        return store
    }

    @Test func carriesTheWatermarkWhenProAndEnabled() {
        let settings = AppSettings(
            defaults: defaults(),
            brandKit: brandKit(enabled: true),
            entitlements: Entitlements(provider: ProProvider()))
        settings.config.code = "let x = 1"

        // The stored config stays watermark-free; the mark lives only on the derived value.
        #expect(settings.config.watermark == nil)
        #expect(settings.exportConfig.watermark != nil)
    }

    @Test func noWatermarkWhenEntitlementIsFree() {
        let settings = AppSettings(
            defaults: defaults(),
            brandKit: brandKit(enabled: true),
            entitlements: Entitlements(provider: FreeProvider()))
        #expect(settings.exportConfig.watermark == nil)
    }

    @Test func noWatermarkWhenBrandKitIsDisabled() {
        let settings = AppSettings(
            defaults: defaults(),
            brandKit: brandKit(enabled: false),
            entitlements: Entitlements(provider: ProProvider()))
        #expect(settings.exportConfig.watermark == nil)
    }
}
