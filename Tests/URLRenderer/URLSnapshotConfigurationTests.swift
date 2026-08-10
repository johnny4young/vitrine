import CoreGraphics
import Foundation
import Testing
import WebKit

@testable import Vitrine

// MARK: - WebSnapshotConfig construction

@Suite("WebSnapshotConfig holds only a validated URL")
struct WebSnapshotConfigTests {
    @Test func configCanOnlyBeBuiltFromAValidURL() throws {
        let url = try URLFixture.valid()
        let config = try WebSnapshotConfig(captureURL: url)
        #expect(config.url == url)
    }

    @Test func buildingAConfigFromARejectedURLThrows() throws {
        let file = try #require(URL(string: "file:///tmp/x.html"))
        #expect(throws: URLValidationError.unsupportedScheme("file")) {
            try WebSnapshotConfig(captureURL: file)
        }
    }

    @Test func theDefaultDataStoreModeIsNonPersistent() throws {
        // The privacy default expressed at the config level: nothing the page
        // touches is persisted unless the caller deliberately opts in.
        let config = try WebSnapshotConfig(captureURL: try URLFixture.valid())
        #expect(config.dataStoreMode == .nonPersistent)
        #expect(config.dataStoreMode.persistsWebsiteData == false)
        #expect(config.dataStoreMode.allowsCookies == false)
    }

    @Test func defaultsMatchTheExporterDefaults() throws {
        let config = try WebSnapshotConfig(captureURL: try URLFixture.valid())
        #expect(config.viewport == CGSize(width: 1200, height: 630))
        #expect(config.scale == 2)
        #expect(config.profile == .sRGB)
    }
}

// MARK: - Data-store mode (cookies and website data are opt-in only)

@Suite("URL capture data-store mode is opt-in")
struct URLDataStoreModeTests {
    @Test func nonPersistentModePersistsNothingAndBlocksCookies() {
        let mode = WebSnapshotConfig.DataStoreMode.nonPersistent
        #expect(mode.persistsWebsiteData == false)
        #expect(mode.allowsCookies == false)
    }

    @Test func persistentModeIsTheOnlyWayToOptIntoCookiesAndWebsiteData() {
        // Cookies and persistent website data ride a single explicit opt-in; there
        // is no third mode that would persist data without enabling cookies, so the
        // "opt-in only" guarantee cannot be partially defeated.
        let mode = WebSnapshotConfig.DataStoreMode.persistent
        #expect(mode.persistsWebsiteData)
        #expect(mode.allowsCookies)
    }

    @MainActor
    @Test func theEngineMapsNonPersistentModeToANonPersistentStore() {
        // The default mode resolves to a non-persistent `WKWebsiteDataStore`, the
        // assertion that the nonpersistent store is actually what WebKit is handed.
        let engine = URLSnapshotEngine()
        let store = engine.dataStore(for: .nonPersistent)
        #expect(store.isPersistent == false)
    }

    @MainActor
    @Test func theEngineMapsPersistentModeToAPersistentStore() {
        let engine = URLSnapshotEngine()
        let store = engine.dataStore(for: .persistent)
        #expect(store.isPersistent)
    }

    @MainActor
    @Test func theEngineRejectsANonPositiveViewportBeforeTouchingWebKit() async throws {
        // The viewport guard is the engine's first check, ahead of building any
        // `WKWebView`, so it asserts deterministically on a sandboxed host that
        // cannot launch a web process: a zero (or negative) dimension is a typed
        // `invalidViewport`, never a blank image and never a hang waiting on a load.
        let engine = URLSnapshotEngine()
        // The raw `.custom` case is deliberately *not* clamped (only the
        // `custom(clampingWidth:height:)` factory clamps), so a test can construct a
        // degenerate viewport to exercise the engine's guard while the UI cannot.
        for preset in [
            WebSnapshotConfig.ViewportPreset.custom(width: 0, height: 400),
            WebSnapshotConfig.ViewportPreset.custom(width: 600, height: 0),
            WebSnapshotConfig.ViewportPreset.custom(width: -10, height: 400),
        ] {
            let config = try WebSnapshotConfig(
                localFileURL: try URLFixture.writeLocalPage(), viewportPreset: preset)
            await #expect(throws: WebSnapshotError.invalidViewport) {
                try await engine.snapshot(of: config)
            }
        }
    }

    @Test func hermeticFixtureHookRejectsRemoteURLsWithoutTrapping() throws {
        let remote = try #require(URL(string: "https://example.com"))
        #expect(throws: WebSnapshotFixtureError.nonFileURL) {
            try WebSnapshotConfig(localFileURL: remote)
        }
    }
}
