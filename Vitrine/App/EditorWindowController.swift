import AppKit
import SwiftUI

/// Owns the editor window (hosted SwiftUI), so it can be opened from the menu or
/// the global hotkey without depending on a SwiftUI `openWindow` environment.
final class EditorWindowController {
    static let shared = EditorWindowController()

    private var window: NSWindow?

    private init() {}

    /// Shows (creating if needed) and focuses the editor window.
    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: EditorView().environmentObject(AppSettings.shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Vitrine Editor"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 900, height: 560))
            window.isReleasedWhenClosed = false
            window.setAccessibilityIdentifier("editor-window")
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
