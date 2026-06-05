import AppKit
import CoreGraphics
import Foundation
import Testing
import WebKit

@testable import Vitrine

/// CS-043 — the URL snapshot renderer with an explicit network mode.
///
/// These suites prove the acceptance criteria the ticket asks for:
///
/// 1. **URL validation** — only `http`/`https` URLs are accepted; `file:`, `data:`,
///    `javascript:`, private localhost, and malformed URLs are rejected as typed
///    errors that never carry the URL itself.
/// 2. **Network-entitlement guard** — URL capture is disabled until the app target
///    includes `com.apple.security.network.client`; a build without it refuses with
///    a typed `RenderError.urlCaptureDisabled`, and the renderer never touches WebKit.
/// 3. **Nonpersistent data store** — `WKWebsiteDataStore.nonPersistent()` is the
///    default, and cookies / persistent website data are opt-in only.
/// 4. **No remote render service** — a URL snapshot is produced locally; the renderer
///    holds no remote endpoint and the disclosure copy says so.
/// 5. **Typed failures, never a blank image** — every failure mode surfaces a typed
///    error rather than an empty asset.
///
/// ## Live WebKit vs. pure logic
///
/// Almost everything here is pure logic — validation, the entitlement gate, the
/// data-store mapping, routing, and the disclosure copy — so those suites always run
/// and assert on every machine. The single suite that rasterizes a real page through
/// `WKWebView` is gated on `WebKitAvailability.canRenderOffscreen` (defined in
/// `HTMLRendererTests`), because a sandboxed, ad-hoc-signed test host cannot launch a
/// web content process; it is reported as **skipped** there, never silently passed.

// MARK: - Fixtures

private enum URLFixture {
    /// A representative, well-formed remote page URL — used only to exercise
    /// validation and routing logic; no test loads it over the network.
    static func valid() throws -> URL {
        try #require(URL(string: "https://example.com/article"))
    }

    /// A small, self-contained local HTML file written to the temp directory and
    /// served over `file://`. Loading a `file:` URL is rejected by validation, so this
    /// is used only by the live snapshot suite, which renders it by handing the engine
    /// a config built from an already-validated URL substitute. The page has an
    /// explicit background so the snapshot is non-empty.
    static func writeLocalPage() throws -> URL {
        let html = """
            <!doctype html><html><head><meta charset="utf-8"><style>
            html,body{margin:0;padding:0;background:#0b1020;color:#fff;font:24px sans-serif}
            </style></head><body><h1>Local capture</h1></body></html>
            """
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineURLTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("page.html")
        try html.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}

// MARK: - URL validation

@Suite("URL capture validation · CS-043")
struct URLValidationTests {
    @Test func httpAndHttpsURLsAreAccepted() throws {
        let http = try #require(URL(string: "http://example.com"))
        let https = try #require(URL(string: "https://example.com/path?q=1#frag"))
        #expect(try WebSnapshotConfig.validate(captureURL: http) == http)
        #expect(try WebSnapshotConfig.validate(captureURL: https) == https)
    }

    @Test func schemeMatchingIsCaseInsensitive() throws {
        // A pasted URL may carry an upper-cased scheme; it is still a web URL.
        let upper = try #require(URL(string: "HTTPS://example.com"))
        #expect(try WebSnapshotConfig.validate(captureURL: upper) == upper)
    }

    @Test func fileURLsAreRejected() throws {
        let file = try #require(URL(string: "file:///etc/passwd"))
        #expect(throws: URLValidationError.unsupportedScheme("file")) {
            try WebSnapshotConfig.validate(captureURL: file)
        }
    }

