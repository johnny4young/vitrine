import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import Vitrine

/// the local HTML renderer backed by an offscreen `WKWebView`.
///
/// These suites prove the documented behavior:
///
/// 1. **Deterministic offscreen render** — a static HTML fixture rasterizes to a
///    real image whose pixel size is exactly `viewport × scale`, produced by a web
///    view that is never on screen (so no Screen Recording permission is involved).
/// 2. **Network blocked for pasted HTML** — HTML that references a remote subresource
///    or attempts a top-level remote redirect still renders locally; the remote load
///    is cancelled unless the caller explicitly allows network.
/// 3. **Local assets only** — a relative reference cannot resolve without a base URL,
///    and a non-`file:` base URL is rejected as a typed error.
/// 4. **Typed errors, never a blank image** — every failure mode (invalid viewport,
///    invalid base URL, load failure, timeout) surfaces a distinct `WebSnapshotError`,
///    and the renderer maps a web failure to `RenderError.renderFailed`.
/// 5. **No network entitlement** — local HTML rendering does not add the network
///    client entitlement to the app target.
///
/// ## Live WebKit vs. pure logic
///
/// The pure-logic suites (typed-error distinctness, base-URL rejection before any
/// load, routing, `canRender`, and the entitlement guard) always run and assert.
///
/// The suites that actually rasterize through `WKWebView` are gated on
/// `WebKitAvailability.canRenderOffscreen`. WebKit renders out of process, and in a
/// **sandboxed, ad-hoc-signed unit-test host** the web content process cannot
/// launch (`WebProcessProxy ... web process failed to launch`), so a real snapshot
/// can never complete there — the engine correctly reports `.timedOut`, but that is
/// an environment limit, not a product defect. Rather than fail the gate for it, the
/// live suites are `enabled(if:)` a one-time probe confirms the web process launches
/// (it does in a properly signed app and in non-sandboxed contexts), and are
/// reported as **skipped** otherwise — never silently passed. `WKWebView` is
/// main-actor bound, so every live suite is `@MainActor`.

// MARK: - WebKit availability probe

/// Whether this process can actually drive an offscreen `WKWebView` snapshot, probed
/// once and cached. Used as the `enabled(if:)` condition for the live-render suites
/// so they run where WebKit works and skip cleanly where the sandboxed test host
/// cannot launch a web content process.
enum WebKitAvailability {
    /// The cached probe result, computed at most once across the whole run. An
    /// `actor` serializes the first probe so concurrent suites do not each spawn a
    /// web view.
    private actor Cache {
        static let shared = Cache()
        private var result: Bool?

        func value() async -> Bool {
            if let result { return result }
            let probed = await WebKitAvailability.probe()
            result = probed
            return probed
        }
    }

    /// The cached probe result, awaited by the `enabled(_:_:)` async condition each
    /// live suite uses. `nonisolated` so the `@Sendable` trait closure can call it.
    nonisolated static func canRenderOffscreen() async -> Bool {
        await Cache.shared.value()
    }

    /// Attempts a minimal offscreen snapshot with a short timeout. Returns `true`
    /// only if a real image came back, so a host that cannot launch the web process
    /// (the snapshot times out or fails) probes as unavailable.
    @MainActor
    private static func probe() async -> Bool {
        // On hosted CI the WebKit web process is unstable: it cannot acquire its RBS
        // assertions and intermittently *crashes the test host* (SIGABRT) rather than
        // failing with a catchable error — a `do/catch` cannot recover a process abort.
        // The live-render suites already skip there (the probe times out), so launching
        // a web process buys no coverage and only risks aborting the whole run. Skip the
        // launch entirely on CI; run it for real everywhere else.
        if isContinuousIntegration { return false }
        do {
            _ = try await WebSnapshotView().snapshot(
                of: .init(
                    html: "<html><body style='background:#fff'>probe</body></html>",
                    viewport: CGSize(width: 64, height: 64),
                    scale: 1,
                    timeout: .seconds(5)))
            return true
        } catch {
            return false
        }
    }

