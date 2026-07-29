import Foundation
import OSLog
import WebKit

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
final class URLLoadCoordinator: NSObject, WKNavigationDelegate {
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
