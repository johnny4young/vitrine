import CoreGraphics
import Testing

@testable import Vitrine

// MARK: - Applying a preset through AppSettings

@MainActor
@Suite("AppSettings style preset application")
struct AppSettingsStylePresetTests {
    @Test func surpriseCyclesBuiltInsAndStartsCustomStylesAtSunset() {
        for (index, current) in StylePreset.builtIns.enumerated() {
            var config = SnapshotConfig()
            current.style.apply(to: &config)

            let expected = StylePreset.builtIns[(index + 1) % StylePreset.builtIns.count]
            #expect(StylePreset.surprise(after: config).id == expected.id)
        }

        var custom = SnapshotConfig()
        custom.theme = .nord
        custom.background = .gradient(.forest)
        #expect(StylePreset.surprise(after: custom).id == StylePreset.sunset.id)
    }

    @Test func surpriseChangesOnlyPresentationAndReportsTheAppliedStyle() {
        let settings = AppSettings(defaults: PresetTestFixtures.freshDefaults())
        settings.config.code = "let mySecret = 1"
        settings.config.language = .python
        settings.config.metadata = SnapshotMetadata(filename: "main.py", title: "Demo")
        settings.config.highlightedLineRanges = [1...1]
        settings.config.redactedLineRanges = [2...2]
        settings.config.annotations = [
            Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 1, y: 1))
        ]
        let original = settings.config

        let applied = settings.applySurpriseStyle()

        #expect(applied.id == StylePreset.sunset.id)
        #expect(settings.config.code == original.code)
        #expect(settings.config.language == original.language)
        #expect(settings.config.metadata == original.metadata)
        #expect(settings.config.highlightedLineRanges == original.highlightedLineRanges)
        #expect(settings.config.redactedLineRanges == original.redactedLineRanges)
        #expect(settings.config.annotations == original.annotations)
        #expect(settings.config.theme.id == StylePreset.sunset.style.themeID)
        #expect(settings.config.background == StylePreset.sunset.style.background)
    }

    @Test func applyStylePresetWritesPresentationOnlyNeverCode() {
        let settings = AppSettings(defaults: PresetTestFixtures.freshDefaults())
        settings.config.code = "let mySecret = 1"
        settings.config.language = .python
        let originalCode = settings.config.code
        let originalLanguage = settings.config.language

        settings.applyStylePreset(.midnight)

        #expect(settings.config.code == originalCode)
        #expect(settings.config.language == originalLanguage)
        #expect(settings.config.theme.id == StylePreset.midnight.style.themeID)
        #expect(settings.config.background == StylePreset.midnight.style.background)
    }

    @Test func applyStylePresetRestoresAnExistingCustomTheme() throws {
        let defaults = PresetTestFixtures.freshDefaults()
        let settings = AppSettings(defaults: defaults)
        let themes = CustomThemeStore(defaults: defaults)
        let customTheme = themes.addTheme(
            named: "Studio",
            palette: ThemePalette(
                background: try #require(HexColor("#101820")),
                foreground: try #require(HexColor("#F2AA4C"))
            )
        )
        var source = settings.config
        source.theme = customTheme
        let preset = StylePreset.capturing(source, name: "Studio")

        settings.config.theme = .oneDark
        settings.applyStylePreset(preset, themes: themes)

        #expect(settings.config.theme.id == customTheme.id)
        #expect(settings.config.theme.palette == customTheme.palette)
    }

    @Test func applyStylePresetFallsBackWhenACustomThemeNoLongerExists() {
        let defaults = PresetTestFixtures.freshDefaults()
        let settings = AppSettings(defaults: defaults)
        let themes = CustomThemeStore(defaults: defaults)
        let preset = StylePreset(
            name: "Missing",
            style: StyleSnapshot(
                themeID: "custom.missing",
                background: .gradient(.aurora)
            )
        )

        settings.config.theme = .dracula
        settings.applyStylePreset(preset, themes: themes)

        #expect(settings.config.theme == .oneDark)
    }

    @Test func stylePresetCapturesAndAppliesWrapColumns() {
        var source = SnapshotConfig()
        source.wrapColumns = 96
        let preset = StylePreset.capturing(source, name: "Wrapped")

        var target = SnapshotConfig()
        target.wrapColumns = nil
        preset.style.apply(to: &target)

        #expect(preset.style.wrapColumns == 96)
        #expect(target.wrapColumns == 96)
    }

    @Test func appliedStyleDivergesFromAndDropsADestinationPreset() {
        // A style preset is independent of a destination preset; applying
        // one that changes a presentation field naturally drops the destination
        // selection to "Custom" through the existing divergence check.
        let settings = AppSettings(defaults: PresetTestFixtures.freshDefaults())
        settings.selectPreset(.openGraph)  // padding 56, aurora
        #expect(settings.selectedPresetID == "opengraph")

        settings.applyStylePreset(.minimal)  // padding 32, solid white, no shadow

        #expect(settings.selectedPresetID == nil)
        #expect(settings.config.background == .solid(RGBAColor(.white)))
    }
}