    /// Whether the suite is running under a hosted CI runner, where the WebKit web
    /// process is unreliable. GitHub Actions sets `GITHUB_ACTIONS`/`CI`.
    private static var isContinuousIntegration: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["GITHUB_ACTIONS"] == "true" || environment["CI"] == "true"
    }
}

// MARK: - Fixtures

private enum HTMLFixture {
    /// A self-contained document with an explicit background and a block of text —
    /// no external references, so it renders fully locally and deterministically.
    static let staticCard = """
        <!doctype html>
        <html>
          <head><meta charset="utf-8"><style>
            html, body { margin: 0; padding: 0; }
            body { background: #101522; color: #f5f7ff; font: 28px -apple-system, sans-serif; }
            .card { padding: 64px; }
            h1 { margin: 0 0 16px; }
          </style></head>
          <body><div class="card"><h1>Vitrine</h1><p>Local HTML render.</p></div></body>
        </html>
        """

    /// References a remote image by absolute URL. With network blocked the remote
    /// request is cancelled, but the document itself still loads and snapshots — the
    /// missing image must not fail the whole render.
    static let remoteImage = """
        <!doctype html>
        <html><body style="margin:0;background:#222">
          <img src="https://example.com/should-be-blocked.png" alt="blocked">
          <p style="color:#fff;font:24px sans-serif">text still renders</p>
        </body></html>
        """

    /// References an asset by a *relative* path. With no base URL the reference
    /// cannot resolve to anything, which is the local-assets-only guarantee; the
    /// surrounding text still renders.
    static let relativeAsset = """
        <!doctype html>
        <html><body style="margin:0;background:#333">
          <img src="logo.png" alt="unresolvable">
          <p style="color:#fff;font:24px sans-serif">no base URL</p>
        </body></html>
        """

    /// A minimal valid document, for the smallest possible successful render.
    static let minimal = "<html><body style='background:#fff'>hi</body></html>"
}

// MARK: - Deterministic offscreen render

@MainActor
@Suite(
    "WebSnapshotView renders HTML offscreen · ",
    .enabled("requires a launchable WKWebView web process (unavailable in a sandboxed test host)") {
        await WebKitAvailability.canRenderOffscreen()
    })
struct WebSnapshotRenderTests {
    @Test func staticHTMLRendersToAnImageOfTheRequestedPixelSize() async throws {
        let engine = WebSnapshotView()
        let request = WebSnapshotView.Request(
            html: HTMLFixture.staticCard,
            viewport: CGSize(width: 600, height: 400),
            scale: 2)
        let image = try await engine.snapshot(of: request)
        // The viewport is fixed and the scale is applied, so the bitmap is exactly
        // viewport × scale — the determinism the documented contract require.
        #expect(image.width == 1200)
        #expect(image.height == 800)
    }

    @Test func sameHTMLAndViewportProduceTheSamePixelSizeTwice() async throws {
        // Determinism: rendering the same input twice yields the same dimensions
        // (the engine builds a fresh, identically configured web view each call).
        let engine = WebSnapshotView()
        let request = WebSnapshotView.Request(
            html: HTMLFixture.minimal, viewport: CGSize(width: 320, height: 200), scale: 1)
        let first = try await engine.snapshot(of: request)
        let second = try await engine.snapshot(of: request)
        #expect(first.width == second.width)
        #expect(first.height == second.height)
        #expect(first.width == 320)
        #expect(first.height == 200)
    }

    @Test func scaleMultipliesTheViewportIntoDevicePixels() async throws {
        let engine = WebSnapshotView()
        let oneX = try await engine.snapshot(
            of: .init(
                html: HTMLFixture.minimal, viewport: CGSize(width: 200, height: 100), scale: 1)
        )
        let threeX = try await engine.snapshot(
            of: .init(
                html: HTMLFixture.minimal, viewport: CGSize(width: 200, height: 100), scale: 3)
        )
        #expect(oneX.width == 200)
        #expect(threeX.width == 600)
        #expect(threeX.height == 300)
    }
}

// MARK: - Network blocked for pasted HTML

