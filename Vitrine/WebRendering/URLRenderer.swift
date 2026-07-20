import CoreGraphics
import Foundation
import OSLog
import WebKit

/// Captures a user-provided URL by loading the page **locally** in an offscreen
/// `WKWebView` and rasterizing it.
///
/// URL screenshots are part of web capture, but they keep Vitrine's privacy promise:
/// the page is loaded on this Mac and turned into a bitmap on-device — there is
/// **no remote render service**. The renderer slots into the existing `Renderer`
/// abstraction so a coordinator routes a `.url` input here exactly as it
/// routes code to `CodeRenderer` and HTML to `HTMLRenderer`.
///
/// ## Safety gate
///
/// Two gates stand in front of any load:
///
/// 1. **The network entitlement.** URL capture is disabled until the app target
///    carries `com.apple.security.network.client`; without it the renderer throws
///    `RenderError.urlCaptureDisabled` before touching WebKit, because a sandboxed
///    build with no network entitlement cannot reach a remote page anyway. The network-free
///    distribution ships without the entitlement, so this renderer remains unavailable there.
/// 2. **URL validation.** Only `http`/`https` URLs are accepted; `file:`, `data:`,
///    `javascript:`, private localhost, and malformed URLs are refused as typed
///    `URLValidationError`s mapped to `RenderError.renderFailed`. Validation runs
///    even when the input already carries a `URL`, so a malformed or non-web URL
///    that reached classification is still rejected here.
///
/// ## Privacy defaults
///
/// The offscreen engine uses `WKWebsiteDataStore.nonPersistent()` by default, so
/// cookies, caches, and local storage live only for the single render; cookies and
/// persistent website data are opt-in only (`WebSnapshotConfig.DataStoreMode`). The
/// web view is never added to a window, so the snapshot reads the view's own layer
/// and no Screen Recording permission is involved.
struct URLRenderer: Renderer {
    /// Output scale (1/2/3), matching `ExportManager`'s default.
    var scale: CGFloat = 2

    /// The viewport preset the page is laid out in. Defaults to Open Graph's 1200×630,
    /// with desktop, full-HD, mobile, and custom alternatives.
    var viewportPreset: WebSnapshotConfig.ViewportPreset = .openGraph

    /// Whether to capture the visible viewport or the full scrollable page.
    /// `.visibleViewport` by default — the deterministic, preset-sized capture.
    var captureMode: WebSnapshotConfig.CaptureMode = .visibleViewport

    /// How long, and on what signal, to wait before snapshotting.
    /// `.domContentLoaded` by default — snapshot as soon as the load settles.
    var waitStrategy: WebSnapshotConfig.WaitStrategy = .domContentLoaded

    /// The memory- and time-safety ceilings applied to every capture.
    /// Always applied; bounds the captured page height and the total wait.
    var safetyCaps: WebSnapshotConfig.SafetyCaps = .standard

    /// Color profile to tag the output with — sRGB by default.
    var profile: ColorProfile = .sRGB

    /// What the web view may persist. `.nonPersistent` by default; `.persistent` is
    /// an explicit opt-in that enables cookies and persistent website data.
    var dataStoreMode: WebSnapshotConfig.DataStoreMode = .nonPersistent

    /// Whether this capture may reach this Mac's loopback interface. Default-off and
    /// deliberately narrower than access to local or private networks.
    var allowsLoopbackCapture = false

    /// Whether the build is permitted to reach the network for a capture. Injectable
    /// so the gate is testable without an entitlement; defaults to the running app's
    /// real entitlement, so production behavior matches the build's capabilities.
    var isNetworkCaptureEnabled: Bool = NetworkCapability.isURLCaptureEnabled

    /// The offscreen engine that actually loads and rasterizes the page. Injectable
    /// for tests; defaults to the real WebKit-backed engine.
    var engine: URLSnapshotEngine = .init()

    /// Accepts only the URL input; code and HTML are handled by their own renderers.
    func canRender(_ input: CaptureInput) -> Bool {
        if case .url = input { return true }
        return false
    }

