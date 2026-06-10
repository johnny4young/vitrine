import CoreGraphics
import Foundation
import OSLog
import WebKit

/// Renders a self-contained HTML string to a `CGImage` in an offscreen
/// `WKWebView` (CS-042). This is the local, network-free engine behind
/// `HTMLRenderer`: it owns the web view's lifecycle, pins a deterministic
/// viewport, blocks remote loads for pasted HTML by default, and turns the loaded
/// page into a bitmap via `WKWebView.takeSnapshot` — so no Screen Recording
/// permission is ever involved (the view is never on screen and nothing reads the
/// display).
///
/// ## Privacy and isolation
///
/// The engine is built for *controlled* HTML (clipboard or a user-selected file),
/// not arbitrary web pages — those are CS-043's URL renderer with its own explicit
/// network mode. Two defaults keep a pasted fragment local:
///
/// 1. **No base URL.** HTML loads with `baseURL: nil` (unless the caller opts into
///    a `localBaseURL`), so relative references like `<img src="logo.png">` cannot
///    resolve to anything — there is no document origin to resolve them against.
/// 2. **Remote loads are blocked in the web process.** A compiled
///    `WKContentRuleList` (see `RemoteBlockRules`) blocks every `http(s)`/`ws(s)`
///    request — subresources (`<img>`, `<script>`, stylesheets), `fetch`/XHR from
///    scripts, and frame loads alike. A navigation delegate additionally cancels
///    remote top-level redirects. The rule list is the load-bearing layer: a
///    navigation delegate alone only sees *frame navigations*, never subresource
///    requests, so it could not keep an absolute `https://…` image off the wire on
///    a build that carries the network entitlement (the direct-download channel,
///    CS-064). If the rule list cannot be compiled the render fails closed with
///    `.networkIsolationUnavailable` rather than rendering unisolated.
///
/// The data store is always `WKWebsiteDataStore.nonPersistent()`, so nothing the
/// page touches (cookies, caches, local storage) is written to disk or shared with
/// any other web view.
///
/// ## Concurrency
///
/// `WKWebView` is main-actor bound, and this whole type runs on the main actor
/// (the module's default isolation). `snapshot(of:)` is `async`: it loads the HTML,
/// waits for the load to finish (or fail) via a retained navigation delegate, then
/// rasterizes. The work is bounded by `timeout` so a script that never settles
/// cannot hang the caller — it surfaces a typed `.timedOut`, never a blank image.
@MainActor
struct WebSnapshotView {
    /// The render request: the HTML to draw, the viewport to draw it in, and the
    /// isolation policy (network and local base URL). Carrying these as a value
    /// keeps `snapshot(of:)` a pure function of its input, which is what the tests
    /// drive.
    struct Request {
        /// The HTML document or fragment to render. Carried as a string so the
        /// input itself implies no file or network access.
        var html: String

        /// The viewport the page is laid out and snapshotted in. Fixed so the same
        /// HTML always produces the same pixel size — the determinism the
        /// acceptance criteria require.
        var viewport: CGSize = CGSize(width: 1200, height: 630)

        /// Output scale (1 = device pixels equal points). The rendered image is
        /// `viewport × scale` pixels. Defaults to 2 to match `ExportManager`.
        var scale: CGFloat = 2

        /// Whether remote (network) loads are allowed. `false` (the default) blocks
        /// every request to a remote scheme/host, so pasted HTML stays local unless
        /// the user explicitly opts in. CS-043 owns the real URL network mode; this
        /// flag exists so the engine has a single, testable allow switch.
        var allowsNetwork: Bool = false

        /// An optional **local** base URL for resolving relative asset references,
        /// limited to a user-selected file or a bundled resource. `nil` (the
        /// default) loads with no base URL, so relative references cannot resolve.
        /// A non-`file:` base URL is rejected by `snapshot(of:)` as a typed error
        /// rather than silently widening the page's reach.
        var localBaseURL: URL?

        /// How long to wait for the page to finish loading before failing with
        /// `.timedOut`. Bounds a runaway page so the caller never hangs.
        var timeout: Duration = .seconds(10)

        init(
            html: String,
            viewport: CGSize = CGSize(width: 1200, height: 630),
            scale: CGFloat = 2,
            allowsNetwork: Bool = false,
            localBaseURL: URL? = nil,
            timeout: Duration = .seconds(10)
        ) {
            self.html = html
            self.viewport = viewport
            self.scale = scale
            self.allowsNetwork = allowsNetwork
            self.localBaseURL = localBaseURL
            self.timeout = timeout
        }
    }

