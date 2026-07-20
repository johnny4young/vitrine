import CoreGraphics
import Foundation
import Testing

@testable import Vitrine

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "VitrinePresetTests-\(UUID().uuidString)")!
}

// MARK: - Catalog

@Suite("ExportPreset catalog")
struct ExportPresetCatalogTests {
    @Test func catalogCoversEverySocialSurface() {
        // The supported set contains six core destinations; image-input added two more (Instagram
        // Story and the GitHub README banner). Each must be present with a stable id.
        let ids = Set(ExportPreset.all.map(\.id))
        #expect(
            ids == [
                "twitter", "linkedin", "keynote", "docs", "transparent-slide", "opengraph",
                "instagram-story", "github-banner",
            ])
    }

    @Test func idsAreUnique() {
        let ids = ExportPreset.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyPresetIsNamedAndDescribed() {
        for preset in ExportPreset.all {
            #expect(!preset.displayName.isEmpty)
            #expect(!preset.summary.isEmpty)
        }
    }

    @Test func everyPresetDeclaresUsableScaleAndSizing() {
        for preset in ExportPreset.all {
            // Scale stays within the supported export range.
            #expect(SettingsDefaults.exportScaleRange.contains(preset.scale))
            // Every sizing carries positive dimensions, so the aspect ratio is finite.
            #expect(preset.sizing.aspectRatio > 0)
            #expect(preset.sizing.aspectRatio.isFinite)
        }
    }

    @Test func lookupResolvesKnownIDsAndRejectsUnknownOrNil() {
        #expect(ExportPreset.preset(withID: "opengraph")?.id == "opengraph")
        #expect(ExportPreset.preset(withID: "twitter") == ExportPreset.twitter)
        #expect(ExportPreset.preset(withID: "does-not-exist") == nil)
        #expect(ExportPreset.preset(withID: nil) == nil)
    }

    @Test func openGraphPinsExactSizeAtOneScale() {
        let openGraph = ExportPreset.openGraph
        #expect(openGraph.scale == 1)
        #expect(openGraph.sizing.fixedSize == CGSize(width: 1200, height: 630))
    }

    @Test func everyDestinationPinsItsExactSize() {
        // Every shipped destination pins a `.fixed` canvas so the export is exactly
        // the shape its name promises — the code card is centered and the
        // background fills the frame.
        let expected: [String: CGSize] = [
            "twitter": CGSize(width: 1600, height: 900),
            "linkedin": CGSize(width: 1200, height: 628),
            "keynote": CGSize(width: 1920, height: 1080),
            "docs": CGSize(width: 1200, height: 800),
            "transparent-slide": CGSize(width: 1920, height: 1080),
            "opengraph": CGSize(width: 1200, height: 630),
            "instagram-story": CGSize(width: 1080, height: 1920),
            "github-banner": CGSize(width: 1280, height: 640),
        ]
        for preset in ExportPreset.all {
            #expect(
                preset.sizing.fixedSize == expected[preset.id],
                "\(preset.id) must pin its exact canvas size")
            // Fixed-size destinations pin scale to 1 so logical and pixel sizes match.
            #expect(preset.scale == 1, "\(preset.id) should export at 1× (logical == pixels)")
        }
    }

    /// The aspect ratio each destination pins matches the shape its name implies.
    @Test func destinationAspectRatiosMatchTheirNames() {
        #expect(abs(ExportPreset.twitter.sizing.aspectRatio - 16.0 / 9.0) < 0.001)
        #expect(abs(ExportPreset.keynote.sizing.aspectRatio - 16.0 / 9.0) < 0.001)
        #expect(abs(ExportPreset.linkedIn.sizing.aspectRatio - 1.91) < 0.01)
        #expect(abs(ExportPreset.docs.sizing.aspectRatio - 3.0 / 2.0) < 0.001)
    }

    @Test func transparentSlidePresetUsesRealTransparency() {
        #expect(ExportPreset.transparentSlide.background == .transparent)
    }
}

// MARK: - Applying a preset to a config

@Suite("ExportPreset apply")
struct ExportPresetApplyTests {
    @Test func applyMutatesOnlyPresentationFieldsNeverCode() {
        var config = SnapshotConfig()
        config.code = "let secret = 42"
        config.language = .python
        let originalCode = config.code
        let originalLanguage = config.language

        ExportPreset.openGraph.apply(to: &config)

        // The user's source is never touched by a preset.
        #expect(config.code == originalCode)
        #expect(config.language == originalLanguage)
        // Presentation fields adopt the preset's guidance.
        #expect(config.padding == SettingsDefaults.clampPadding(ExportPreset.openGraph.padding))
        #expect(config.background == .gradient(.aurora))
    }