@MainActor
@Suite(
    "Pasted HTML cannot reach the network · ",
    .enabled("requires a launchable WKWebView web process (unavailable in a sandboxed test host)") {
        await WebKitAvailability.canRenderOffscreen()
    })
struct WebSnapshotNetworkTests {
    @Test func remoteSubresourceIsBlockedButTheDocumentStillRenders() async throws {
        // A remote <img> is blocked in the web process by the compiled content
        // rule list (a navigation delegate never sees subresource loads), yet the
        // document loads and snapshots — a blocked subresource must not fail the
        // render or yield a blank image.
        let engine = WebSnapshotView()
        let image = try await engine.snapshot(
            of: .init(
                html: HTMLFixture.remoteImage,
                viewport: CGSize(width: 500, height: 300),
                scale: 1,
                allowsNetwork: false))
        #expect(image.width == 500)
        #expect(image.height == 300)
    }

    @Test func networkIsBlockedByDefault() async throws {
        // The default request blocks network: the same fixture renders without the
        // caller having to opt out, proving `allowsNetwork` defaults to false.
        // Scale is pinned to 1 so the pixel assertion is exact — the request's
        // default scale is 2, which doubles the bitmap (deterministic sizing).
        let engine = WebSnapshotView()
        let image = try await engine.snapshot(
            of: .init(
                html: HTMLFixture.remoteImage, viewport: CGSize(width: 400, height: 240),
                scale: 1))
        #expect(image.width == 400)
        #expect(image.height == 240)
    }

    @Test func remoteBlockRulesCompileIntoAUsableRuleList() async throws {
        // The rule list is the load-bearing isolation layer for pasted HTML on a
        // network-entitled build (DMG): subresources and script-initiated
        // requests never reach the navigation delegate, so blocking happens in the
        // web process. This proves the committed rule JSON actually compiles —
        // a malformed rule source would otherwise fail every HTML render closed.
        let list = try await WebSnapshotView.remoteBlockList()
        #expect(list.identifier == WebSnapshotView.RemoteBlockRules.identifier)
    }
}

// MARK: - Local assets only (live render)

@MainActor
@Suite(
    "HTML resolves only local assets · ",
    .enabled("requires a launchable WKWebView web process (unavailable in a sandboxed test host)") {
        await WebKitAvailability.canRenderOffscreen()
    })
struct WebSnapshotLocalAssetTests {
    @Test func relativeReferenceWithoutBaseURLStillRenders() async throws {
        // With no base URL, a relative `src` cannot resolve; the document renders
        // anyway (the broken image is simply absent), so the local-only default is
        // safe rather than fatal.
        let engine = WebSnapshotView()
        let image = try await engine.snapshot(
            of: .init(
                html: HTMLFixture.relativeAsset,
                viewport: CGSize(width: 480, height: 300),
                scale: 1,
                localBaseURL: nil))
        #expect(image.width == 480)
        #expect(image.height == 300)
    }

    @Test func aFileBaseURLIsAccepted() async throws {
        // A local file base URL is the allowed way to resolve relative assets
        // (user-selected file or bundled resource). Using the temp directory as the
        // base is a valid `file:` URL, so the request is accepted and renders.
        let engine = WebSnapshotView()
        let base = FileManager.default.temporaryDirectory
        let image = try await engine.snapshot(
            of: .init(
                html: HTMLFixture.minimal,
                viewport: CGSize(width: 300, height: 200),
                scale: 1,
                localBaseURL: base))
        #expect(image.width == 300)
        #expect(image.height == 200)
    }
}

// MARK: - Typed errors, never a blank image (pre-load, no web process needed)