    /// Renders `request` to a `CGImage`, or throws a typed `WebSnapshotError`.
    ///
    /// The web view is created per call, configured for isolation, loads the HTML,
    /// and is torn down before this returns — there is no shared mutable web-view
    /// state between renders. A failure at any stage (an invalid base URL, a load
    /// error such as a blocked remote redirect, a timeout, or a snapshot that
    /// yields no image) throws, so a caller never receives a blank picture.
    func snapshot(of request: Request) async throws -> CGImage {
        guard request.viewport.width > 0, request.viewport.height > 0 else {
            throw WebSnapshotError.invalidViewport
        }
        // A base URL is only ever a local file. Anything else (an http(s) origin,
        // a data: URL) would widen what relative references can reach, so reject it
        // rather than load it.
        if let base = request.localBaseURL, !base.isFileURL {
            throw WebSnapshotError.invalidBaseURL
        }

        let configuration = WKWebViewConfiguration()
        // Never persist anything the page touches (cookies, caches, storage).
        configuration.websiteDataStore = .nonPersistent()

        if !request.allowsNetwork {
            // The content rule list is what actually keeps pasted HTML off the
            // network: it blocks remote subresources and script-initiated requests
            // inside the web process, which the navigation delegate below never
            // sees. Failing to obtain it fails the render (closed), preserving the
            // CS-042 promise even on the network-entitled direct-download build.
            configuration.userContentController.add(try await Self.remoteBlockList())
        }

        let frame = CGRect(origin: .zero, size: request.viewport)
        let webView = WKWebView(frame: frame, configuration: configuration)
        // The view is laid out at the deterministic viewport but never added to a
        // window or shown — the snapshot reads the view's own layer, not the screen,
        // so no Screen Recording permission is involved.
        webView.frame = frame

        // The delegate enforces the network policy and reports load completion. It
        // is retained for the lifetime of this call (the web view holds it weakly),
        // and torn down with the web view when the function returns.
        let coordinator = NavigationCoordinator(allowsNetwork: request.allowsNetwork)
        webView.navigationDelegate = coordinator
        defer {
            webView.navigationDelegate = nil
            webView.stopLoading()
        }

        webView.loadHTMLString(request.html, baseURL: request.localBaseURL)

        // Wait for the load to settle (or fail), bounded by the timeout. A page that
        // never finishes surfaces `.timedOut` instead of hanging the caller.
        try await coordinator.waitForLoad(timeout: request.timeout)

        let snapshotConfiguration = WKSnapshotConfiguration()
        snapshotConfiguration.rect = frame
        // Pin the output width in points; the engine multiplies by `scale` to get
        // device pixels, so the bitmap is exactly `viewport × scale`.
        snapshotConfiguration.snapshotWidth = NSNumber(value: Double(request.viewport.width))
        snapshotConfiguration.afterScreenUpdates = true

        let image: NSImage
        do {
            image = try await webView.takeSnapshot(configuration: snapshotConfiguration)
        } catch {
            Log.render.error(
                "HTML snapshot failed during rasterization (\((error as NSError).domain, privacy: .public))"
            )
            throw WebSnapshotError.snapshotFailed
        }

        guard let cgImage = cgImage(from: image, scale: request.scale) else {
            Log.render.error("HTML snapshot produced no CGImage")
            throw WebSnapshotError.snapshotFailed
        }
        return cgImage
    }

    /// The exact device-pixel dimensions a snapshot of `sourceSize` points renders
    /// to at `scale`: each axis is `size × scale`, rounded to the nearest integer.
    /// This is the determinism guarantee CS-042 requires, isolated as pure
    /// arithmetic so it is assertable without a web process. `(0, 0)` for a
    /// non-positive input signals "no drawable bitmap".
    static func pixelDimensions(
        forSourceSize sourceSize: CGSize, scale: CGFloat
    )
        -> (width: Int, height: Int)
    {
        let width = Int((sourceSize.width * scale).rounded())
        let height = Int((sourceSize.height * scale).rounded())
        guard width > 0, height > 0 else { return (0, 0) }
        return (width, height)
    }

    /// Extracts a `CGImage` from the snapshot `NSImage`, drawing it into a
    /// fixed-size sRGB-shaped bitmap context at `scale` so the result is exactly
    /// `viewport × scale` device pixels regardless of the backing screen. The
    /// context keeps an alpha channel so a transparent page body stays transparent.
    func cgImage(from image: NSImage, scale: CGFloat) -> CGImage? {
        let (pixelWidth, pixelHeight) = Self.pixelDimensions(
            forSourceSize: image.size, scale: scale)
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        var proposedRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        guard
            let cgImage = image.cgImage(
                forProposedRect: &proposedRect, context: nil, hints: nil)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        return context.makeImage()
    }
}