    @Test func applyClampsPaddingIntoSupportedRange() {
        // A preset whose padding sits outside the slider range is clamped on apply
        // so a hand-authored preset can never push an out-of-range value into the
        // renderer.
        let wide = ExportPreset(
            id: "wide", displayName: "Wide", summary: "x",
            sizing: .aspect(width: 1, height: 1), scale: 2, background: nil, padding: 999)
        var config = SnapshotConfig()
        wide.apply(to: &config)
        #expect(config.padding == SettingsDefaults.paddingRange.upperBound)
    }

    @Test func applyLeavesBackgroundUntouchedWhenPresetDeclaresNone() {
        var config = SnapshotConfig()
        config.background = .solid(RGBAColor(.black))
        ExportPreset.docs.apply(to: &config)  // docs declares no background
        #expect(config.background == .solid(RGBAColor(.black)))
    }

    @Test func matchesReflectsAppliedState() {
        var config = SnapshotConfig()
        ExportPreset.keynote.apply(to: &config)
        #expect(ExportPreset.keynote.matches(config))
        // A user edit to a presentation field breaks the match.
        config.padding = SettingsDefaults.paddingRange.lowerBound
        #expect(!ExportPreset.keynote.matches(config))
    }
}

// MARK: - Persistence via AppSettings

@MainActor
@Suite("AppSettings destination presets")
struct AppSettingsPresetTests {
    @Test func selectingPresetAppliesGuidanceAndScale() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.selectPreset(.openGraph)

        #expect(settings.selectedPresetID == "opengraph")
        #expect(settings.selectedPreset == .openGraph)
        #expect(settings.export.scale == 1)
        #expect(settings.effectiveExportScale == 1)
        #expect(settings.effectiveFixedSize == CGSize(width: 1200, height: 630))
        #expect(settings.config.background == .gradient(.aurora))
    }

    @Test func lastSelectedPresetPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.selectPreset(.linkedIn)

        let second = AppSettings(defaults: defaults)
        #expect(second.selectedPresetID == "linkedin")
        #expect(second.selectedPreset == .linkedIn)
    }

    @Test func unknownPersistedPresetResolvesToCustom() {
        let defaults = freshDefaults()
        // A preset id written by a future build that this build no longer knows.
        defaults.set("a-future-preset", forKey: "selectedPreset")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.selectedPresetID == nil)
        #expect(settings.selectedPreset == nil)
        // With no preset, the effective values fall back to the user's own.
        #expect(settings.effectiveFixedSize == nil)
        #expect(settings.effectiveExportScale == settings.export.scale)
    }

    @Test func editingStyleAfterSelectingFallsBackToCustom() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.selectPreset(.keynote)
        #expect(settings.selectedPresetID == "keynote")

        // A manual padding change diverges from the preset, so the selection
        // drops to Custom and the picker stays honest.
        settings.config.padding = 20
        #expect(settings.selectedPresetID == nil)
    }

    @Test func clearPresetReturnsToCustomWithoutChangingStyle() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.selectPreset(.twitter)
        let backgroundAfterSelect = settings.config.background

        settings.clearPreset()
        #expect(settings.selectedPresetID == nil)
        // Clearing does not undo the style the preset applied; it only forgets
        // the association.
        #expect(settings.config.background == backgroundAfterSelect)
    }

    @Test func resetClearsSelectedPreset() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.selectPreset(.openGraph)
        settings.resetToDefaults()
        #expect(settings.selectedPresetID == nil)
        #expect(settings.effectiveFixedSize == nil)
        #expect(settings.export.scale == SettingsDefaults.exportScale)
    }

    @Test func overridingScaleAfterSelectingKeepsThePresetAndWins() {
        // "OpenGraph exports 1200×630 at 1× unless overridden": selecting the
        // preset seeds the scale, but the Resolution control stays authoritative.
        let settings = AppSettings(defaults: freshDefaults())
        settings.selectPreset(.openGraph)
        #expect(settings.export.scale == 1)

        settings.export.scale = 3

        // The override wins for the effective scale used by the renderer…
        #expect(settings.effectiveExportScale == 3)
        // …and scale is not a presentation field, so the preset stays selected
        // (only a style edit drops to Custom). The fixed size is still pinned.
        #expect(settings.selectedPresetID == "opengraph")
        #expect(settings.effectiveFixedSize == CGSize(width: 1200, height: 630))
    }

    @Test func selectingPresetClampsAnOutOfRangeRecommendedScale() {
        // A hand-authored preset whose recommended scale sits outside the
        // supported range is clamped on selection, mirroring padding clamping, so
        // an out-of-range value can never reach `exportScale`.
        let oversized = ExportPreset(
            id: "oversized", displayName: "Oversized", summary: "x",
            sizing: .aspect(width: 1, height: 1), scale: 99, background: nil, padding: 32)
        let settings = AppSettings(defaults: freshDefaults())
        settings.selectPreset(oversized)
        #expect(settings.export.scale == SettingsDefaults.exportScaleRange.upperBound)
        #expect(settings.effectiveExportScale == SettingsDefaults.exportScaleRange.upperBound)
    }

    @Test func switchingDirectlyBetweenPresetsAdoptsTheSecondPreset() {
        // Selecting a second preset while one is already active re-applies the
        // new preset's guidance and scale wholesale, without first returning to
        // Custom — the `isApplyingPreset` guard must not leave a stale selection.
        let settings = AppSettings(defaults: freshDefaults())
        settings.selectPreset(.openGraph)  // scale 1, fixed 1200×630, aurora
        #expect(settings.selectedPresetID == "opengraph")

        settings.selectPreset(.keynote)  // scale 1, fixed 1920×1080, night

        #expect(settings.selectedPresetID == "keynote")
        #expect(settings.selectedPreset == .keynote)
        #expect(settings.export.scale == 1)
        #expect(settings.effectiveFixedSize == CGSize(width: 1920, height: 1080))
        #expect(settings.config.background == .gradient(.night))
        #expect(
            settings.config.padding == SettingsDefaults.clampPadding(ExportPreset.keynote.padding))
    }
}

