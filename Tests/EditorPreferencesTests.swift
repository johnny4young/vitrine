import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Editor preferences")
struct EditorPreferencesTests {
    private func environment() -> AppEnvironment {
        AppEnvironment(
            defaults: testDefaults(), entitlements: Entitlements(provider: FreeProvider()))
    }

    @Test func additionalWindowsKeepTheResolvedCustomDefaultTheme() {
        let environment = environment()
        let theme = environment.customThemes.addTheme(
            named: "Studio", palette: ThemeTestFixtures.samplePalette())
        environment.appSettings.selectTheme(theme)
        environment.appSettings.style.padding = 47
        environment.appSettings.documentCode = "Only the primary document"
        let primary = EditorSession(
            identity: .primary, environment: environment, feedback: .noOp, presentation: .noOp)
        let additional = EditorSession(
            identity: EditorWindowIdentity(index: 2), environment: environment,
            feedback: .noOp, presentation: .noOp)
        defer {
            primary.discard()
            additional.discard()
        }

        #expect(primary.settings.config.theme == theme)
        #expect(additional.settings.config.theme == theme)
        #expect(additional.settings.config.padding == 47)
        #expect(additional.settings.documentCode.isEmpty)
        #expect(primary.settings.documentCode == "Only the primary document")
        additional.settings.style.padding = 62
        #expect(primary.settings.style.padding == 47)
        #expect(environment.appSettings.style.padding == 47)
    }

    @Test func resolvingTheThemeDoesNotCopyItsCatalogIntoTheSession() {
        let defaults = testDefaults()
        let environment = AppEnvironment(
            defaults: defaults, entitlements: Entitlements(provider: FreeProvider()))
        let theme = environment.customThemes.addTheme(
            named: "Studio", palette: ThemeTestFixtures.samplePalette())
        environment.appSettings.selectTheme(theme)
        let store = InMemoryUserDefaults()
        let session = AppSettings.makeEditorSession(
            seededFrom: defaults, store: store, brandKit: environment.brandKit,
            entitlements: environment.entitlements)
        defer { session.discardEphemeralStore() }
        #expect(session.style.theme == theme)
        #expect(store.object(forKey: CustomThemeStore.storageKey) == nil)
        #expect(environment.customThemes.customThemes == [theme])
    }

    @Test func defaultDestinationDoesNotRestyleOpenWindows() throws {
        let defaults = testDefaults()
        let environment = AppEnvironment(
            defaults: defaults, entitlements: Entitlements(provider: FreeProvider()))
        let open = environment.makeEditorSessionSettings()
        let original = open.config
        let slide = try #require(ExportPreset.preset(withID: "transparent-slide"))
        environment.appSettings.selectPreset(slide)
        let next = environment.makeEditorSessionSettings()
        defer {
            open.discardEphemeralStore()
            next.discardEphemeralStore()
        }
        #expect(open.config == original)
        #expect(open.selectedPresetID == nil)
        #expect(next.selectedPresetID == slide.id)
        #expect(slide.matches(next.config))
        #expect(next.export.scale == environment.appSettings.export.scale)
        let reloaded = AppEnvironment(
            defaults: defaults, entitlements: Entitlements(provider: FreeProvider()))
        #expect(reloaded.appSettings.selectedPresetID == slide.id)
        #expect(reloaded.appSettings.config == next.config)
    }

    @Test func promotedCustomThemeSurvivesReloadWithoutChangingOtherEditors() {
        let defaults = testDefaults()
        let environment = AppEnvironment(
            defaults: defaults, entitlements: Entitlements(provider: FreeProvider()))
        let untouched = environment.makeEditorSessionSettings()
        let session = environment.makeEditorSessionSettings()
        defer {
            untouched.discardEphemeralStore()
            session.discardEphemeralStore()
        }
        let original = untouched.config
        let theme = environment.customThemes.addTheme(
            named: "Studio", palette: ThemeTestFixtures.samplePalette())
        session.style.theme = theme
        environment.appSettings.makeDefault(from: session)
        let reloaded = AppEnvironment(
            defaults: defaults, entitlements: Entitlements(provider: FreeProvider()))
        let next = reloaded.makeEditorSessionSettings()
        defer { next.discardEphemeralStore() }
        #expect(next.style.theme == theme)
        #expect(untouched.config == original)
        #expect(reloaded.customThemes.customThemes == [theme])
    }

    @Test(arguments: [false, true])
    func makeDefaultPromotesCaptureOptionsButNotGlobalBehavior(concealed: Bool) {
        let environment = environment()
        let shared = environment.appSettings
        shared.export.autoCopy = false
        shared.export.alsoSaveToFile = true
        shared.export.closeAfterCopy = false
        shared.export.concealClipboard = concealed
        let session = environment.makeEditorSessionSettings()
        defer { session.discardEphemeralStore() }
        session.documentCode = "Keep the editor document"
        session.style.theme = .dracula
        session.style.padding = 55
        session.export.scale = 3
        session.export.format = .pdf
        session.export.colorProfile = .displayP3
        session.export.richClipboard = true
        session.export.textSidecar = true
        session.export.concealClipboard = !concealed
        let document = session.config
        var expected = document
        expected.code = ""
        expected.clearContentMarks()
        shared.makeDefault(from: session)

        #expect(shared.config == expected)
        #expect(session.config == document)
        #expect(shared.export.scale == 3)
        #expect(shared.export.format == .pdf)
        #expect(shared.export.colorProfile == .displayP3)
        #expect(shared.export.richClipboard)
        #expect(shared.export.textSidecar)
        #expect(shared.export.concealClipboard == concealed)
        #expect(!shared.export.autoCopy)
        #expect(shared.export.alsoSaveToFile)
        #expect(!shared.export.closeAfterCopy)
        let next = environment.makeEditorSessionSettings()
        defer { next.discardEphemeralStore() }
        #expect(next.config == expected)
        #expect(next.export.scale == 3)
        // Global privacy is read from the environment, not seeded.
        #expect(!next.export.concealClipboard)
    }
}