extension WebSnapshotView {
    /// The content rules that keep pasted HTML off the network (CS-042).
    ///
    /// `WKNavigationDelegate` only decides *frame navigations*; subresource loads
    /// (`<img>`, `<script>`, stylesheets) and script-initiated requests
    /// (`fetch`/XHR/WebSocket) never reach it. This compiled rule list runs inside
    /// the web process and blocks every request to a network scheme, which is the
    /// only supported way to guarantee "pasted HTML cannot reach the network" on a
    /// build that carries the network entitlement (the direct-download DMG,
    /// CS-064). Local schemes (`file`, `data`, `blob`, `about`) are untouched, so
    /// inline images and a user-selected local base URL keep working.
    enum RemoteBlockRules {
        /// The store identifier for the compiled rules. Versioned so a future rule
        /// change recompiles instead of reusing a stale cached list.
        static let identifier = "vitrine-block-remote-v1"

        /// The rule source: block everything that can reach the wire. WebKit can
        /// only load remote content over `http(s)`/`ws(s)`, so matching those
        /// schemes blocks the entire network surface without touching local ones.
        static let json = """
            [
              { "trigger": { "url-filter": "^https?://" }, "action": { "type": "block" } },
              { "trigger": { "url-filter": "^wss?://" }, "action": { "type": "block" } }
            ]
            """
    }

    /// The compiled remote-block rule list, compiled at most once per process.
    private static var cachedRemoteBlockList: WKContentRuleList?

    /// Returns the compiled remote-block rule list, compiling and caching it on
    /// first use. Throws `.networkIsolationUnavailable` when WebKit cannot provide
    /// a compiled list — the caller must fail the render rather than proceed
    /// without isolation.
    static func remoteBlockList() async throws -> WKContentRuleList {
        if let cachedRemoteBlockList { return cachedRemoteBlockList }
        guard let store = WKContentRuleListStore.default() else {
            throw WebSnapshotError.networkIsolationUnavailable
        }
        do {
            guard
                let list = try await store.compileContentRuleList(
                    forIdentifier: RemoteBlockRules.identifier,
                    encodedContentRuleList: RemoteBlockRules.json)
            else {
                throw WebSnapshotError.networkIsolationUnavailable
            }
            cachedRemoteBlockList = list
            return list
        } catch {
            Log.render.error(
                "Remote-block rule list failed to compile (\((error as NSError).domain, privacy: .public))"
            )
            throw WebSnapshotError.networkIsolationUnavailable
        }
    }

    /// The pure load-policy decision behind the navigation delegate: given a
    /// request's scheme and whether the caller allowed network, should the load
    /// proceed or be cancelled?
    ///
    /// Extracted from `NavigationCoordinator` so the privacy guarantee at the heart
    /// of CS-042 — "pasted HTML cannot reach the network" — is a pure function that
    /// tests assert directly, with no `WKWebView` and no web content process. The
    /// delegate is a thin adapter that pulls the scheme off the live navigation and
    /// defers to this.
    enum NetworkPolicy {
        /// Whether a request should be allowed to load or cancelled.
        enum Decision: Equatable {
            case allow
            case cancel
        }

        /// Schemes that never reach the network and are therefore always allowed:
        /// the in-memory `loadHTMLString` document (`about`), and local/inline data
        /// (`file`, `data`, `blob`). A request with no scheme is the in-memory
        /// document itself and is treated as local.
        static let localSchemes: Set<String> = ["about", "file", "data", "blob"]

        /// Whether `scheme` is a local (non-network) scheme. A `nil` scheme is the
        /// in-memory `loadHTMLString` navigation, which is local.
        static func isLocal(scheme: String?) -> Bool {
            guard let scheme = scheme?.lowercased() else { return true }
            return localSchemes.contains(scheme)
        }

        /// The decision for a request with `scheme`, given the caller's
        /// `allowsNetwork` flag. When network is allowed, everything loads; when it
        /// is not, only local schemes load and any remote scheme is cancelled — the
        /// rule that blocks an absolute `https://…` subresource or a top-level
        /// redirect for pasted HTML.
        static func decision(forScheme scheme: String?, allowsNetwork: Bool) -> Decision {
            if allowsNetwork { return .allow }
            return isLocal(scheme: scheme) ? .allow : .cancel
        }
    }
}

/// Why an HTML snapshot did not produce an image, as a typed error rather than a
/// blank picture (CS-042 acceptance: "Snapshot failure returns a typed error, not
/// a blank image"). Each case names a distinct, non-PII failure mode so a caller
/// can offer the right recovery and tests can assert the exact reason.
enum WebSnapshotError: Error, Equatable {
    /// The requested viewport had a non-positive dimension.
    case invalidViewport

