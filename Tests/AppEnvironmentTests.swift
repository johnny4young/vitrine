import Foundation
import Testing

@testable import Vitrine

// The composition root. `AppEnvironment` constructs the data-store graph in one
// place; the individual `Store.shared` accessors forward to the app-wide root. These pin
// that a freshly-built environment is an independent, fully-wired graph over its own
// defaults — the property that makes the store graph injectable (for tests and previews)
// rather than a set of scattered global singletons.

@MainActor
@Suite("AppEnvironment composition root")
struct AppEnvironmentTests {
    private struct ProProvider: EntitlementProvider {
        var cachedIsPro: Bool { true }
        func currentIsPro() async -> Bool { true }
    }

    @Test func buildsAGraphIsolatedFromTheSharedRoot() throws {
        let suite = try #require(
            UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)"))
        let env = AppEnvironment(defaults: suite)

        // Every store is a distinct instance from the app-wide shared graph…
        #expect(env.appSettings !== AppEnvironment.shared.appSettings)
        #expect(env.brandKit !== AppEnvironment.shared.brandKit)
        #expect(env.recents !== AppEnvironment.shared.recents)
        #expect(env.customThemes !== AppEnvironment.shared.customThemes)
        #expect(env.presets !== AppEnvironment.shared.presets)
        #expect(env.entitlements !== AppEnvironment.shared.entitlements)
    }

    @Test func theGraphIsBackedByTheInjectedDefaults() throws {
        let suite = try #require(
            UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)"))
        let env = AppEnvironment(defaults: suite)

        // A write through the environment's settings lands in the injected suite, proving
        // the whole graph is wired to those defaults rather than the app-wide store.
        env.appSettings.export.scale = 3
        #expect(suite.integer(forKey: SettingsCodec.Keys.exportScale) == 3)
    }

    @Test func settingsRootRetainsTheProvidedGraph() throws {
        let suite = try #require(
            UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)"))
        let env = AppEnvironment(defaults: suite)

        let root = SettingsRootView(environment: env)

        #expect(root.environment === env)
    }

    @Test func editorRootResolvesEveryLongLivedStoreFromTheProvidedGraph() throws {
        let suite = try #require(
            UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)"))
        let env = AppEnvironment(defaults: suite)

        let root = EditorView(environment: env)

        #expect(root.environment === env)
        #expect(root.presets === env.presets)
        #expect(root.themes === env.customThemes)
        #expect(root.brandKit === env.brandKit)
        #expect(root.entitlements === env.entitlements)
    }

    @Test func editorSessionsSeedFromAndRetainTheProvidedGraph() throws {
        let suite = try #require(
            UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)"))
        let env = AppEnvironment(
            defaults: suite, entitlements: Entitlements(provider: ProProvider()))
        env.appSettings.config.theme = .dracula
        env.appSettings.config.code = "print(\"primary\")"
        env.brandKit.isEnabled = true
        env.brandKit.brandKit = BrandKit(handle: "@isolated")

        let primary = EditorSession(identity: .primary, environment: env)
        let secondary = EditorSession(
            identity: EditorWindowIdentity(index: 2), environment: env)
        defer {
            primary.discard()
            secondary.discard()
        }

        #expect(primary.environment === env)
        #expect(secondary.environment === env)
        #expect(primary.settings !== env.appSettings)
        #expect(primary.settings.config.code == "print(\"primary\")")
        #expect(secondary.settings.config.code.isEmpty)
        #expect(secondary.settings.config.theme.id == Theme.dracula.id)
        #expect(secondary.settings.exportConfig.watermark?.text == "@isolated")
    }

    @Test func auxiliaryWindowsRetainAndExposeTheProvidedGraph() throws {
        let suite = try #require(
            UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)"))
        let env = AppEnvironment(defaults: suite)
        let webModel = WebSnapshotModel()

        let socialRoot = SocialCardEditorView(environment: env)
        let webRoot = WebSnapshotEditorView(model: webModel, environment: env)
        let socialController = SocialCardWindowController(environment: env)
        let webController = WebSnapshotWindowController(
            environment: env, model: webModel)

        #expect(socialRoot.environment === env)
        #expect(socialRoot.settings === env.appSettings)
        #expect(socialRoot.themes === env.customThemes)
        #expect(socialRoot.brandKit === env.brandKit)
        #expect(socialRoot.entitlements === env.entitlements)
        #expect(webRoot.environment === env)
        #expect(webRoot.settings === env.appSettings)
        #expect(socialController.environment === env)
        #expect(webController.environment === env)
        #expect(webController.model === webModel)
    }

    @Test func menuBarRootRetainsAndExposesTheProvidedGraph() throws {
        let suite = try #require(
            UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)"))
        let env = AppEnvironment(
            defaults: suite, entitlements: Entitlements(provider: ProProvider()))
        env.brandKit.isEnabled = true
        env.brandKit.brandKit = BrandKit(handle: "@menu-root")
        let feedback = CaptureFeedbackPresenter()
        let root = MenuBarContent(environment: env, feedback: feedback)
        let controller = StatusItemController(environment: env, feedback: feedback)

        #expect(root.environment === env)
        #expect(root.settings === env.appSettings)
        #expect(root.recents === env.recents)
        #expect(root.settings.exportWatermark?.text == "@menu-root")
        #expect(root.feedback === feedback)
        #expect(controller.environment === env)
        #expect(controller.feedback === feedback)
    }
}
