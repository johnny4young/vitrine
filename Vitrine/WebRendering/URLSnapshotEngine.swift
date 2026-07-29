import AppKit
import CoreGraphics
import Foundation
import OSLog
import WebKit

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
        let coordinator = URLLoadCoordinator(allowsLoopbackCapture: config.allowsLoopbackCapture)
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