    /// A base URL was supplied that is not a local `file:` URL. Local asset
    /// references are limited to user-selected files or bundled resources, so a
    /// remote or non-file base URL is refused.
    case invalidBaseURL

    /// The page failed to load — for example a blocked remote redirect, malformed
    /// HTML that WebKit refused, or a provisional navigation error.
    case loadFailed

    /// The page did not finish loading within the request's timeout.
    case timedOut

    /// The page loaded but `takeSnapshot` yielded no usable image.
    case snapshotFailed

    /// The remote-block content rule list could not be compiled, so the engine
    /// refused to render pasted HTML without its network isolation (CS-042). The
    /// render fails closed instead of loading the page unisolated.
    case networkIsolationUnavailable
}

/// Drives one offscreen load: enforces the network policy and signals when the
/// load has settled or failed. A fresh instance is used per snapshot, so it holds
/// no state across renders.
///
/// `WKNavigationDelegate` is an `NSObjectProtocol`, so this is an `NSObject`
/// subclass; its callbacks arrive on the main actor (where the web view lives),
/// matching the module's default isolation.
@MainActor
private final class NavigationCoordinator: NSObject, WKNavigationDelegate {
    /// Whether remote loads are permitted. When `false`, any request to a remote
    /// scheme/host is cancelled.
    private let allowsNetwork: Bool

    /// The continuation resumed when the load finishes, fails, or times out.
    /// Resumed exactly once; cleared on resume so neither a late navigation
    /// callback nor the timeout can resume it twice.
    private var loadContinuation: CheckedContinuation<Void, Error>?

    /// Set once the navigation has settled so `waitForLoad` can return immediately
    /// if the load completed before the caller began waiting (a fast, fully local
    /// document can finish before the `await` suspends).
    private var outcome: Result<Void, Error>?

    /// The armed timeout. It resumes the wait with `.timedOut` if the load has not
    /// settled in time, and is cancelled the moment the load does settle so a
    /// completed render never trips the timer.
    private var timeoutTask: Task<Void, Never>?

    init(allowsNetwork: Bool) {
        self.allowsNetwork = allowsNetwork
    }

    /// Suspends until the page finishes loading or fails, or until `timeout`
    /// elapses (whichever comes first). Throws `WebSnapshotError.timedOut` on the
    /// timeout and `WebSnapshotError.loadFailed` on a navigation failure.
    ///
    /// The timeout is a sibling `Task` that calls back onto this main-actor object;
    /// a continuation (rather than a task group) keeps the region-based isolation
    /// simple — `self` is the only shared state and it is `@MainActor`.
    func waitForLoad(timeout: Duration) async throws {
        // If the load already settled before we started waiting, return its result
        // without suspending.
        if let outcome {
            self.outcome = nil
            try outcome.get()
            return
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                // The load did not settle in time; fail the wait through the same
                // single-resume guard a real navigation result uses.
                self?.resume(.failure(WebSnapshotError.timedOut))
            }
        }
    }

    /// Resumes the load continuation exactly once, recording the outcome for a
    /// caller that has not started waiting yet, and disarming the timeout.
    private func resume(_ result: Result<Void, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let continuation = loadContinuation {
            loadContinuation = nil
            continuation.resume(with: result)
        } else {
            // The result arrived before `waitForLoad` suspended; stash it so the
            // subsequent await returns it immediately.
            outcome = result
        }
    }

    // MARK: WKNavigationDelegate

    /// Gates every *frame navigation* — the `loadHTMLString` document itself (an
    /// `about:blank`-style main-frame navigation with no URL, always allowed),
    /// remote top-level redirects, and iframe loads. Subresource requests never
    /// reach a navigation delegate; those are blocked by the compiled
    /// `RemoteBlockRules` content rule list installed on the configuration. This
    /// delegate is the second, navigation-level layer of the same policy.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // The decision is pure logic (scheme + the allow flag); the delegate only
        // pulls the scheme off the live navigation. See `NetworkPolicy`.
        let scheme = navigationAction.request.url?.scheme
        switch WebSnapshotView.NetworkPolicy.decision(
            forScheme: scheme, allowsNetwork: allowsNetwork)
        {
        case .allow:
            decisionHandler(.allow)
        case .cancel:
            Log.render.error("Blocked a remote request from pasted HTML (network not allowed)")
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resume(.success(()))
    }

    func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        Log.render.error(
            "HTML page navigation failed (\((error as NSError).domain, privacy: .public))")
        resume(.failure(WebSnapshotError.loadFailed))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Log.render.error(
            "HTML page provisional navigation failed (\((error as NSError).domain, privacy: .public))"
        )
        resume(.failure(WebSnapshotError.loadFailed))
    }
}