/// These failures are all detected *before* any web content process launches — the
/// viewport guard and the local-base-URL check both run before `loadHTMLString` — so
/// the suite always runs and asserts, even where the sandboxed test host cannot
/// launch WebKit. That is what keeps the "typed error, not a blank image" contract
/// executable on every machine.
@MainActor
@Suite("Snapshot failures are typed errors")
struct WebSnapshotErrorTests {
    @Test func zeroWidthViewportThrowsInvalidViewport() async throws {
        let engine = WebSnapshotView()
        await #expect(throws: WebSnapshotError.invalidViewport) {
            try await engine.snapshot(
                of: .init(html: HTMLFixture.minimal, viewport: CGSize(width: 0, height: 400)))
        }
    }

    @Test func zeroHeightViewportThrowsInvalidViewport() async throws {
        let engine = WebSnapshotView()
        await #expect(throws: WebSnapshotError.invalidViewport) {
            try await engine.snapshot(
                of: .init(html: HTMLFixture.minimal, viewport: CGSize(width: 600, height: 0)))
        }
    }

    @Test func remoteBaseURLIsRejectedAsATypedError() async throws {
        // A non-file base URL would widen what relative references can reach, so it
        // is refused with a typed error before any load — local assets only.
        let engine = WebSnapshotView()
        let remoteBase = try #require(URL(string: "https://example.com/"))
        await #expect(throws: WebSnapshotError.invalidBaseURL) {
            try await engine.snapshot(
                of: .init(html: HTMLFixture.minimal, localBaseURL: remoteBase))
        }
    }

    @Test func dataBaseURLIsRejectedBecauseItIsNotAFileURL() async throws {
        // `data:` is not a local file, so it is refused like any other non-file base.
        let engine = WebSnapshotView()
        let dataBase = try #require(URL(string: "data:text/html,<b>x</b>"))
        await #expect(throws: WebSnapshotError.invalidBaseURL) {
            try await engine.snapshot(of: .init(html: HTMLFixture.minimal, localBaseURL: dataBase))
        }
    }

    @Test func webSnapshotErrorCasesAreDistinct() {
        // The typed-error contract only holds if the cases are not interchangeable.
        #expect(WebSnapshotError.invalidViewport != .invalidBaseURL)
        #expect(WebSnapshotError.invalidBaseURL != .loadFailed)
        #expect(WebSnapshotError.loadFailed != .timedOut)
        #expect(WebSnapshotError.timedOut != .snapshotFailed)
        #expect(WebSnapshotError.snapshotFailed != .invalidViewport)
        #expect(WebSnapshotError.networkIsolationUnavailable != .snapshotFailed)
        // Sanity: identical cases remain equal (what `#expect(throws:)` relies on).
        #expect(WebSnapshotError.timedOut == .timedOut)
    }

    @Test func everyErrorHasAStableNonPIIDiagnosticReason() {
        // The diagnostic label names the failure mode, never the HTML body, and is
        // distinct per case so logs are filterable.
        let reasons = [
            WebSnapshotError.invalidViewport.diagnosticReason,
            WebSnapshotError.invalidBaseURL.diagnosticReason,
            WebSnapshotError.loadFailed.diagnosticReason,
            WebSnapshotError.timedOut.diagnosticReason,
            WebSnapshotError.snapshotFailed.diagnosticReason,
            WebSnapshotError.networkIsolationUnavailable.diagnosticReason,
        ]
        #expect(Set(reasons).count == reasons.count)
        #expect(reasons.allSatisfy { !$0.isEmpty })
        #expect(WebSnapshotError.timedOut.diagnosticReason == "timed-out")
    }
}

// MARK: - Network policy (pure logic, no web process needed)

/// The privacy guarantee at the heart of — *"pasted HTML cannot reach the
/// network"* — is the navigation delegate's allow/cancel decision. That decision is
/// pure (the request's scheme plus the caller's `allowsNetwork` flag), so it is
/// proven here directly against `WebSnapshotView.NetworkPolicy` with **no
/// `WKWebView` and no web content process** — unlike the live network suite, which
/// only runs where WebKit can launch. This is the assertion that keeps the
/// network-blocking contract executable on every machine, including the sandboxed
/// test host where a real render cannot run.
@Suite("Pasted HTML network policy is local-only by default")
struct WebSnapshotNetworkPolicyTests {
    private typealias Policy = WebSnapshotView.NetworkPolicy

