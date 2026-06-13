import AppKit
import OSLog
import SwiftUI

/// Which kind of web input the Web Snapshot surface is composing.
enum WebInputMode: String, CaseIterable, Identifiable {
    /// A user-provided `http`/`https` URL, captured locally in WebKit (CS-043).
    case url
    /// A pasted HTML fragment or document, rendered locally with remote subresources
    /// blocked (CS-042).
    case html

    var id: String { rawValue }
}

/// The observable document behind the Web Snapshot window: the chosen input mode, the
/// URL/HTML the user is composing, the rendered result, and the in-flight/error state
/// (CS-042/CS-043).
///
/// The render itself runs here so the view stays declarative: ``render(settings:)``
/// builds the right renderer (`HTMLRenderer` for HTML, `URLRenderer.configured` for
/// URL), invokes it, and publishes either the `RenderedAsset` or a typed, non-PII
/// error message. URL capture stays gated on the network entitlement inside
/// `URLRenderer`, so a build without it surfaces a clear "only in the direct-download
/// build" message rather than a blank result.
@MainActor
final class WebSnapshotModel: ObservableObject {
    @Published var mode: WebInputMode = .url
    @Published var urlText: String = ""
    @Published var htmlText: String = ""

    /// The most recent successful render, shown in the preview and exported.
    @Published var renderedAsset: RenderedAsset?
    /// Whether a render is in flight (drives the preview's loading state).
    @Published var isRendering = false
    /// A user-facing, non-PII error from the last render attempt, or `nil`.
    @Published var errorMessage: String?

    /// Whether the active input has enough content to attempt a render.
    var canRender: Bool {
        switch mode {
        case .url: !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .html: !htmlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The host of the URL being captured, shown verbatim in the loading state for
    /// transparency (which page is being loaded). `nil` outside URL mode or for an
    /// unparseable URL.
    var loadingHost: String? {
        guard mode == .url, let url = Self.normalizedURL(urlText) else { return nil }
        return url.host
    }

    /// Renders the current input through the appropriate renderer, publishing the
    /// asset or a typed error. Safe to call repeatedly; each call replaces the result.
    func render(settings: AppSettings) async {
        // Ignore a re-entrant render while one is already in flight (a fast second
        // Capture tap, or a disclosure-confirm landing while a prefilled render runs),
        // so two WKWebView load-and-snapshot cycles never overlap. Safe because this
        // type is @MainActor, so the check-and-set cannot interleave.
        guard !isRendering else { return }
        errorMessage = nil
        isRendering = true
        defer { isRendering = false }
        do {
            switch mode {
            case .html:
                let renderer = HTMLRenderer(
                    viewport: settings.webViewportPreset.size,
                    scale: CGFloat(settings.exportScale),
                    profile: settings.colorProfile)
                renderedAsset = try await renderer.render(
                    .html(htmlText), config: settings.config)
            case .url:
                guard let url = Self.normalizedURL(urlText) else {
                    errorMessage = String(localized: "Enter a valid http or https URL.")
                    renderedAsset = nil
                    return
                }
                let renderer = URLRenderer.configured(from: settings)
                renderedAsset = try await renderer.render(.url(url), config: settings.config)
            }
        } catch let error as RenderError {
            renderedAsset = nil
            errorMessage = Self.message(for: error)
        } catch {
            renderedAsset = nil
            errorMessage = String(localized: "The render didn't complete.")
        }
    }

    /// Trims and accepts only a single `http`/`https` URL, mirroring the renderer's own
    /// scheme gate so the UI rejects an obviously bad URL before a render attempt.
    static func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    /// A user-facing, localized message for a render error — never the URL or HTML.
    static func message(for error: RenderError) -> String {
        switch error {
        case .urlCaptureDisabled:
            String(localized: "URL capture is only available in the direct-download build.")
        case .renderFailed:
            String(localized: "Couldn't load or render that — check the input and try again.")
        case .noRendererFor:
            String(localized: "That input can't be rendered here.")
        }
    }
}

/// Owns the app's single Web Snapshot window (CS-042/CS-043): local HTML rendering and
/// (on a build that carries the network entitlement) URL capture, with a live preview
/// and the same clipboard/save/share export as the rest of the app.
///
/// Like `SocialCardWindowController`, the window is reused across opens and closes. It
/// is registered with `WebSnapshotPresenter` at launch (`registerPresenter()`), so the
/// File-menu command, the `--open-web-snapshot` hook, and the quick-capture URL route —
/// all of which live in `App/` and must not link WebKit — present it through that seam
/// rather than naming this WebKit-backed controller directly.
@MainActor
final class WebSnapshotWindowController: NSObject {
    static let shared = WebSnapshotWindowController()

    /// The window's working document, shared with the hosted SwiftUI view.
    let model = WebSnapshotModel()

    private var window: NSWindow?

    private static let defaultContentSize = NSSize(width: 1100, height: 760)
    private static let frameAutosaveName = "vitrine.web-snapshot.window"

    /// Not an `editor-window` prefix, so a key Web Snapshot window never enables the
    /// editor-scoped export commands.
    static let windowIdentifier = "web-snapshot-window"

    private override init() { super.init() }

    /// Installs the window opener on `WebSnapshotPresenter`. Called once at launch from
    /// the app-only `VitrineApp`, so the CLI (which excludes this file) never links the
    /// WebKit-backed window.
    static func registerPresenter() {
        WebSnapshotPresenter.open = { prefillURL in
            WebSnapshotWindowController.shared.show(prefillURL: prefillURL)
        }
    }

    /// Shows the Web Snapshot window, creating it the first time, and focuses it.
    /// `prefillURL` (from the quick-capture URL route) loads the URL field in URL mode
    /// and clears any previous result so the user lands ready to capture.
    func show(prefillURL: String? = nil) {
        if let prefillURL {
            model.mode = .url
            model.urlText = prefillURL
            model.renderedAsset = nil
            model.errorMessage = nil
        }
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: WebSnapshotEditorView(model: model).environmentObject(AppSettings.shared))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Web Snapshot")
        window.styleMask = [
            .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
        ]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(Self.defaultContentSize)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setAccessibilityIdentifier(Self.windowIdentifier)

        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
                window.setFrame(
                    WindowFrameSolver.clamp(window.frame, into: visible), display: false)
            }
            window.center()
        }
        return window
    }
}