    /// Renders a `.url` input to a `RenderedAsset` by loading the page locally.
    ///
    /// Order of operations: confirm the network entitlement, validate the URL into a
    /// `WebSnapshotConfig` (which can only hold an approved `http`/`https` URL),
    /// load it offscreen with the chosen data-store mode, then normalize and tag the
    /// bitmap with `profile` so a URL snapshot flows through the same
    /// clipboard/save/share paths as a code snapshot. Any failure throws a typed
    /// error — never a blank image.
    func render(_ input: CaptureInput, config: SnapshotConfig) async throws -> RenderedAsset {
        guard case .url(let url) = input else {
            throw RenderError.noRendererFor(kind: input.diagnosticKind)
        }

        // Gate 1: the network entitlement. Without it, URL capture is disabled — a
        // sandboxed build with no network entitlement cannot load a remote page, so
        // refuse early with a clear, typed reason instead of failing inside WebKit.
        guard isNetworkCaptureEnabled else {
            Log.render.error("URL capture is disabled: the network client entitlement is absent")
            throw RenderError.urlCaptureDisabled
        }

        // Gate 2: validation. Build the config from the URL; an unsupported scheme,
        // a private localhost host, or a malformed URL throws here. Never log the URL
        // itself — only the non-PII validation reason.
        let webConfig: WebSnapshotConfig
        do {
            webConfig = try WebSnapshotConfig(
                captureURL: url,
                viewportPreset: viewportPreset,
                captureMode: captureMode,
                waitStrategy: waitStrategy,
                safetyCaps: safetyCaps,
                scale: scale,
                profile: profile,
                dataStoreMode: dataStoreMode,
                allowsLoopbackCapture: allowsLoopbackCapture)
        } catch let error as URLValidationError {
            Log.render.error(
                "URL capture rejected the URL (\(error.diagnosticReason, privacy: .public))")
            if error == .privateLocalhost, !allowsLoopbackCapture, let host = url.host,
                WebSnapshotConfig.isLoopbackHost(host: host)
            {
                throw RenderError.loopbackCaptureDisabled
            }
            throw RenderError.renderFailed
        }

        let rawImage: CGImage
        do {
            rawImage = try await engine.snapshot(of: webConfig)
        } catch let error as WebSnapshotError {
            // Non-PII only: the typed failure mode, never the URL.
            Log.render.error(
                "URL capture failed to snapshot the page (\(error.diagnosticReason, privacy: .public))"
            )
            throw RenderError.renderFailed
        }

        let normalized = ExportManager.normalized(rawImage, to: profile)
        return RenderedAsset(cgImage: normalized, profile: profile)
    }
}

extension URLRenderer {
    /// Builds a renderer configured from the user's persisted web-capture settings:
    /// the chosen viewport preset, capture mode, and wait strategy, plus
    /// the shared export scale and color profile.
    ///
    /// This is the seam that connects the Input pane's controls to the URL render
    /// path. URL capture stays gated on the network entitlement, so the resulting
    /// renderer is still inert in a network-free build; when the entitlement is added, the
    /// coordinator can build the renderer from settings so a capture uses exactly the
    /// viewport and timing the user selected.
    static func configured(from settings: AppSettings) -> URLRenderer {
        URLRenderer(
            scale: CGFloat(settings.export.scale),
            viewportPreset: settings.webCapture.viewportPreset,
            captureMode: settings.webCapture.captureMode,
            waitStrategy: settings.webCapture.waitStrategy,
            profile: settings.export.colorProfile,
            dataStoreMode: settings.webCapture.dataStoreMode,
            allowsLoopbackCapture: settings.webCapture.allowsLoopbackCapture)
    }
}

extension URLValidationError {
    /// A stable, non-PII label for the refusal reason, for diagnostics. Never
    /// includes the rejected URL — only the kind of refusal (and, for an
    /// unsupported scheme, the scheme token, which is a fixed identifier).
    var diagnosticReason: String {
        switch self {
        case .malformed: "malformed-url"
        case .unsupportedScheme(let scheme): "unsupported-scheme-\(scheme)"
        case .privateLocalhost: "private-localhost"
        }
    }
}