// MARK: - Render dimensions for fixed-size presets

@MainActor
@Suite("ExportPreset render dimensions")
struct ExportPresetRenderTests {
    @Test func openGraphRendersExactly1200x630AtOneScale() throws {
        var config = SnapshotConfig()
        config.code = "let answer = 42"
        ExportPreset.openGraph.apply(to: &config)

        let cgImage = try #require(
            ExportManager.renderCGImage(
                config, scale: 1, fixedSize: ExportPreset.openGraph.sizing.fixedSize))
        // Exactly 1200×630 logical pixels at 1× (no padding/scale drift).
        #expect(cgImage.width == 1200)
        #expect(cgImage.height == 630)
    }

    @Test func openGraphScalesUpExactlyWhenOverridden() throws {
        var config = SnapshotConfig()
        config.code = "print(1)"
        ExportPreset.openGraph.apply(to: &config)

        // "unless overridden": at 2× the same fixed size doubles to 2400×1260.
        let cgImage = try #require(
            ExportManager.renderCGImage(
                config, scale: 2, fixedSize: ExportPreset.openGraph.sizing.fixedSize))
        #expect(cgImage.width == 2400)
        #expect(cgImage.height == 1260)
    }

    @Test func fixedSizeRenderIsIndependentOfCodeLength() throws {
        // The defining property of a fixed-size preset: the image size does not
        // change with the amount of code, unlike a content-hugging render.
        var shortConfig = SnapshotConfig()
        shortConfig.code = "x"
        ExportPreset.openGraph.apply(to: &shortConfig)

        var longConfig = SnapshotConfig()
        longConfig.code = String(repeating: "let value = compute()\n", count: 40)
        ExportPreset.openGraph.apply(to: &longConfig)

        let size = ExportPreset.openGraph.sizing.fixedSize
        let small = try #require(
            ExportManager.renderCGImage(shortConfig, scale: 1, fixedSize: size))
        let large = try #require(ExportManager.renderCGImage(longConfig, scale: 1, fixedSize: size))
        #expect(small.width == large.width)
        #expect(small.height == large.height)
    }

    @Test func contentHuggingRenderStillVariesWithCodeLength() throws {
        // A preset without a fixed size leaves the canvas hugging its content, so
        // a longer snippet still produces a taller image (regression guard that
        // the fixed-size path did not change default rendering).
        var shortConfig = SnapshotConfig()
        shortConfig.code = "x"
        var tallConfig = SnapshotConfig()
        tallConfig.code = String(repeating: "line\n", count: 20)

        let short = try #require(ExportManager.renderCGImage(shortConfig, scale: 1))
        let tall = try #require(ExportManager.renderCGImage(tallConfig, scale: 1))
        #expect(tall.height > short.height)
    }

    @Test func transparentSlidePresetRendersWithAlphaChannel() throws {
        var config = SnapshotConfig()
        config.code = "let x = 1"
        ExportPreset.transparentSlide.apply(to: &config)
        let cgImage = try #require(ExportManager.renderCGImage(config, scale: 1))
        // A transparent background must carry a real alpha channel, not an opaque matte.
        let alpha = cgImage.alphaInfo
        #expect(
            alpha == .premultipliedFirst || alpha == .premultipliedLast || alpha == .first
                || alpha == .last)
    }
}
