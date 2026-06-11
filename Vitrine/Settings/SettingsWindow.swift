import AppKit
import SwiftUI

/// Owns and presents the redesigned preferences window (design/handoff).
///
/// The window is a fixed 720×600 card hosting `SettingsRootView` — a sidebar
/// of panes on the left and the active pane on the right. The title bar is
/// transparent and merged into the content (the sidebar runs to the top, under
/// the traffic lights), matching the handoff reference while keeping the
/// standard close control.
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private var window: NSWindow?

    private init() {}

    /// Shows the preferences window and brings the app forward.
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        // Built directly (not via `NSWindow(contentViewController:)`) so the
        // hosting view never re-derives the frame: with the transparent,
        // full-size title bar the content IS the whole 720×600 window.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(
            rootView: SettingsRootView(settings: .shared, presets: .shared, themes: .shared)
                .ignoresSafeArea())
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // The visible title is hidden; this names the window for the window
        // menu, Mission Control, and accessibility.
        window.title = String(localized: "Settings")
        window.isMovableByWindowBackground = true
        // Kept alive for reuse: closing hides it, reopening shows the same
        // window with its pane selection intact.
        window.isReleasedWhenClosed = false
        // The root view is width-fixed but height-flexible, so the frame set
        // here is authoritative: 720×600 of content with the title bar overlaid.
        window.setFrame(NSRect(x: 0, y: 0, width: 720, height: 600), display: false)
        window.center()
        return window
    }
}