/// The local, network-free-by-default engine behind `URLRenderer`: it loads a
/// validated URL in an offscreen `WKWebView`, applies the chosen wait strategy and
/// capture mode, and rasterizes the result to a `CGImage`.
///
/// This is the URL analogue of `WebSnapshotView` (which renders pasted HTML). It
/// owns the web view's lifecycle, picks the data store from the config's
/// `dataStoreMode` (`nonPersistent` by default), pins the preset viewport width, and
/// tears everything down before returning, so there is no shared web-view state
/// between renders. The page is loaded directly into the view's own layer and read
/// back with `WKWebView.takeSnapshot`; nothing reads the display, so no Screen
/// Recording permission is involved, and the bitmap path is shared with
/// `WebSnapshotView` so a URL snapshot sizes identically to an HTML one.
///
/// ## Capture mode and bounded full-page rendering
///
/// In `.visibleViewport` mode the snapshot rect is exactly the preset size, so the
/// bitmap is `viewport × scale` device pixels — fully deterministic. In `.fullPage`
/// mode the engine measures the document's content height after the wait, clamps it
/// to `SafetyCaps.maxPageHeight`, resizes the web view to that height, and snapshots
/// the whole page. The clamp is what keeps a runaway document from asking for a
/// multi-gigapixel bitmap.
///
/// ## Lazy-load scroll behavior
///
/// Many pages defer images and sections until they scroll into view, so a top-only
/// full-page capture would miss them. Before measuring the content height the engine
/// performs a **bounded** lazy-load pass: it scrolls the document down in viewport-
/// sized steps, up to a fixed maximum number of steps, pausing briefly between steps
/// for content to fault in, then scrolls back to the top. The pass is bounded by
/// `maxLazyLoadSteps` (so an infinitely growing/infinite-scroll page cannot loop
/// forever) and only runs for `.fullPage` captures; a visible-viewport capture never
/// scrolls. This is best-effort: content that loads only on interaction other than
/// scrolling, or below the height cap, is not guaranteed to appear.
///
/// `WKWebView` is main-actor bound, so the whole type runs on the main actor (the
/// module's default isolation).
@MainActor
struct URLSnapshotEngine {
    /// The maximum number of viewport-sized scroll steps the bounded lazy-load pass
    /// performs for a full-page capture. Caps the work for an infinite-scroll page:
    /// after this many steps the engine stops scrolling regardless of whether the
    /// document is still growing, so the pass always terminates.
    static let maxLazyLoadSteps = 20

    /// How long the lazy-load pass pauses between scroll steps for deferred content
    /// to fault in. Short so the whole bounded pass stays well inside the load budget.
    static let lazyLoadStepPause: Duration = .milliseconds(120)

    /// Renders `config` to a `CGImage`, or throws a typed `WebSnapshotError`.
    ///
    /// The web view is created per call, configured with the chosen data store, made
    /// to load the validated URL, and torn down before this returns. After the load
    /// settles it applies the wait strategy (a fixed post-load delay, or a best-effort
    /// network-quiet wait), then — for a full-page capture — runs the bounded
    /// lazy-load pass and grows the view to the clamped content height before
    /// snapshotting. A failure at any stage (a load error, a timeout, or a snapshot
    /// that yields no image) throws, so a caller never receives a blank picture.
    func snapshot(of config: WebSnapshotConfig) async throws -> CGImage {
        let viewport = config.viewport
        guard viewport.width > 0, viewport.height > 0 else {
            throw WebSnapshotError.invalidViewport
        }

        let configuration = WKWebViewConfiguration()
        // The data store is the explicit network mode: a per-render nonpersistent
        // store by default (nothing written to disk, no cookies across renders), or
        // the persistent store only when the user opted in.
        configuration.websiteDataStore = dataStore(for: config.dataStoreMode)

        let frame = CGRect(origin: .zero, size: viewport)
        let webView = WKWebView(frame: frame, configuration: configuration)
        // Laid out at the deterministic viewport but never shown — the snapshot reads
        // the view's own layer, not the screen.
        webView.frame = frame

        // The delegate reports load completion. Unlike pasted HTML (which blocks all
        // remote loads), a URL capture is a page the user explicitly asked to load,
        // so the page itself and its subresources are allowed; the engine still runs
        // entirely locally and never contacts a remote render service.
        let coordinator = LoadCoordinator(allowsLoopbackCapture: config.allowsLoopbackCapture)
        webView.navigationDelegate = coordinator
        defer {
            webView.navigationDelegate = nil
            webView.stopLoading()
        }

        webView.load(URLRequest(url: config.url))

        // Every wait below shares one absolute deadline. The timeout is no longer
        // only a navigation timeout; it bounds navigation, post-load settling, and
        // the bounded lazy-load pass before the snapshot is attempted.
        let deadline = ContinuousClock.now.advanced(by: config.timeout)

        // Wait for the navigation to settle, bounded by the remaining total budget.
        try await coordinator.waitForLoad(timeout: remainingBudget(until: deadline))

        // Apply the post-load wait the strategy asks for: nothing for
        // `.domContentLoaded`, a fixed delay, or a best-effort network-quiet settle.
        try await applyWaitStrategy(config.waitStrategy, on: webView, deadline: deadline)

        // Resolve the rect to capture. A visible-viewport capture is exactly the
        // preset size; a full-page capture grows the height to the clamped content
        // height after a bounded lazy-load pass.
        let captureRect = try await captureRect(
            for: config, webView: webView, viewport: viewport, deadline: deadline)

        _ = try remainingBudget(until: deadline)

        let snapshotConfiguration = WKSnapshotConfiguration()
        snapshotConfiguration.rect = captureRect
        snapshotConfiguration.snapshotWidth = NSNumber(value: Double(viewport.width))
        snapshotConfiguration.afterScreenUpdates = true

        let image: NSImage
        do {
            image = try await webView.takeSnapshot(configuration: snapshotConfiguration)
        } catch {
            Log.render.error(
                "URL snapshot failed during rasterization (\((error as NSError).domain, privacy: .public))"
            )
            throw WebSnapshotError.snapshotFailed
        }

        // Reuse the shared, deterministic bitmap path so a URL snapshot is exactly
        // captureRect × scale device pixels, identical to an HTML snapshot.
        guard let cgImage = WebSnapshotView().cgImage(from: image, scale: config.scale) else {
            Log.render.error("URL snapshot produced no CGImage")
            throw WebSnapshotError.snapshotFailed
        }
        return cgImage
    }

