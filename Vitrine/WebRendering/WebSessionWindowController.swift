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
final class WebSessionWindowController: NSObject, NSWindowDelegate, WKUIDelegate {
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
                // An accessory app would otherwise show the alert behind other apps.
                AppActivation.bringForward()
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
    private var allowsLoopback = false
    private var locationObservations: [NSKeyValueObservation] = []
    /// Sign-in popups (`window.open`, `target=_blank`) hosted in their own windows so
    /// SSO flows that report back through `window.opener` can finish.
    /// Each popup owns its subtitle observations, so they are released with that popup
    /// instead of accumulating for the lifetime of the sign-in window.
    private var popups:
        [(
            window: NSWindow, webView: WKWebView, coordinator: URLLoadCoordinator,
            observations: [NSKeyValueObservation]
        )] = []
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

        self.allowsLoopback = allowsLoopback
        let webView = makeWebView(ruleList: ruleList, allowsLoopback: allowsLoopback)
        self.webView?.stopLoading()
        self.webView?.navigationDelegate = nil
        self.webView?.uiDelegate = nil
        closePopups()
        self.webView = webView

        let window = self.window ?? makeWindow(hosting: webView)
        self.window = window
        if window.contentView !== webView { window.contentView = webView }
        observeLocation(of: webView, in: window)

        webView.load(URLRequest(url: checkedURL))
        // An accessory app gets no activation from the caller's click, and this window
        // exists to be typed into.
        AppActivation.bringForward()
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
        let coordinator = makeCoordinator()
        webView.navigationDelegate = coordinator
        webView.uiDelegate = self
        navigationCoordinator = coordinator
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    /// The capture's navigation policy, plus a credential sheet for HTTP authentication
    /// that only this interactive window can answer.
    private func makeCoordinator() -> URLLoadCoordinator {
        let coordinator = URLLoadCoordinator(allowsLoopbackCapture: allowsLoopback)
        coordinator.credentialProvider = { [weak self] space, webView in
            guard let self, let window = webView.window ?? self.window else { return nil }
            return await Self.requestCredential(for: space, in: window)
        }
        return coordinator
    }

    /// Keeps the window subtitle on the page's real host and transport security, so the
    /// user can see where they are typing credentials after cross-site redirects.
    private func observeLocation(of webView: WKWebView, in window: NSWindow) {
        locationObservations = Self.subtitleObservations(of: webView, in: window)
    }

    /// WebKit posts these KVO changes on the main thread.
    private static func subtitleObservations(
        of webView: WKWebView, in window: NSWindow
    ) -> [NSKeyValueObservation] {
        [
            webView.observe(\.url, options: [.initial]) { [weak window] webView, _ in
                MainActor.assumeIsolated { updateSubtitle(of: window, for: webView) }
            },
            webView.observe(\.hasOnlySecureContent) { [weak window] webView, _ in
                MainActor.assumeIsolated { updateSubtitle(of: window, for: webView) }
            },
        ]
    }

    private static func updateSubtitle(of window: NSWindow?, for webView: WKWebView) {
        window?.subtitle = locationSubtitle(
            url: webView.url, hasOnlySecureContent: webView.hasOnlySecureContent)
    }

    /// The host shown under the window title, flagged when the page is not served
    /// entirely over HTTPS.
    static func locationSubtitle(url: URL?, hasOnlySecureContent: Bool) -> String {
        guard let host = url?.host(), !host.isEmpty else { return "" }
        if url?.scheme?.lowercased() == "https", hasOnlySecureContent { return host }
        return String(localized: "\(host) — Not Secure")
    }

    /// Asks for a user name and password in a sheet on `window`; nil when cancelled.
    private static func requestCredential(
        for space: URLProtectionSpace, in window: NSWindow
    ) async -> URLCredential? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Sign in to \(space.host)")
        alert.informativeText = String(
            localized: "\(space.host) requires a user name and password.")
        alert.addButton(withTitle: String(localized: "Sign In"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let user = NSTextField()
        user.placeholderString = String(localized: "User name")
        let password = NSSecureTextField()
        password.placeholderString = String(localized: "Password")
        let fields = NSStackView(views: [user, password])
        fields.orientation = .vertical
        fields.spacing = 8
        fields.frame = NSRect(x: 0, y: 0, width: 260, height: 52)
        user.frame.size.width = 260
        password.frame.size.width = 260
        alert.accessoryView = fields
        alert.window.initialFirstResponder = user
        guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else {
            return nil
        }
        return URLCredential(
            user: user.stringValue, password: password.stringValue, persistence: .forSession)
    }

    // MARK: WKUIDelegate

    /// Hosts a popup in its own window on the same configuration WebKit hands over, so it
    /// shares the session store, the private-host rules, and `window.opener`.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard self.webView != nil else { return nil }
        let width = windowFeatures.width.map { CGFloat($0.doubleValue) } ?? 520
        let height = windowFeatures.height.map { CGFloat($0.doubleValue) } ?? 680
        let popup = WKWebView(
            frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: configuration)
        let coordinator = makeCoordinator()
        popup.navigationDelegate = coordinator
        popup.uiDelegate = self
        let popupWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        popupWindow.title = String(localized: "Sign In for Web Capture")
        popupWindow.contentView = popup
        popupWindow.isReleasedWhenClosed = false
        popupWindow.delegate = self
        popupWindow.center()
        let observations = Self.subtitleObservations(of: popup, in: popupWindow)
        popups.append((popupWindow, popup, coordinator, observations))
        popupWindow.makeKeyAndOrderFront(nil)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.first { $0.webView === webView }?.window.close()
    }

    private func closePopups() {
        let open = popups
        popups = []
        for popup in open {
            for observation in popup.observations { observation.invalidate() }
            popup.webView.stopLoading()
            popup.webView.navigationDelegate = nil
            popup.webView.uiDelegate = nil
            popup.window.close()
        }
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
        if let closing = notification.object as? NSWindow, closing !== window {
            if let index = popups.firstIndex(where: { $0.window === closing }) {
                let popup = popups.remove(at: index)
                for observation in popup.observations { observation.invalidate() }
                popup.webView.stopLoading()
                popup.webView.navigationDelegate = nil
                popup.webView.uiDelegate = nil
            }
            return
        }
        presentationGeneration = UUID()
        closePopups()
        locationObservations = []
        // Drop the web view with the window: a signed-in page left loaded off-screen
        // would keep running timers and network activity for a window the user closed.
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        navigationCoordinator = nil
        window = nil
        NotificationCenter.default.post(name: WebSessionStore.didChange, object: nil)
    }
}
