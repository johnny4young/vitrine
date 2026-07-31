import AppKit
import SwiftUI

/// Owns the single reusable Recents gallery window and supplies its complete app-owned
/// dependency graph.
final class RecentsGalleryWindowController {
    static let shared = RecentsGalleryWindowController(
        environment: .shared,
        feedback: .live,
        navigation: .live)

    let environment: AppEnvironment
    let feedback: FeedbackDisplay
    let navigation: RecentsGalleryNavigation

    private var window: NSWindow?

    init(
        environment: AppEnvironment,
        feedback: FeedbackDisplay,
        navigation: RecentsGalleryNavigation
    ) {
        self.environment = environment
        self.feedback = feedback
        self.navigation = navigation
    }

    /// Builds the SwiftUI root from the same dependencies retained by this controller.
    func makeRootView() -> RecentsGalleryView {
        RecentsGalleryView(
            environment: environment,
            feedback: feedback,
            navigation: navigation)
    }

    /// Shows (creating if needed) and focuses the Recents gallery window.
    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: makeRootView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Recents"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 560))
            window.isReleasedWhenClosed = false
            window.setAccessibilityIdentifier("recents-window")
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
