import Foundation
import Testing

@testable import Vitrine

// MARK: - Network-capability gate

@Suite("URL capture is gated on the network entitlement")
struct URLNetworkCapabilityTests {
    @Test func urlCaptureIsEnabledExactlyWhenTheEntitlementIsPresent() {
        // The gate is the entitlement and nothing else: enabled iff the network
        // client entitlement is present on the running build.
        #expect(
            NetworkCapability.isURLCaptureEnabled
                == NetworkCapability.hasNetworkClientEntitlement)
    }

    @Test func theGateNamesTheNetworkClientEntitlement() {
        // The gate keys off the standard sandbox entitlement, not an ad-hoc flag.
        #expect(NetworkCapability.networkClientEntitlement == "com.apple.security.network.client")
    }

    @MainActor
    @Test func aBuildWithoutTheEntitlementRefusesURLCaptureWithATypedError() async throws {
        // With the gate off, the renderer refuses before touching WebKit and never
        // returns a blank image — the "disabled until the entitlement is present"
        // contract, asserted without needing the entitlement in the test host.
        let renderer = URLRenderer(isNetworkCaptureEnabled: false)
        let input = CaptureInput.url(try URLFixture.valid())
        await #expect(throws: RenderError.urlCaptureDisabled) {
            try await renderer.render(input, config: SnapshotConfig())
        }
    }

    @MainActor
    @Test func theDisabledRefusalRunsBeforeAnyWebProcess() async throws {
        // The refusal is synchronous-fast: it does not depend on a launchable web
        // process, so it asserts identically on a sandboxed CI host. Repeating the
        // call proves it is a deterministic gate, not a flaky load timeout.
        let renderer = URLRenderer(isNetworkCaptureEnabled: false)
        let input = CaptureInput.url(try URLFixture.valid())
        for _ in 0..<3 {
            await #expect(throws: RenderError.urlCaptureDisabled) {
                try await renderer.render(input, config: SnapshotConfig())
            }
        }
    }

    /// The app target ships **without** `com.apple.security.network.client` in Phase
    /// 1, so URL capture is inert in the shipping build until the
    /// entitlement is deliberately added. The entitlements file is excluded from the
    /// app's compiled sources and is not a bundle resource, so it is read from the
    /// source tree via `#filePath` — the same anchoring the renderer and golden tests
    /// use.
    @Test func appStoreCompatibleBuildShipsWithoutTheNetworkEntitlement() throws {
        let data = try Data(contentsOf: Self.appEntitlements())
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Vitrine.entitlements must be a property list")
        #expect(
            plist[NetworkCapability.networkClientEntitlement] == nil,
            "local rendering must not request the network client entitlement ( gates URL capture on it)"
        )
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
    }

    /// `<repo>/Vitrine/Resources/Vitrine.entitlements`, derived from this file.
    private static func appEntitlements() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // <repo>/Tests/URLRenderer
            .deletingLastPathComponent()  // <repo>/Tests
            .deletingLastPathComponent()  // <repo>
            .appendingPathComponent("Vitrine", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Vitrine.entitlements", isDirectory: false)
    }
}

// MARK: - URLRenderer routing (pure logic, no web process needed)

@MainActor
@Suite("URLRenderer routing")
struct URLRendererRoutingTests {
    @Test func urlRendererAcceptsOnlyURLs() throws {
        let renderer = URLRenderer()
        #expect(renderer.canRender(.url(try URLFixture.valid())))
        #expect(!renderer.canRender(.code("x", languageHint: nil)))
        #expect(!renderer.canRender(.html("<b>x</b>")))
    }

    @Test func nonURLInputThrowsNoRendererForFromURLRenderer() async throws {
        // Handed an input it rejects (a routing mistake), it throws rather than
        // producing an image — never a blank picture. The gate is on so this is not
        // short-circuited by the entitlement refusal.
        let renderer = URLRenderer(isNetworkCaptureEnabled: true)
        await #expect(throws: RenderError.noRendererFor(kind: "code")) {
            try await renderer.render(.code("x", languageHint: nil), config: SnapshotConfig())
        }
    }

    @Test func urlRendererAcceptsExactlyTheURLInput() throws {
        // The `canRender` contract is what lets the Web Snapshot surface hold either
        // web renderer behind the shared protocol shape.
        let renderer = URLRenderer()
        #expect(renderer.canRender(.url(try URLFixture.valid())))
        #expect(!renderer.canRender(.code("x", languageHint: nil)))
        #expect(!renderer.canRender(.html("<b>x</b>")))
    }
}