    /// Applies the post-load portion of a wait strategy on `webView`.
    ///
    /// `.domContentLoaded` returns immediately (the load already settled).
    /// `.fixedDelay` sleeps the configured duration so client-rendered content has a
    /// predictable window to appear. `.networkQuiet` polls for the page to stop
    /// issuing requests (best-effort) up to its budget, falling back to the full
    /// budget if it never quiesces.
    func applyWaitStrategy(
        _ strategy: WebSnapshotConfig.WaitStrategy, on webView: WKWebView,
        deadline: ContinuousClock.Instant
    ) async throws {
        switch strategy {
        case .domContentLoaded:
            return
        case .fixedDelay(let delay):
            try await sleep(delay, within: deadline)
        case .networkQuiet(let budget):
            try await waitForNetworkQuiet(on: webView, budget: budget, deadline: deadline)
        }
    }

    /// Best-effort network-quiet wait: polls until the document reports it has
    /// finished loading and stays settled for a short idle window, or until `budget`
    /// elapses — whichever comes first. Bounded by the budget so a page that polls
    /// forever still returns.
    private func waitForNetworkQuiet(
        on webView: WKWebView, budget: Duration, deadline totalDeadline: ContinuousClock.Instant
    ) async throws {
        let deadline = min(ContinuousClock.now.advanced(by: budget), totalDeadline)
        let idleWindow = Duration.milliseconds(400)
        let pollInterval = Duration.milliseconds(100)
        var settledSince: ContinuousClock.Instant?

        while ContinuousClock.now < deadline {
            let isComplete = await documentIsComplete(webView)
            let now = ContinuousClock.now
            if isComplete {
                if let since = settledSince {
                    if since.duration(to: now) >= idleWindow { return }
                } else {
                    settledSince = now
                }
            } else {
                settledSince = nil
            }
            // Sleep one poll interval, never overshooting the budget deadline. Budget
            // exhaustion is a normal best-effort exit (the loop condition ends it and the page
            // is snapshotted anyway), NOT a failure — so this must not throw `.timedOut` the way
            // the deadline-enforcing `sleep(_:within:)` does. Only the absolute total deadline,
            // checked after the loop, fails the capture. (A sub-interval remaining budget made
            // the old `sleep(within:)` throw here and surface as `renderFailed`.)
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { break }
            try await Task.sleep(for: min(pollInterval, remaining))
        }
        if ContinuousClock.now >= totalDeadline { throw WebSnapshotError.timedOut }
    }

    /// Whether `document.readyState` is `complete` — the cheapest available "page has
    /// settled" signal. Any evaluation failure conservatively reports `false`, so a
    /// flaky probe never short-circuits the quiet wait early.
    private func documentIsComplete(_ webView: WKWebView) async -> Bool {
        let state = try? await webView.evaluateJavaScript("document.readyState") as? String
        return state == "complete"
    }

