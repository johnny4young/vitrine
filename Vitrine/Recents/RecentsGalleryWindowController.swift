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
        if let window {
            if let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
                var availableFrame = visibleFrame
                #if DEBUG
                    // Forces the compact action-bar layout in UI automation without
                    // coupling the assertion to the test machine's display width.
                    if let rawWidth = ProcessInfo.processInfo.environment[
                        "VITRINE_RECENTS_TEST_MAX_WIDTH"
                    ], let requestedWidth = Double(rawWidth), requestedWidth > 0 {
                        let width = min(CGFloat(requestedWidth), visibleFrame.width)
                        availableFrame.origin.x = visibleFrame.midX - width / 2
                        availableFrame.size.width = width
                    }
                #endif
                window.setFrame(
                    WindowFrameSolver.clamp(window.frame, into: availableFrame), display: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
