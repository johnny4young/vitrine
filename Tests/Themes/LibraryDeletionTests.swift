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