    /// The rect to snapshot for `config`. For a visible-viewport capture this is
    /// exactly the preset viewport. For a full-page capture it runs the bounded
    /// lazy-load pass, measures the document's content height, clamps it to the safety
    /// cap, grows the web view to that height, and returns the full-page rect.
    private func captureRect(
        for config: WebSnapshotConfig, webView: WKWebView, viewport: CGSize,
        deadline: ContinuousClock.Instant
    ) async throws -> CGRect {
        guard config.captureMode.capturesFullHeight else {
            return CGRect(origin: .zero, size: viewport)
        }

        // Fault in deferred content with a bounded scroll pass before measuring, so a
        // lazy-loading page is captured top to bottom rather than blank below the fold.
        try await performBoundedLazyLoadPass(on: webView, viewport: viewport, deadline: deadline)

        let contentHeight = await documentContentHeight(webView, fallback: viewport.height)
        let cappedHeight = config.safetyCaps.clampPageHeight(
            contentHeight, viewportHeight: viewport.height)

        // Grow the web view to the captured height and lay it out so the whole page is
        // rendered into the layer the snapshot reads.
        let fullFrame = CGRect(x: 0, y: 0, width: viewport.width, height: cappedHeight)
        webView.frame = fullFrame
        webView.layoutSubtreeIfNeeded()
        // A brief settle so the resized layout paints before the snapshot.
        try await sleep(.milliseconds(80), within: deadline)

        return fullFrame
    }

    /// Scrolls the document down in viewport-sized steps to trigger lazy-loaded
    /// content, then returns to the top. Strictly bounded: it stops after
    /// `maxLazyLoadSteps` steps or once it reaches the bottom of the document,
    /// whichever comes first, so an infinite-scroll page cannot loop forever.
    private func performBoundedLazyLoadPass(
        on webView: WKWebView, viewport: CGSize, deadline: ContinuousClock.Instant
    ) async throws {
        let step = max(viewport.height, 1)
        var offset = step
        for _ in 0..<Self.maxLazyLoadSteps {
            _ = try remainingBudget(until: deadline)
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, \(offset))")
            try await sleep(Self.lazyLoadStepPause, within: deadline)
            let height = await documentContentHeight(webView, fallback: step)
            if offset >= height { break }
            offset += step
        }
        // Return to the top so the capture starts at the document origin.
        _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 0)")
        try await sleep(Self.lazyLoadStepPause, within: deadline)
    }

    /// The document's full scrollable height in CSS points, read from the DOM. Returns
    /// `fallback` if the measurement is unavailable or non-positive, so a failed probe
    /// degrades to the viewport height rather than a zero-height capture.
    private func documentContentHeight(_ webView: WKWebView, fallback: CGFloat) async -> CGFloat {
        let script = """
            Math.max(
              document.body ? document.body.scrollHeight : 0,
              document.documentElement ? document.documentElement.scrollHeight : 0,
              document.body ? document.body.offsetHeight : 0,
              document.documentElement ? document.documentElement.offsetHeight : 0
            )
            """
        guard
            let value = try? await webView.evaluateJavaScript(script) as? NSNumber,
            value.doubleValue > 0
        else {
            return fallback
        }
        return CGFloat(value.doubleValue)
    }

    /// The `WKWebsiteDataStore` for `mode`: a fresh per-render nonpersistent store
    /// (the default, nothing persisted) or the shared persistent store (the explicit
    /// opt-in that carries existing cookies and website data).
    func dataStore(for mode: WebSnapshotConfig.DataStoreMode) -> WKWebsiteDataStore {
        switch mode {
        case .nonPersistent: .nonPersistent()
        case .persistent: .default()
        }
    }

    /// The remaining time until `deadline`, or a typed timeout when the total budget
    /// has already been consumed.
    func remainingBudget(until deadline: ContinuousClock.Instant) throws -> Duration {
        let now = ContinuousClock.now
        guard now < deadline else { throw WebSnapshotError.timedOut }
        return now.duration(to: deadline)
    }

    /// Sleeps for `duration` without overshooting the total deadline. If the requested
    /// wait cannot fit, it sleeps only until the deadline and then throws `.timedOut`
    /// so the caller never continues past the cap as if the full wait had completed.
    private func sleep(_ duration: Duration, within deadline: ContinuousClock.Instant) async throws
    {
        let remaining = try remainingBudget(until: deadline)
        guard duration <= remaining else {
            try await Task.sleep(for: remaining)
            throw WebSnapshotError.timedOut
        }
        try await Task.sleep(for: duration)
    }
}