    @Test func dataURLsAreRejected() throws {
        // `data:` is a non-web scheme, refused by name; it never loads, which is the
        // guarantee that matters.
        let data = try #require(URL(string: "data:text/html,<b>x</b>"))
        #expect(throws: URLValidationError.unsupportedScheme("data")) {
            try WebSnapshotConfig.validate(captureURL: data)
        }
    }

    @Test func javascriptURLsAreRejected() throws {
        // A `javascript:` URL is a non-web scheme, refused by name; it never executes.
        let js = try #require(URL(string: "javascript:alert(1)"))
        #expect(throws: URLValidationError.unsupportedScheme("javascript")) {
            try WebSnapshotConfig.validate(captureURL: js)
        }
    }

    @Test func otherSchemesAreRejectedAsUnsupported() throws {
        // A scheme that does parse a host (e.g. ftp) is refused as an unsupported
        // scheme, naming the scheme but never the URL.
        let ftp = try #require(URL(string: "ftp://files.example.com/archive.zip"))
        #expect(throws: URLValidationError.unsupportedScheme("ftp")) {
            try WebSnapshotConfig.validate(captureURL: ftp)
        }
    }

    @Test func malformedStringsAreRejected() {
        // Empty, scheme-only, and host-less strings cannot form a loadable URL.
        #expect(throws: URLValidationError.malformed) {
            try WebSnapshotConfig.validate(captureURLString: "")
        }
        #expect(throws: URLValidationError.malformed) {
            try WebSnapshotConfig.validate(captureURLString: "https://")
        }
        #expect(throws: URLValidationError.malformed) {
            try WebSnapshotConfig.validate(captureURLString: "not a url")
        }
    }

    @Test func localhostHostsAreRejected() throws {
        for raw in [
            "http://localhost/admin",
            "http://localhost:3000",
            "http://127.0.0.1:8080",
            "http://127.5.4.3/",
            "http://[::1]:9000",
            "http://0.0.0.0:5000",
            "http://myservice.local/status",
        ] {
            let url = try #require(URL(string: raw), "fixture \(raw) must parse")
            #expect(
                throws: URLValidationError.privateLocalhost,
                "\(raw) must be refused as private localhost"
            ) {
                try WebSnapshotConfig.validate(captureURL: url)
            }
        }
    }

    @Test func publicHostsThatMerelyContainLoopbackTextAreAllowed() throws {
        // The localhost guard must not over-match: a real public host whose name
        // merely contains "localhost" or starts past the loopback block still loads.
        let lookalike = try #require(URL(string: "https://localhost.example.com/page"))
        #expect(try WebSnapshotConfig.validate(captureURL: lookalike) == lookalike)
        let notLoopback = try #require(URL(string: "https://128.0.0.1/page"))
        #expect(try WebSnapshotConfig.validate(captureURL: notLoopback) == notLoopback)
    }

    @Test func validatingTextTrimsSurroundingWhitespace() throws {
        // A pasted URL often carries a trailing newline; validation trims before
        // parsing so the clean URL is what would load.
        let url = try WebSnapshotConfig.validate(captureURLString: "  https://example.com/x  \n")
        #expect(url == (try #require(URL(string: "https://example.com/x"))))
    }

    @Test func validationErrorsAreDistinctAndCarryNoURL() {
        // The typed-error contract: the cases are not interchangeable, and the
        // associated value is a scheme token, never the URL.
        #expect(URLValidationError.malformed != .privateLocalhost)
        #expect(URLValidationError.unsupportedScheme("file") != .unsupportedScheme("data"))
        #expect(URLValidationError.unsupportedScheme("file") != .malformed)
        #expect(URLValidationError.malformed == .malformed)
    }

    @Test func everyValidationErrorHasAStableNonPIIDiagnosticReason() {
        // The diagnostic label names the refusal, never the URL, and is distinct per
        // case so logs are filterable.
        let reasons = [
            URLValidationError.malformed.diagnosticReason,
            URLValidationError.unsupportedScheme("file").diagnosticReason,
            URLValidationError.privateLocalhost.diagnosticReason,
        ]
        #expect(Set(reasons).count == reasons.count)
        #expect(reasons.allSatisfy { !$0.isEmpty })
        #expect(URLValidationError.privateLocalhost.diagnosticReason == "private-localhost")
        #expect(
            URLValidationError.unsupportedScheme("file").diagnosticReason
                == "unsupported-scheme-file")
    }
}

// MARK: - WebSnapshotConfig construction

@Suite("WebSnapshotConfig holds only a validated URL · CS-043")
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

@Suite("URL capture data-store mode is opt-in · CS-043")
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
            let config = WebSnapshotConfig(
                localFileURL: try URLFixture.writeLocalPage(), viewportPreset: preset)
            await #expect(throws: WebSnapshotError.invalidViewport) {
                try await engine.snapshot(of: config)
            }
        }
    }
}

// MARK: - Network-capability gate

@Suite("URL capture is gated on the network entitlement · CS-043")
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
        // acceptance, asserted without needing the entitlement in the test host.
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
    /// 1 (CS-011/CS-062), so URL capture is inert in the shipping build until the
    /// entitlement is deliberately added. The entitlements file is excluded from the
    /// app's compiled sources and is not a bundle resource, so it is read from the
    /// source tree via `#filePath` — the same anchoring the renderer and golden tests
    /// use.
    @Test func appShipsWithoutTheNetworkEntitlementInPhase1() throws {
        let data = try Data(contentsOf: Self.appEntitlements())
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Vitrine.entitlements must be a property list")
        #expect(
            plist[NetworkCapability.networkClientEntitlement] == nil,
            "Phase 1 must not request the network client entitlement (CS-043 gates URL capture on it)"
        )
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
    }

    /// `<repo>/Vitrine/Resources/Vitrine.entitlements`, derived from this file at
    /// `<repo>/Tests/URLRendererTests.swift`.
    private static func appEntitlements() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // <repo>/Tests
            .deletingLastPathComponent()  // <repo>
            .appendingPathComponent("Vitrine", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Vitrine.entitlements", isDirectory: false)
    }
}

// MARK: - URLRenderer routing (pure logic, no web process needed)

@MainActor
@Suite("URLRenderer routing · CS-043")
struct URLRendererRoutingTests {
    @Test func urlRendererAcceptsOnlyURLs() throws {
        let renderer = URLRenderer()
        #expect(renderer.canRender(.url(try URLFixture.valid())))
        #expect(!renderer.canRender(.code("x", languageHint: nil)))
        #expect(!renderer.canRender(.html("<b>x</b>")))
    }