// MARK: - URLRenderer validation through the abstraction (no web process needed)

@MainActor
@Suite("URLRenderer rejects unsafe URLs as typed failures")
struct URLRendererValidationTests {
    /// A non-web URL handed to the enabled renderer is rejected during validation and
    /// surfaces as `RenderError.renderFailed`, never a blank image — proving the
    /// scheme/localhost guard runs inside the renderer even when the input already
    /// carries a `URL`. The gate is forced on so the failure is the validation, not
    /// the entitlement refusal.
    @Test func aFileURLInputFailsValidationRatherThanLoading() async throws {
        let renderer = URLRenderer(isNetworkCaptureEnabled: true)
        let file = try #require(URL(string: "file:///etc/hosts"))
        await #expect(throws: RenderError.renderFailed) {
            try await renderer.render(.url(file), config: SnapshotConfig())
        }
    }

    @Test func aLocalhostURLInputFailsValidationRatherThanLoading() async throws {
        let renderer = URLRenderer(isNetworkCaptureEnabled: true)
        let local = try #require(URL(string: "http://127.0.0.1:8080/admin"))
        await #expect(throws: RenderError.loopbackCaptureDisabled) {
            try await renderer.render(.url(local), config: SnapshotConfig())
        }
    }

    @Test func privateNonLoopbackURLsDoNotSuggestTheLoopbackOption() async throws {
        let renderer = URLRenderer(isNetworkCaptureEnabled: true)
        for raw in ["http://dev.local/", "http://192.168.1.1/", "http://169.254.169.254/"] {
            let url = try #require(URL(string: raw))
            await #expect(throws: RenderError.renderFailed) {
                try await renderer.render(.url(url), config: SnapshotConfig())
            }
        }
    }

    @Test func configuredRendererCarriesThePersistedLoopbackChoice() {
        let defaults = UserDefaults(suiteName: "VitrineLoopbackRenderer-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(!URLRenderer.configured(from: settings).allowsLoopbackCapture)

        settings.webCapture.allowsLoopbackCapture = true
        #expect(URLRenderer.configured(from: settings).allowsLoopbackCapture)
    }

    @Test func theEntitlementGateIsCheckedBeforeValidation() async throws {
        // With the gate off, even a malformed/unsafe URL reports the disabled gate,
        // not a validation failure — the gate is the outermost guard, so a local rendering
        // build never reaches the URL-parsing stage for a capture.
        let renderer = URLRenderer(isNetworkCaptureEnabled: false)
        let file = try #require(URL(string: "file:///etc/hosts"))
        await #expect(throws: RenderError.urlCaptureDisabled) {
            try await renderer.render(.url(file), config: SnapshotConfig())
        }
    }

    @Test func anEngineSnapshotFailureSurfacesAsRenderFailedNotABlankImage() async throws {
        // Past both gates (entitlement on, URL valid), a failure inside the offscreen
        // engine must surface as the typed `RenderError.renderFailed`, never a blank
        // asset — the third "typed failure, never a blank image" path, asserted at the
        // renderer boundary. A degenerate viewport makes the engine throw
        // `WebSnapshotError.invalidViewport` deterministically *before* it builds any
        // `WKWebView`, so this exercises the WebSnapshotError → renderFailed mapping
        // hermetically, with no launchable web process required.
        let renderer = URLRenderer(
            viewportPreset: .custom(width: 0, height: 0), isNetworkCaptureEnabled: true)
        await #expect(throws: RenderError.renderFailed) {
            try await renderer.render(.url(try URLFixture.valid()), config: SnapshotConfig())
        }
    }

    @Test func urlCaptureDisabledIsDistinctFromOtherRenderErrors() {
        // The new typed case must not collapse into the existing ones, or a test
        // asserting the disabled gate would pass against an unrelated failure.
        #expect(RenderError.urlCaptureDisabled != .renderFailed)
        #expect(RenderError.loopbackCaptureDisabled != .renderFailed)
        #expect(RenderError.urlCaptureDisabled != .noRendererFor(kind: "url"))
        #expect(RenderError.urlCaptureDisabled == .urlCaptureDisabled)
    }
}
