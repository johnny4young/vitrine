import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Confirmed library deletion")
struct LibraryDeletionTests {
    @Test(arguments: [false, true])
    func deletingAThemeOnlyReplacesTheMatchingDefault(_ active: Bool) {
        let defaults = ThemeTestFixtures.freshDefaults()
        let themes = CustomThemeStore(defaults: defaults)
        let theme = themes.addTheme(named: "Example", palette: ThemeTestFixtures.samplePalette())
        let settings = AppSettings(defaults: defaults)
        settings.config.theme = active ? theme : .dracula
        settings.config.padding = 43
        settings.config.code = "Keep this document"
        settings.config.redactedLineRanges = [1...1]
        let document = settings.config
        let environment = AppEnvironment(defaults: defaults)
        let editor = AppSettings.makeEditorSession(
            seededFrom: defaults, brandKit: environment.brandKit,
            entitlements: environment.entitlements)
        // The primary editor adopts the live document after creating its session.
        // Test deletion of an already-open document, not session seed resolution.
        editor.config = document
        let editorTheme = editor.config.theme
        #expect(editorTheme == document.theme)
        #expect(settings.deleteCustomTheme(id: theme.id, from: themes))
        #expect(settings.config.theme.id == (active ? Theme.oneDark.id : Theme.dracula.id))
        #expect(editor.config.theme == editorTheme)
        #expect(editor.config.padding == document.padding)
        #expect(settings.config.padding == document.padding)
        #expect(settings.config.code == document.code)
        #expect(settings.config.redactedLineRanges == document.redactedLineRanges)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.config.theme.id == settings.config.theme.id)
        #expect(reloaded.config.padding == 43)
        #expect(CustomThemeStore(defaults: defaults).customThemes.isEmpty)
        #expect(!settings.deleteCustomTheme(id: theme.id, from: themes))
        #expect(!settings.deleteCustomTheme(id: Theme.oneDark.id, from: themes))
        #expect(themes.theme(withID: Theme.oneDark.id) == .oneDark)
    }

    @Test func deletingPresetDoesNotChangeAppliedStyleOrBuiltIns() {
        let defaults = PresetTestFixtures.freshDefaults()
        let settings = AppSettings(defaults: defaults)
        let themes = CustomThemeStore(defaults: defaults)
        let store = PresetStore(defaults: defaults)
        settings.config.theme = .dracula
        settings.config.padding = 43
        let preset = store.savePreset(named: "Example", from: settings.config)
        settings.applyStylePreset(preset, themes: themes)
        #expect(store.delete(id: preset.id))
        #expect(settings.config.theme == .dracula)
        #expect(settings.config.padding == 43)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.config.theme == .dracula)
        #expect(reloaded.config.padding == 43)
        #expect(PresetStore(defaults: defaults).userPresets.isEmpty)
        for builtIn in StylePreset.builtIns {
            #expect(!store.delete(id: builtIn.id))
            #expect(store.preset(withID: builtIn.id) == builtIn)
        }
    }
}

@MainActor
@Suite("Custom theme editing")
struct CustomThemeEditingTests {
    @Test func editingKeepsIdPositionAndPresetReferences() {
        let defaults = ThemeTestFixtures.freshDefaults()
        let themes = CustomThemeStore(defaults: defaults)
        let settings = AppSettings(defaults: defaults)
        let presets = PresetStore(defaults: defaults)
        let original = themes.addTheme(named: "First", palette: ThemeTestFixtures.samplePalette())
        themes.addTheme(named: "Second", palette: ThemeTestFixtures.samplePalette())
        settings.config.theme = original
        let preset = presets.savePreset(named: "Uses First", from: settings.config)
        settings.config.theme = .dracula

        var edited = ThemeTestFixtures.samplePalette()
        edited.background = HexColor("#000000")!
        let saved = settings.saveCustomTheme(
            editingID: original.id, name: "First Edited", palette: edited, in: themes)

        #expect(saved.id == original.id)
        #expect(themes.customThemes.first?.id == original.id)
        #expect(themes.customThemes.count == 2)
        #expect(settings.config.theme == .dracula)
        settings.applyStylePreset(preset, themes: themes)
        #expect(settings.config.theme.id == original.id)
        #expect(settings.config.theme.palette == edited)
    }

    @Test func editingTheDefaultRefreshesItAndANewThemeBecomesDefault() {
        let defaults = ThemeTestFixtures.freshDefaults()
        let themes = CustomThemeStore(defaults: defaults)
        let settings = AppSettings(defaults: defaults)
        let added = settings.saveCustomTheme(
            editingID: nil, name: "New", palette: ThemeTestFixtures.samplePalette(), in: themes)
        #expect(settings.config.theme == added)

        var edited = ThemeTestFixtures.samplePalette()
        edited.keyword = HexColor("#FF0000")!
        settings.saveCustomTheme(editingID: added.id, name: "New", palette: edited, in: themes)
        #expect(settings.config.theme.id == added.id)
        #expect(settings.config.theme.palette == edited)
        #expect(AppSettings(defaults: defaults).config.theme.palette == edited)
    }
}
