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
final class WebSessionWindowController: NSObject, NSWindowDelegate {
    static let shared = WebSessionWindowController()

    /// Bridges the synchronous presentation action to the fail-closed async WebKit
    /// setup. This entry point is nonisolated because the presentation port is a
    /// plain callback; every AppKit operation still executes on the main actor.
    nonisolated static func requestSignIn(url: URL, allowsLoopback: Bool) {
        Task { @MainActor in
            do {
                try await shared.show(url: url, allowsLoopback: allowsLoopback)
            } catch {
                let alert = NSAlert()
                alert.messageText = String(localized: "Could Not Open Sign-In Window")
                alert.informativeText = String(
                    localized: "Vitrine could not establish safe web access. Try again later.")
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private let websiteDataStore: WKWebsiteDataStore

    /// Keep the sign-in and capture stores identical; tests inject an ephemeral store
    /// rather than writing synthetic credentials into the user's WebKit profile.
    init(websiteDataStore: WKWebsiteDataStore = .default()) {
        self.websiteDataStore = websiteDataStore
        super.init()
    }

    private var window: NSWindow?
    private var webView: WKWebView?
    private var navigationCoordinator: URLLoadCoordinator?
    private var presentationGeneration = UUID()
    /// Whether the sign-in window is currently open.
    var isPresented: Bool { window != nil }

    /// Opens the sign-in window on `url`, or brings an open one forward and navigates it.
    ///
    /// The caller establishes that signing in is available (see
    /// `WebSessionAvailability`); this boundary independently validates the URL
    /// and installs the capture's private-host policy before loading anything.
    func show(url: URL, allowsLoopback: Bool) async throws {
        let generation = UUID()
        presentationGeneration = generation
        // Validate again at the last entry point. The editor validates its field, but
        // callers must not be able to open an unfiltered browser through this API.
        let checkedURL = try WebSnapshotConfig.validate(
            captureURL: url, allowLoopback: allowsLoopback)
        // A navigation delegate never sees images, scripts, or fetch requests. Do not
        // create or load the browser until the same fail-closed rule list used by URL
        // capture has compiled; a failed compilation must not become an open browser.
        let ruleList = try await URLSnapshotEngine.privateNetworkBlockList(
            allowsLoopback: allowsLoopback)
        guard generation == presentationGeneration else { return }

        let webView = makeWebView(ruleList: ruleList, allowsLoopback: allowsLoopback)
        self.webView?.stopLoading()
        self.webView?.navigationDelegate = nil
        self.webView = webView

        let window = self.window ?? makeWindow(hosting: webView)
        self.window = window
        if window.contentView !== webView { window.contentView = webView }

        webView.load(URLRequest(url: checkedURL))
        // An accessory app gets no activation from the caller's click, and this window
        // exists to be typed into.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the window, keeping whatever the site stored.
    func close() {
        presentationGeneration = UUID()
        window?.close()
    }

    private func makeWebView(ruleList: WKContentRuleList, allowsLoopback: Bool) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The whole point: the interactive session and the offscreen capture must share
        // one store, or signing in here would have no effect on what a capture sees.
        configuration.websiteDataStore = websiteDataStore
        configuration.userContentController.add(ruleList)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let coordinator = URLLoadCoordinator(allowsLoopbackCapture: allowsLoopback)
        webView.navigationDelegate = coordinator
        navigationCoordinator = coordinator
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
        window.setAccessibilityIdentifier("web-sign-in-window")
        window.center()
        window.setFrameAutosaveName("VitrineWebSessionWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        presentationGeneration = UUID()
        // Drop the web view with the window: a signed-in page left loaded off-screen
        // would keep running timers and network activity for a window the user closed.
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        navigationCoordinator = nil
        window = nil
        NotificationCenter.default.post(name: WebSessionStore.didChange, object: nil)
    }
}