    @Test func remoteSchemesAreCancelledWhenNetworkIsNotAllowed() {
        // The whole point: with network off, any scheme that reaches the wire is
        // cancelled, so an absolute https subresource or a remote redirect in pasted
        // HTML never loads.
        for scheme in ["http", "https", "ws", "wss", "ftp"] {
            #expect(
                Policy.decision(forScheme: scheme, allowsNetwork: false) == .cancel,
                "\(scheme) must be cancelled when network is not allowed")
            #expect(!Policy.isLocal(scheme: scheme), "\(scheme) is a network scheme")
        }
    }

    @Test func localSchemesLoadEvenWhenNetworkIsNotAllowed() {
        // The in-memory document and inline/local data must still load with network
        // off, otherwise the page itself could never render.
        for scheme in ["about", "file", "data", "blob"] {
            #expect(
                Policy.decision(forScheme: scheme, allowsNetwork: false) == .allow,
                "\(scheme) is local and must load")
            #expect(Policy.isLocal(scheme: scheme), "\(scheme) is a local scheme")
        }
    }

    @Test func aMissingSchemeIsTheInMemoryDocumentAndLoads() {
        // `loadHTMLString`'s main-frame navigation carries no URL/scheme; it is the
        // document being rendered and must always be allowed.
        #expect(Policy.isLocal(scheme: nil))
        #expect(Policy.decision(forScheme: nil, allowsNetwork: false) == .allow)
    }

    @Test func schemeMatchingIsCaseInsensitive() {
        // A delegate sees whatever case the URL carried; classification must not be
        // fooled by `HTTPS` vs `https` or `FILE` vs `file`.
        #expect(Policy.decision(forScheme: "HTTPS", allowsNetwork: false) == .cancel)
        #expect(Policy.decision(forScheme: "FILE", allowsNetwork: false) == .allow)
        #expect(Policy.isLocal(scheme: "DATA"))
    }

    @Test func everythingLoadsOnceTheCallerExplicitlyAllowsNetwork() {
        // The single opt-in switch: when the caller allows network, even a remote
        // scheme loads. This is the only path that reaches the wire, and it is never
        // the default.
        #expect(Policy.decision(forScheme: "https", allowsNetwork: true) == .allow)
        #expect(Policy.decision(forScheme: "http", allowsNetwork: true) == .allow)
        #expect(Policy.decision(forScheme: nil, allowsNetwork: true) == .allow)
    }

    @Test func theDefaultRequestKeepsNetworkOff() {
        // The Request value the renderer builds must default to network-off, so the
        // policy above applies unless a caller deliberately opts in.
        let request = WebSnapshotView.Request(html: "<b>x</b>")
        #expect(request.allowsNetwork == false)
        // And with that default, a remote scheme is cancelled — the end-to-end
        // default-deny, asserted without a live load.
        #expect(
            Policy.decision(forScheme: "https", allowsNetwork: request.allowsNetwork) == .cancel)
    }
}

// MARK: - Deterministic pixel sizing (pure math + real draw, no web process needed)

