import Foundation
import OSLog
import WebKit

/// Drives one offscreen URL load: signals when the navigation has settled or
/// failed, bounded by a timeout. A fresh instance is used per snapshot, so it holds
/// no state across renders.
///
/// This shares ``WebLoadWaiter`` with `WebSnapshotView`'s navigation coordinator but
/// does not enforce the pasted-HTML network block — a URL capture is a page the user
/// explicitly asked to load, so the page and its subresources are permitted.
/// `WKNavigationDelegate` is an
/// `NSObjectProtocol`, so this is an `NSObject` subclass; its callbacks arrive on the
/// main actor, matching the module's default isolation.
final class URLLoadCoordinator: NSObject, WKNavigationDelegate {
    /// Frozen from the validated config so policy cannot change midway through a load.
    private let allowsLoopbackCapture: Bool

    init(allowsLoopbackCapture: Bool) {
        self.allowsLoopbackCapture = allowsLoopbackCapture
        super.init()
    }

    private let loadWaiter = WebLoadWaiter()

    /// Suspends until the page finishes loading or fails, or until `timeout` elapses
    /// (whichever comes first). Throws `WebSnapshotError.timedOut` on the timeout and
    /// `WebSnapshotError.loadFailed` on a navigation failure.
    func waitForLoad(timeout: Duration) async throws {
        try await loadWaiter.wait(timeout: timeout)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadWaiter.complete(.success(()))
    }

    func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        Log.render.error(
            "URL page navigation failed (\((error as NSError).domain, privacy: .public))")
        loadWaiter.complete(.failure(WebSnapshotError.loadFailed))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Log.render.error(
            "URL page provisional navigation failed (\((error as NSError).domain, privacy: .public))"
        )
        loadWaiter.complete(.failure(WebSnapshotError.loadFailed))
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
                loadWaiter.complete(.failure(WebSnapshotError.loadFailed))
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
            loadWaiter.complete(.failure(WebSnapshotError.loadFailed))
        }
    }
}
