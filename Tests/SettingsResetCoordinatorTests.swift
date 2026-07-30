import Foundation
import Testing

@testable import Vitrine

@Suite("Settings reset coordination")
struct SettingsResetCoordinatorTests {
    @Test func resetClearsPersistedAndLiveStoreState() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "VitrineSettingsResetCoordinatorTests-\(UUID().uuidString)")
        )
        let settings = AppSettings(defaults: defaults)
        let presets = PresetStore(defaults: defaults)
        let themes = CustomThemeStore(defaults: defaults)
        let brandKit = BrandKitStore(defaults: defaults)

        settings.treatURLsAsScreenshot = true
        presets.savePreset(named: "Temporary", from: settings.config)
        themes.addTheme(
            named: "Temporary",
            palette: ThemePalette(
                background: try #require(HexColor("#121212")),
                foreground: try #require(HexColor("#F5F5F5"))
            )
        )
        brandKit.brandKit = BrandKit(handle: "@vitrine", project: "Example")
        brandKit.isEnabled = true

        SettingsResetCoordinator(
            settings: settings,
            presets: presets,
            themes: themes,
            brandKit: brandKit
        ).reset()

        #expect(!settings.treatURLsAsScreenshot)
        #expect(settings.config == SnapshotConfig())
        #expect(presets.userPresets.isEmpty)
        #expect(themes.customThemes.isEmpty)
        #expect(brandKit.brandKit == BrandKit())
        #expect(!brandKit.isEnabled)
        #expect(defaults.data(forKey: PresetStore.storageKey) == nil)
        #expect(defaults.data(forKey: CustomThemeStore.storageKey) == nil)
        #expect(defaults.data(forKey: BrandKitStore.storageKey) == nil)
        #expect(defaults.object(forKey: BrandKitStore.enabledStorageKey) == nil)
    }
}