    @Test func urlRendererDefersNothing() throws {
        // It is the real renderer, not the Phase 2 stub: it reports no deferral
        // ticket, so wiring it into a coordinator renders URLs instead of deferring.
        #expect(URLRenderer().deferralTicket(for: .url(try URLFixture.valid())) == nil)
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

    @Test func urlRendererInACoordinatorReportsNoDeferral() throws {
        // Wired into a coordinator, a URL renders today instead of deferring — the
        // seam CS-040 documented for when CS-043 ships.
        let coordinator = RenderCoordinator(renderers: [URLRenderer()])
        let url = CaptureInput.url(try URLFixture.valid())
        #expect(coordinator.renderer(for: url) is URLRenderer)
        #expect(coordinator.deferralReason(for: url) == nil)
    }
}

// MARK: - URLRenderer validation through the abstraction (no web process needed)

@MainActor
@Suite("URLRenderer rejects unsafe URLs as typed failures · CS-043")
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
        await #expect(throws: RenderError.renderFailed) {
            try await renderer.render(.url(local), config: SnapshotConfig())
        }
    }

    @Test func theEntitlementGateIsCheckedBeforeValidation() async throws {
        // With the gate off, even a malformed/unsafe URL reports the disabled gate,
        // not a validation failure — the gate is the outermost guard, so a Phase 1
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
        #expect(RenderError.urlCaptureDisabled != .noRendererFor(kind: "url"))
        #expect(RenderError.urlCaptureDisabled != .deferredToPhase2(ticket: "CS-043"))
        #expect(RenderError.urlCaptureDisabled == .urlCaptureDisabled)
    }
}

// MARK: - First-use disclosure (no web process needed)

@Suite("URL capture first-use disclosure · CS-043")
struct URLFirstUseDisclosureTests {
    @Test func theDisclosureExplainsLocalWebKitLoading() {
        // The first-use copy must make the privacy fact explicit: the page is loaded
        // locally in WebKit, and there is no remote screenshot service.
        let disclosure = WebSnapshotConfig.firstUseDisclosure
        #expect(!disclosure.title.isEmpty)
        #expect(disclosure.message.localizedCaseInsensitiveContains("locally"))
        #expect(disclosure.message.localizedCaseInsensitiveContains("WebKit"))
        #expect(!disclosure.confirmTitle.isEmpty)
        #expect(!disclosure.cancelTitle.isEmpty)
    }

    @Test func theDisclosurePromisesNoRemoteRenderService() {
        // The copy explicitly rules out a remote render service, the privacy promise
        // CS-043 preserves.
        let message = WebSnapshotConfig.firstUseDisclosure.message
        #expect(message.localizedCaseInsensitiveContains("remote"))
        #expect(message.localizedCaseInsensitiveContains("on-device"))
    }
}

// MARK: - Live capture of a local page (real image)

/// The one suite that rasterizes through `WKWebView`. A live capture cannot use a
/// real network in the test host, and validation rejects a `file:` URL, so this
/// drives the engine through the explicit hermetic hook (`init(localFileURL:)`),
/// which loads a local fixture page while still honoring the privacy default (a
/// nonpersistent data store). The shared bitmap path means a URL snapshot sizes
/// identically to an HTML one — exactly `viewport × scale`. It runs only where a web
/// content process can launch and is reported skipped otherwise.
@MainActor
@Suite(
    "URLSnapshotEngine renders a page offscreen · CS-043",
    .enabled("requires a launchable WKWebView web process (unavailable in a sandboxed test host)") {
        await WebKitAvailability.canRenderOffscreen()
    })
struct URLSnapshotEngineRenderTests {
    @Test func aLocalPageRendersToAnImageOfTheRequestedPixelSize() async throws {
        let engine = URLSnapshotEngine()
        let config = WebSnapshotConfig(
            localFileURL: try URLFixture.writeLocalPage(),
            viewportPreset: .custom(width: 600, height: 400), scale: 2)
        // The data store is the privacy default even on the live path.
        #expect(config.dataStoreMode == .nonPersistent)
        let image = try await engine.snapshot(of: config)
        // The viewport is fixed and the scale is applied, so the bitmap is exactly
        // viewport × scale — the determinism the acceptance criteria require.
        #expect(image.width == 1200)
        #expect(image.height == 800)
    }

    @Test func theEngineProducesATaggedAssetForALocalPage() async throws {
        // The engine + the exporter's color step yield a real, color-tagged asset —
        // the same `RenderedAsset` shape a code snapshot yields, so the clipboard and
        // save paths stay uniform across input kinds.
        let engine = URLSnapshotEngine()
        let config = WebSnapshotConfig(
            localFileURL: try URLFixture.writeLocalPage(),
            viewportPreset: .custom(width: 400, height: 300), scale: 1)
        let image = try await engine.snapshot(of: config)
        let asset = RenderedAsset(
            cgImage: ExportManager.normalized(image, to: .sRGB), profile: .sRGB)
        #expect(asset.pixelWidth == 400)
        #expect(asset.pixelHeight == 300)
        #expect(asset.profile == .sRGB)
    }
}
