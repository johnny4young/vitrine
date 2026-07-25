import AppKit
import WebKit

/// A real, visible browser window whose only job is to let the user sign in to a site so
/// that Vitrine can capture it.
///
/// The capture engine (`URLRenderer`) is deliberately offscreen and non-interactive: it
/// loads a page and rasterizes it with `takeSnapshot`, so there is nothing to type a
/// password into. That is fine for a public page and useless for one behind a login,
/// which is why opting into `DataStoreMode.persistent` alone never worked — it switched
/// the capture to a persistent store that had no way of ever receiving a session.
///
/// This window closes that gap. It loads the same URL in a normal, interactive
/// `WKWebView` bound to the **same** `WKWebsiteDataStore.default()` the capture uses, so
/// the cookies the site sets while the user signs in are exactly the cookies the next
/// capture sends. Nothing is scraped from another browser: WebKit isolates website data
/// per application, so this is Vitrine signing in on its own behalf, with the user
/// driving it.
@MainActor
final class WebSessionWindowController: NSObject, NSWindowDelegate {
    static let shared = WebSessionWindowController()

    private var window: NSWindow?
    private var webView: WKWebView?
    /// Run when the window closes, so the caller can refresh what it shows about stored
    /// sessions without polling.
    private var onClose: (() -> Void)?

    /// Whether the sign-in window is currently open.
    var isPresented: Bool { window != nil }

    /// Opens the sign-in window on `url`, or brings an open one forward and navigates it.
    ///
    /// The caller is responsible for having established that signing in is available —
    /// see `WebSessionAvailability`.
    func show(url: URL, onClose: (() -> Void)? = nil) {
        self.onClose = onClose

        let webView = self.webView ?? makeWebView()
        self.webView = webView

        let window = self.window ?? makeWindow(hosting: webView)
        self.window = window

        webView.load(URLRequest(url: url))
        // An accessory app gets no activation from the caller's click, and this window
        // exists to be typed into.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the window, keeping whatever the site stored.
    func close() {
        window?.close()
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The whole point: the interactive session and the offscreen capture must share
        // one store, or signing in here would have no effect on what a capture sees.
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    private func makeWindow(hosting webView: WKWebView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = String(localized: "Sign In for Web Capture")
        window.contentView = webView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("VitrineWebSessionWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the web view with the window: a signed-in page left loaded off-screen
        // would keep running timers and network activity for a window the user closed.
        webView = nil
        window = nil
        let onClose = self.onClose
        self.onClose = nil
        onClose?()
    }
}
