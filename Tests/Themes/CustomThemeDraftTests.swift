import SwiftUI
import Testing

@testable import Vitrine

/// The editor's `CustomThemeDraft` is the editable, `Color`-backed form behind both
/// the live preview and the Save action. The editor builds its preview *and* the saved theme from the same
/// `draft.palette()`, so these tests pin the load-bearing guarantee that what the
/// user previews is exactly the palette that gets saved — and that opening an
/// existing theme for editing seeds the wells without drifting its colors.
@Suite("Custom theme editor draft")
struct CustomThemeDraftTests {
    @Test func aNewDraftResolvesToACompleteValidDarkPalette() {
        // The editor opens a new theme on a sensible, fully-populated starting point
        // (not all-black wells), so the very first preview is legible and complete.
        let palette = CustomThemeDraft().palette()
        #expect(palette.appearance == .dark)
        // Every token color is a real, distinct choice rather than collapsing to the
        // foreground fallback, so the seeded preview shows real syntax coloring.
        let tokens = [
            palette.keyword, palette.string, palette.comment, palette.number,
            palette.type, palette.function, palette.variable, palette.attribute,
        ]
        #expect(Set(tokens).count >= 2)
        #expect(tokens.allSatisfy { $0 != palette.foreground })
    }

    @Test func editingDraftRoundTripsAnExistingPaletteWithoutDrift() {
        // Edit seeds each well from `palette.x.color` and `palette()` resolves it back
        // through `Color.hexColor`. This is the documented fixed-sRGB round-trip, so
        // opening a theme and saving it unchanged must yield the identical palette —
        // otherwise Edit would silently corrupt a saved theme's colors.
        let original = ThemeTestFixtures.samplePalette()
        let draft = CustomThemeDraft(
            editingID: "custom.edit", name: "Editable", palette: original)
        #expect(draft.palette() == original)
    }

    @Test func editingDraftPreservesTheEditingIDAndName() {
        let draft = CustomThemeDraft(
            editingID: "custom.keep", name: "Keep", palette: ThemeTestFixtures.samplePalette())
        #expect(draft.editingID == "custom.keep")
        #expect(draft.name == "Keep")
    }

    @Test func aNewDraftHasNoEditingID() {
        // A new draft is in "create" mode, so the editor adds rather than rewrites.
        #expect(CustomThemeDraft().editingID == nil)
    }

    @Test func draftResolvesToTheSamePaletteOnEveryCall() {
        // The editor calls `palette()` once for the preview and again to save; both
        // must agree, so "what you preview is what you save" holds exactly.
        let draft = CustomThemeDraft(
            editingID: "custom.stable", name: "Stable", palette: ThemeTestFixtures.samplePalette())
        #expect(draft.palette() == draft.palette())
    }

    @Test func editingAWellChangesOnlyThatColorInTheResolvedPalette() {
        // Editing a single well in the editor must change exactly that token color and
        // leave the rest of the previewed/saved palette intact.
        let draft = CustomThemeDraft(
            editingID: "custom.edit1", name: "One Edit", palette: ThemeTestFixtures.samplePalette())
        draft.keyword = HexColor("#FF0000")!.color

        let edited = draft.palette()
        #expect(edited.keyword == HexColor("#FF0000"))
        // Every other token is untouched relative to the seed palette.
        let seed = ThemeTestFixtures.samplePalette()
        #expect(edited.background == seed.background)
        #expect(edited.foreground == seed.foreground)
        #expect(edited.string == seed.string)
        #expect(edited.comment == seed.comment)
        #expect(edited.number == seed.number)
        #expect(edited.type == seed.type)
        #expect(edited.function == seed.function)
        #expect(edited.variable == seed.variable)
        #expect(edited.attribute == seed.attribute)
    }

    @Test func theDraftPaletteRendersTheSamePreviewTheStoreWouldSave() throws {
        // The preview renders `draft.palette()`; saving stores the same palette. Render
        // both as a theme and assert byte-identical PNGs, proving the preview the user
        // approves is pixel-for-pixel what the saved custom theme produces (
        // "preview before saving" tied to the determinism guarantee).
        let draft = CustomThemeDraft(
            editingID: "custom.preview", name: "Preview", palette: ThemeTestFixtures.samplePalette()
        )

        var previewConfig = SnapshotConfig()
        previewConfig.code = ThemeTestFixtures.sampleCode
        previewConfig.language = .swift
        previewConfig.theme = Theme(
            id: "custom.preview", displayName: draft.name, palette: draft.palette())

        // The store re-keys and re-validates on save; the resolved theme must render
        // the same pixels because it carries the same palette value.
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        let saved = store.addTheme(named: draft.name, palette: draft.palette())
        var savedConfig = previewConfig
        savedConfig.theme = store.theme(withID: saved.id)

        let previewImage = try #require(ExportManager.renderCGImage(previewConfig, scale: 1))
        let savedImage = try #require(ExportManager.renderCGImage(savedConfig, scale: 1))
        let previewPNG = try #require(ExportManager.pngData(from: previewImage))
        let savedPNG = try #require(ExportManager.pngData(from: savedImage))
        #expect(previewPNG == savedPNG)
    }
}
