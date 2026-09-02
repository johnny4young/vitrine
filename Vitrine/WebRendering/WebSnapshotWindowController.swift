import AppKit
import SwiftUI

/// Owns the app's single Web Snapshot window: local HTML rendering and
/// (on a build that carries the network entitlement) URL capture, with a live preview
/// and the same clipboard/save/share export as the rest of the app.
///
/// Like `SocialCardWindowController`, the window is reused across opens and closes. It
/// is registered with `WebSnapshotPresenter` at launch (`registerPresenter()`), so the
/// File-menu command, the `--open-web-snapshot` hook, and the quick-capture URL route —
/// all of which live in `App/` and must not link WebKit — present it through that seam
/// rather than naming this WebKit-backed controller directly.
@MainActor
final class WebSnapshotWindowController: NSObject, NSWindowDelegate {
    static let shared = WebSnapshotWindowController(
        environment: .shared,
        model: makeSharedModel(),
        feedback: .live,
        presentation: .live)

    private static func makeSharedModel() -> WebSnapshotModel {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--web-snapshot-ui-test-renderer") {
                return WebSnapshotModel(viewportRenderer: .uiTestFixture)
            }
        #endif
        return WebSnapshotModel()
    }

    /// The window's working document, shared with the hosted SwiftUI view.
    let model: WebSnapshotModel

    /// The data graph supplied to the window and its SwiftUI root.
    let environment: AppEnvironment
    /// The transient-feedback operation supplied to the SwiftUI root.
    let feedback: FeedbackDisplay
    /// The app-owned presentation routes supplied to the SwiftUI root.
    let presentation: WebSnapshotPresentation

    private var window: NSWindow?

    private static let defaultContentSize = NSSize(width: 1100, height: 760)
    private static let frameAutosaveName = "vitrine.web-snapshot.window"

    /// Not an `editor-window` prefix, so a key Web Snapshot window never enables the
    /// editor-scoped export commands.
    static let windowIdentifier = "web-snapshot-window"

    init(
        environment: AppEnvironment,
        model: WebSnapshotModel = WebSnapshotModel(),
        feedback: FeedbackDisplay,
        presentation: WebSnapshotPresentation
    ) {
        self.environment = environment
        self.model = model
        self.feedback = feedback
        self.presentation = presentation
        super.init()
    }

    /// Builds the SwiftUI root from the same dependencies retained by this controller.
    func makeRootView() -> WebSnapshotEditorView {
        WebSnapshotEditorView(
            model: model,
            environment: environment,
            feedback: feedback,
            presentation: presentation)
    }

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
            model.prepareForPrefillURL(prefillURL)
        }
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: makeRootView())
        let window = TitleBarAlignedWindow(contentViewController: hosting)
        window.title = String(localized: "Web Snapshot")
        window.styleMask = [
            .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
        ]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(Self.defaultContentSize)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
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

    /// Frees the large rendered images when the window closes. The window is reused
    /// (`isReleasedWhenClosed = false`), so without this a multi-viewport batch's
    /// full-resolution captures would stay resident for the app's lifetime.
    ///
    /// Cancel first: discarding alone left an in-flight capture running against a closed
    /// window, and its tail then re-seated the very assets this just cleared.
    func windowWillClose(_ notification: Notification) {
        model.cancelRender()
        model.discardRenderedAssets()
    }
}
