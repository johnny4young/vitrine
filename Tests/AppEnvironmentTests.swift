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

        let primary = EditorSession(
            identity: .primary,
            environment: env,
            feedback: .noOp,
            presentation: .noOp)
        let secondary = EditorSession(
            identity: EditorWindowIdentity(index: 2),
            environment: env,
            feedback: .noOp,
            presentation: .noOp)
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

        let socialRoot = SocialCardEditorView(
            environment: env,
            feedback: .noOp,
            presentation: .noOp)
        let webRoot = WebSnapshotEditorView(
            model: webModel,
            environment: env,
            feedback: .noOp,
            presentation: .noOp)
        let socialController = SocialCardWindowController(
            environment: env,
            feedback: .noOp,
            presentation: .noOp)
        let webController = WebSnapshotWindowController(
            environment: env,
            model: webModel,
            feedback: .noOp,
            presentation: .noOp)

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
        var destinations: [MenuBarNavigation.Destination] = []
        let navigation = MenuBarNavigation(
            present: { destinations.append($0) },
            loadPrimaryEditor: { _ in },
            terminate: {})
        let root = MenuBarContent(
            environment: env,
            feedback: feedback,
            navigation: navigation)
        let controller = StatusItemController(
            environment: env,
            feedback: feedback,
            navigation: navigation)

        #expect(root.environment === env)
        #expect(root.settings === env.appSettings)
        #expect(root.recents === env.recents)
        #expect(root.settings.exportWatermark?.text == "@menu-root")
        #expect(root.feedback === feedback)
        #expect(controller.environment === env)
        #expect(controller.feedback === feedback)
        root.navigation.show(.help)
        controller.navigation.show(.settings)
        #expect(destinations == [.help, .settings])
    }

    @Test func appLifecycleRetainsTheProvidedGraphAndFeedbackPresenter() throws {
        let suite = try #require(
            UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)"))
        let env = AppEnvironment(defaults: suite)
        let feedback = CaptureFeedbackPresenter()
        let delegate = AppDelegate(
            environment: env,
            feedback: feedback,
            editorPresentation: .noOp)

        #expect(delegate.environment === env)
        #expect(delegate.feedback === feedback)
        #expect(delegate.launchArguments.environment === env)
        #expect(delegate.mainMenu.environment === env)
        #expect(delegate.mainMenu.feedback === feedback)
        #expect(delegate.mainMenu.appCommands.environment === env)
        #expect(delegate.mainMenu.appCommands.feedback === feedback)
        #expect(delegate.mainMenu.editorCommands.settings === env.appSettings)
    }

    @Test func launchArgumentsSeedOnlyTheProvidedGraph() throws {
        let firstDefaults = try #require(
            UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)"))
        let secondDefaults = try #require(
            UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)"))
        let first = AppEnvironment(defaults: firstDefaults)
        let second = AppEnvironment(defaults: secondDefaults)
        let handler = AppLaunchArgumentHandler(environment: first)

        let didOpenWindow = handler.handle([
            "Vitrine",
            "--skip-onboarding",
            "--demo-html-format",
            "--demo-brand-kit-free",
        ])

        #expect(!didOpenWindow)
        #expect(first.appSettings.hasSeenWelcome)
        #expect(first.appSettings.config.language == .html)
        #expect(first.appSettings.config.code.contains("<!doctype html>"))
        #expect(first.brandKit.isEnabled)
        #expect(first.brandKit.brandKit.handle == "@vitrine")

        #expect(!second.appSettings.hasSeenWelcome)
        #expect(second.appSettings.config.language == .swift)
        #expect(second.appSettings.config.code.isEmpty)
        #expect(!second.brandKit.isEnabled)
    }

    @Test func launchArgumentsOpenTheMenuPanelThroughTheInjectedRoute() throws {
        let suite = try #require(
            UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)"))
        let environment = AppEnvironment(defaults: suite)
        var presentations = 0
        let handler = AppLaunchArgumentHandler(
            environment: environment,
            showMenuBarPanel: { presentations += 1 })

        let didOpenWindow = handler.handle(["Vitrine", "--open-menu-panel"])

        #expect(didOpenWindow)
        #expect(presentations == 1)
    }

    @Test func lifecycleAdaptersDoNotEscapeToGlobalDataStores() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for relativePath in [
            "Vitrine/App/AppDelegate.swift",
            "Vitrine/App/AppLaunchArgumentHandler.swift",
            "Vitrine/App/AppMenu.swift",
            "Vitrine/App/AppCommandResponder.swift",
            "Vitrine/App/EditorCommandResponder.swift",
            "Vitrine/App/VitrineCommands.swift",
            "Vitrine/Editor/EditorView+Stage.swift",
        ] {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8)
            for forbiddenDependency in [
                "AppSettings.shared",
                "Entitlements.shared",
                "RecentsStore.shared",
                "BrandKitStore.shared",
                "QuickCapture.perform(environment: .shared",
                "AppCommandResponder.shared",
                "EditorCommandResponder.shared",
            ] {
                #expect(
                    !source.contains(forbiddenDependency),
                    "\(relativePath) must resolve data through its retained environment")
            }
        }
    }
}