/// Drives one offscreen URL load: signals when the navigation has settled or
/// failed, bounded by a timeout. A fresh instance is used per snapshot, so it holds
/// no state across renders.
///
/// This mirrors `WebSnapshotView`'s navigation coordinator but does not enforce a
/// network block — a URL capture is a page the user explicitly asked to load, so the
/// page and its subresources are permitted. `WKNavigationDelegate` is an
/// `NSObjectProtocol`, so this is an `NSObject` subclass; its callbacks arrive on the
/// main actor, matching the module's default isolation.
@MainActor
private final class LoadCoordinator: NSObject, WKNavigationDelegate {
    /// Frozen from the validated config so policy cannot change midway through a load.
    private let allowsLoopbackCapture: Bool

    init(allowsLoopbackCapture: Bool) {
        self.allowsLoopbackCapture = allowsLoopbackCapture
        super.init()
    }

    /// The continuation resumed when the load finishes, fails, or times out.
    /// Resumed exactly once; cleared on resume so neither a late navigation callback
    /// nor the timeout can resume it twice.
    private var loadContinuation: CheckedContinuation<Void, Error>?

    /// Set once the navigation has settled so `waitForLoad` can return immediately if
    /// the load completed before the caller began waiting.
    private var outcome: Result<Void, Error>?

    /// The armed timeout. It resumes the wait with `.timedOut` if the load has not
    /// settled in time, and is cancelled the moment the load does settle.
    private var timeoutTask: Task<Void, Never>?

    /// Suspends until the page finishes loading or fails, or until `timeout` elapses
    /// (whichever comes first). Throws `WebSnapshotError.timedOut` on the timeout and
    /// `WebSnapshotError.loadFailed` on a navigation failure.
    func waitForLoad(timeout: Duration) async throws {
        if let outcome {
            self.outcome = nil
            try outcome.get()
            return
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                // The task may already have been cancelled before we suspended.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                loadContinuation = continuation
                timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.resume(.failure(WebSnapshotError.timedOut))
                }
            }
        } onCancel: {
            // Cancel can arrive on any executor; hop to this type's main-actor isolation
            // to resume the wait. `resume` is idempotent, so a cancel racing a real
            // completion is harmless; the renderer's `defer` then stops the load.
            Task { @MainActor [weak self] in
                self?.resume(.failure(CancellationError()))
            }
        }
    }

    /// Resumes the load continuation exactly once, recording the outcome for a caller
    /// that has not started waiting yet, and disarming the timeout.
    private func resume(_ result: Result<Void, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let continuation = loadContinuation {
            loadContinuation = nil
            continuation.resume(with: result)
        } else {
            outcome = result
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resume(.success(()))
    }

    func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        Log.render.error(
            "URL page navigation failed (\((error as NSError).domain, privacy: .public))")
        resume(.failure(WebSnapshotError.loadFailed))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Log.render.error(
            "URL page provisional navigation failed (\((error as NSError).domain, privacy: .public))"
        )
        resume(.failure(WebSnapshotError.loadFailed))
    }

    /// Re-validates every navigation target against the SSRF host filter. The entry
    /// URL is checked before `load`, but a public page can 30x-redirect — or embed a frame —
    /// to a private, loopback, or link-local host (e.g. the `169.254.169.254` cloud-metadata
    /// endpoint); without this, WebKit would follow it and render the private response. This
    /// closes the post-redirect gap, matching `BackgroundImageStore`'s image-download re-check.
    /// A blocked main-frame target fails the capture; a blocked subframe is dropped so the rest
    /// of the page still renders.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if let host = navigationAction.request.url?.host,
            WebSnapshotConfig.isRefusedHost(
                host, allowLoopback: allowsLoopbackCapture)
        {
            decisionHandler(.cancel)
            if navigationAction.targetFrame?.isMainFrame ?? true {
                Log.render.error("URL capture blocked a navigation to a private host")
                resume(.failure(WebSnapshotError.loadFailed))
            }
            return
        }
        decisionHandler(.allow)
    }

    /// Backstop for server-issued redirects of the provisional (main-frame) navigation: if the
    /// redirected URL resolves to a private host, stop and fail rather than render it.
    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        if let host = webView.url?.host,
            WebSnapshotConfig.isRefusedHost(host, allowLoopback: allowsLoopbackCapture)
        {
            webView.stopLoading()
            Log.render.error("URL capture blocked a server redirect to a private host")
            resume(.failure(WebSnapshotError.loadFailed))
        }
    }
}