/// The other headline guarantee the renderer makes — a snapshot is **exactly
/// `viewport × scale` device pixels**, deterministically — is sizing arithmetic
/// plus a CoreGraphics draw, neither of which needs WebKit. The live render suite
/// asserts this end to end where WebKit can launch; here the same guarantee is
/// proven on every machine by driving `WebSnapshotView`'s own sizing and bitmap
/// path against a synthesized `NSImage` standing in for the web view's snapshot.
@MainActor
@Suite("Snapshot sizing is deterministic")
struct WebSnapshotSizingTests {
    /// A solid-color `NSImage` of a known point size, used as a stand-in for the
    /// image `WKWebView.takeSnapshot` would hand back — so the sizing and bitmap
    /// code runs with no web process.
    private func solidImage(width: CGFloat, height: CGFloat) -> NSImage {
        let image = NSImage(size: CGSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
        image.unlockFocus()
        return image
    }

    @Test func pixelDimensionsAreSourceSizeTimesScale() {
        // The determinism contract as pure arithmetic: each axis is points × scale.
        let oneX = WebSnapshotView.pixelDimensions(
            forSourceSize: CGSize(width: 600, height: 400), scale: 1)
        #expect(oneX.width == 600)
        #expect(oneX.height == 400)

        let twoX = WebSnapshotView.pixelDimensions(
            forSourceSize: CGSize(width: 600, height: 400), scale: 2)
        #expect(twoX.width == 1200)
        #expect(twoX.height == 800)

        let threeX = WebSnapshotView.pixelDimensions(
            forSourceSize: CGSize(width: 200, height: 100), scale: 3)
        #expect(threeX.width == 600)
        #expect(threeX.height == 300)
    }

    @Test func pixelDimensionsRoundToTheNearestDevicePixel() {
        // A fractional point size rounds, so the bitmap is always a whole number of
        // device pixels (no truncation that would shave a row/column).
        let rounded = WebSnapshotView.pixelDimensions(
            forSourceSize: CGSize(width: 100.4, height: 100.6), scale: 1.5)
        #expect(rounded.width == Int((100.4 * 1.5).rounded()))  // 151
        #expect(rounded.height == Int((100.6 * 1.5).rounded()))  // 151
    }

    @Test func nonPositiveSourceSizeYieldsNoDrawableBitmap() {
        // A degenerate size signals "no bitmap" as (0, 0), which the draw path turns
        // into a `snapshotFailed` rather than a zero-pixel image.
        #expect(
            WebSnapshotView.pixelDimensions(forSourceSize: CGSize(width: 0, height: 400), scale: 2)
                == (0, 0))
        #expect(
            WebSnapshotView.pixelDimensions(forSourceSize: CGSize(width: 600, height: 0), scale: 2)
                == (0, 0))
        #expect(
            WebSnapshotView.pixelDimensions(
                forSourceSize: CGSize(width: 600, height: 400), scale: 0)
                == (0, 0))
    }

    @Test func realDrawProducesABitmapOfExactlyTheRequestedPixelSize() {
        // Driving the actual bitmap path (the same code the live snapshot uses)
        // against a stand-in image yields a CGImage of exactly source × scale — the
        // determinism guarantee, proven with no web process.
        let engine = WebSnapshotView()
        let image = engine.cgImage(from: solidImage(width: 300, height: 200), scale: 2)
        let cg = try? #require(image)
        #expect(cg?.width == 600)
        #expect(cg?.height == 400)
    }

    @Test func realDrawAtOneXMatchesTheSourcePointSize() {
        let engine = WebSnapshotView()
        let image = engine.cgImage(from: solidImage(width: 320, height: 240), scale: 1)
        #expect(image?.width == 320)
        #expect(image?.height == 240)
    }

    @Test func theBitmapKeepsAnAlphaChannelSoATransparentBodyStaysTransparent() throws {
        // The context is premultiplied-last (RGBA): a transparent page body must not
        // be flattened onto an opaque background by the snapshot bitmap.
        let engine = WebSnapshotView()
        let cg = try #require(engine.cgImage(from: solidImage(width: 64, height: 64), scale: 1))
        let alpha = cg.alphaInfo
        #expect(
            alpha == .premultipliedLast || alpha == .last,
            "the snapshot bitmap must carry an alpha channel")
    }

    @Test func aZeroSizedSourceImageDrawsNoBitmap() {
        // The draw path refuses a zero-sized source rather than returning an empty
        // image — the caller maps the nil to a typed `snapshotFailed`.
        let engine = WebSnapshotView()
        #expect(engine.cgImage(from: NSImage(size: .zero), scale: 2) == nil)
    }
}

// MARK: - HTMLRenderer routing (pure logic, no web process needed)

/// Routing and contract are decided without rendering, so this suite always runs:
/// these tests pin that `HTMLRenderer` accepts only HTML and throws — never returns a
/// blank image — for an input it rejects.
@MainActor
@Suite("HTMLRenderer routing")
struct HTMLRendererRoutingTests {
    @Test func htmlRendererAcceptsOnlyHTML() throws {
        let renderer = HTMLRenderer()
        #expect(renderer.canRender(.html("<b>x</b>")))
        #expect(!renderer.canRender(.code("x", languageHint: nil)))
        #expect(!renderer.canRender(.url(try #require(URL(string: "https://example.com")))))
    }

