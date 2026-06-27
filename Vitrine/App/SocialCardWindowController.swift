import AppKit
import SwiftUI

/// Owns the app's single social-card editor window (CS-041).
///
/// Unlike the multi-window code editor (CS-053), the social card is an app-global
/// document: there is one working card, persisted in `AppSettings.shared.socialCard`,
/// so this controller keeps exactly one reusable window rather than a keyed set. The
/// window hosts ``SocialCardEditorView``, which composes and exports the card entirely
/// locally — `ImageRenderer`, never WebKit or the network.
///
/// The window is reused across opens *and* closes (`isReleasedWhenClosed = false`), so
/// reopening is instant and the frame the user dialed in survives within a launch and,
/// via frame autosave, across launches. The working card itself survives through
/// `AppSettings`, so the window carries no document state of its own and needs no
/// secure state restoration.
@MainActor
final class SocialCardWindowController: NSObject {
    static let shared = SocialCardWindowController()

    /// The single reused window, created on first show and kept alive across closes.
    private var window: NSWindow?

    /// The opening content size: wide enough for the 1200×630 preview stage beside the
    /// card inspector. A window restored from a saved frame overrides this.
    private static let defaultContentSize = NSSize(width: 1080, height: 720)

    /// AppKit frame-autosave name, so the window reopens where the user left it.
    private static let frameAutosaveName = "vitrine.social-card.window"

    /// The window's accessibility identifier. Deliberately *not* an `editor-window`
    /// prefix, so a key social-card window never enables the editor-scoped export
    /// commands (`EditorCommandResponder.isEditorKey` matches that prefix).
    static let windowIdentifier = "social-card-window"

    private override init() { super.init() }

    /// Shows the social-card window, creating it the first time, and focuses it. This
    /// is the entry the File-menu "New Social Card" command uses, so it reuses the one
    /// window rather than stacking duplicates.
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Builds the AppKit window hosting a ``SocialCardEditorView`` bound to the shared
    /// settings, so it edits the app-global working card (CS-041).
    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: SocialCardEditorView().environment(AppSettings.shared))
        let window = TitleBarAlignedWindow(contentViewController: hosting)
        window.title = String(localized: "Social Card")
        window.styleMask = [
            .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
        ]
        // Merge the title bar into the editor's glass toolbar, like the code editor:
        // the traffic lights float over the toolbar's leading edge (design/handoff).
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(Self.defaultContentSize)
        // Reused, never auto-released on close, so reopening is instant and preserves
        // the window's frame within a launch.
        window.isReleasedWhenClosed = false
        // Not a tabbed-document app: keep this standalone even when the user's "prefer
        // tabs when opening documents" preference is Always.
        window.tabbingMode = .disallowed
        window.setAccessibilityIdentifier(Self.windowIdentifier)

        // Restore size/position across launches. On a brand-new window with no saved
        // frame, cap the default to the screen it opens on — a wide default can
        // overhang a small display (e.g. 1024×768) and strand the trailing controls —
        // then center it. A window with a saved frame keeps the restored position.
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
