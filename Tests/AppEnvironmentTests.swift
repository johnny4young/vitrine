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
    @Test func buildsAGraphIsolatedFromTheSharedRoot() {
        let suite = UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)")!
        let env = AppEnvironment(defaults: suite)

        // Every store is a distinct instance from the app-wide shared graph…
        #expect(env.appSettings !== AppEnvironment.shared.appSettings)
        #expect(env.brandKit !== AppEnvironment.shared.brandKit)
        #expect(env.recents !== AppEnvironment.shared.recents)
        #expect(env.customThemes !== AppEnvironment.shared.customThemes)
        #expect(env.presets !== AppEnvironment.shared.presets)
        #expect(env.entitlements !== AppEnvironment.shared.entitlements)
    }

    @Test func theGraphIsBackedByTheInjectedDefaults() {
        let suite = UserDefaults(suiteName: "VitrineEnv-\(UUID().uuidString)")!
        let env = AppEnvironment(defaults: suite)

        // A write through the environment's settings lands in the injected suite, proving
        // the whole graph is wired to those defaults rather than the app-wide store.
        env.appSettings.export.scale = 3
        #expect(suite.integer(forKey: SettingsCodec.Keys.exportScale) == 3)
    }
}