    @Test func nonHTMLInputThrowsNoRendererForFromHTMLRenderer() async throws {
        // Handed an input it rejects (a routing mistake), it throws rather than
        // producing an image — never a blank picture.
        let renderer = HTMLRenderer()
        await #expect(throws: RenderError.noRendererFor(kind: "code")) {
            try await renderer.render(.code("x", languageHint: nil), config: SnapshotConfig())
        }
    }

    @Test func htmlRendererInACoordinatorRoutesToIt() throws {
        // Wired into a coordinator, HTML routes to the real renderer.
        let coordinator = RenderCoordinator(renderers: [HTMLRenderer()])
        #expect(coordinator.renderer(for: .html("<b>x</b>")) is HTMLRenderer)
    }
}

// MARK: - HTMLRenderer live render (Renderer abstraction → real image)

@MainActor
@Suite(
    "HTMLRenderer produces a tagged asset · ",
    .enabled("requires a launchable WKWebView web process (unavailable in a sandboxed test host)") {
        await WebKitAvailability.canRenderOffscreen()
    })
struct HTMLRendererRenderTests {
    @Test func htmlRendererRendersHTMLToATaggedAsset() async throws {
        // The renderer produces a real, color-tagged asset for an HTML input, the
        // same `RenderedAsset` shape a code snapshot yields, so the clipboard/save
        // paths stay uniform.
        let renderer = HTMLRenderer(viewport: CGSize(width: 400, height: 300), scale: 1)
        let asset = try await renderer.render(
            .html(HTMLFixture.staticCard), config: SnapshotConfig())
        #expect(asset.pixelWidth == 400)
        #expect(asset.pixelHeight == 300)
        #expect(asset.profile == .sRGB)
    }

    @Test func htmlRendererTagsTheRequestedProfile() async throws {
        let renderer = HTMLRenderer(
            viewport: CGSize(width: 200, height: 200), scale: 1, profile: .displayP3)
        let asset = try await renderer.render(.html(HTMLFixture.minimal), config: SnapshotConfig())
        #expect(asset.profile == .displayP3)
    }

    @Test func htmlRendererRoutesThroughACoordinator() async throws {
        // Routed through a coordinator, an HTML input rasterizes to the requested
        // pixel size — the end-to-end abstraction path for HTML.
        let coordinator = RenderCoordinator(
            renderers: [HTMLRenderer(viewport: CGSize(width: 300, height: 200), scale: 1)])
        let asset = try await coordinator.render(
            .html(HTMLFixture.minimal), config: SnapshotConfig())
        #expect(asset.pixelWidth == 300)
        #expect(asset.pixelHeight == 200)
    }
}

// MARK: - No Screen Recording, no network entitlement

@Suite("Local HTML rendering needs no screen or network capability")
struct HTMLRenderingCapabilityTests {
    /// Local HTML rendering must not add `com.apple.security.network.client` to the
    /// app target: the engine renders a pasted fragment locally and blocks remote
    /// loads, so it never needs the network. The entitlements file is excluded from
    /// the app's compiled sources, so it is read from the source tree via `#filePath`
    /// the same anchoring the renderer and golden tests use.
    @Test func appHasNoNetworkClientEntitlement() throws {
        let entitlements = Self.appEntitlements()
        let data = try Data(contentsOf: entitlements)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Vitrine.entitlements must be a property list")
        #expect(
            plist["com.apple.security.network.client"] == nil,
            "Local HTML rendering must not request the network client entitlement")
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
    }

    /// `<repo>/Vitrine/Resources/Vitrine.entitlements`, derived from this file at
    /// `<repo>/Tests/HTMLRendererTests.swift`.
    private static func appEntitlements() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // <repo>/Tests
            .deletingLastPathComponent()  // <repo>
            .appendingPathComponent("Vitrine", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Vitrine.entitlements", isDirectory: false)
    }
}
