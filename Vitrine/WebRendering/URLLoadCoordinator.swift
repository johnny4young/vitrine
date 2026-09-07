import Foundation
import OSLog
import WebKit

/// Drives one offscreen URL load: signals when the navigation has settled or
/// failed, bounded by a timeout. A fresh instance is used per snapshot, so it holds
/// no state across renders.
///
/// This shares ``WebLoadWaiter`` with `WebSnapshotView`'s navigation coordinator.
/// A URL capture may load public network content because the user explicitly asked
/// for the page, while `PrivateNetworkBlockRules` blocks literal private/local
/// subresources that never reach this delegate. This coordinator is the second
/// layer for top-level and child-frame navigation.
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

    /// Whether a navigation may proceed during a URL capture.
    ///
    /// Extracted from the delegate so the rule is a pure function tests assert directly,
    /// with no `WKWebView` and no web content process — the same shape as
    /// `WebSnapshotView.NetworkPolicy` on the pasted-HTML side.
    ///
    /// Two independent reasons to refuse:
    ///
    /// - **Scheme.** The entry URL is validated against `WebSnapshotConfig.allowedSchemes`
    ///   before the load, but that check never ran again afterwards. A navigation whose URL
    ///   carries no host — `file:`, `data:`, `about:`, `blob:` — skipped the host filter
    ///   entirely and was allowed. A main-frame navigation must therefore be a web scheme
    ///   with a host, and `file:` is refused in any frame.
    /// - **Host.** A public page can 30x-redirect, or embed a frame, pointing at a private,
    ///   loopback, or link-local host (the `169.254.169.254` cloud-metadata endpoint being
    ///   the canonical example). This is the post-redirect gap that mirrors
    ///   `BackgroundImageStore`'s image-download re-check.
    ///
    /// Subframes keep the narrower rule on purpose: `about:srcdoc` and `data:` iframes are
    /// ordinary page furniture, and refusing them would break real pages without closing
    /// any path to private content.
    enum NavigationPolicy {
        enum Decision: Equatable {
            case allow
            /// Refused, with the reason to log. Never carries a URL or host: the log
            /// records what kind of thing was refused, never where the user browsed.
            case cancel(reason: String)
        }

        static func decision(
            for url: URL?, isMainFrame: Bool, allowsLoopback: Bool
        ) -> Decision {
            let scheme = url?.scheme?.lowercased()

            if isMainFrame {
                guard let scheme, WebSnapshotConfig.allowedSchemes.contains(scheme) else {
                    return .cancel(reason: "unsupported scheme")
                }
                guard let host = url?.host, !host.isEmpty else {
                    return .cancel(reason: "missing host")
                }
            } else if scheme == "file" {
                return .cancel(reason: "local file subframe")
            }

            if let host = url?.host,
                WebSnapshotConfig.isRefusedHost(host, allowLoopback: allowsLoopback)
            {
                return .cancel(reason: "private host")
            }
            return .allow
        }
    }

    /// Re-validates every navigation target. The delegate only pulls the URL and the frame
    /// off the live navigation; the rule itself is `NavigationPolicy`. A blocked main-frame
    /// target fails the capture; a blocked subframe is dropped so the rest of the page
    /// still renders.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        switch NavigationPolicy.decision(
            for: navigationAction.request.url,
            isMainFrame: isMainFrame,
            allowsLoopback: allowsLoopbackCapture)
        {
        case .allow:
            decisionHandler(.allow)
        case .cancel(let reason):
            decisionHandler(.cancel)
            if isMainFrame {
                Log.render.error(
                    "URL capture blocked a navigation (\(reason, privacy: .public))")
                loadWaiter.complete(.failure(WebSnapshotError.loadFailed))
            }
        }
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
