import AppKit
import SwiftUI

/// Owns the single session-only comparison-board window.
@MainActor
final class ComparisonBoardWindowController: NSObject, NSWindowDelegate {
    static let shared = ComparisonBoardWindowController(
        environment: .shared,
        feedback: .live,
        presentation: .live)

    let environment: AppEnvironment
    let feedback: FeedbackDisplay
    let presentation: ComparisonBoardPresentation

    private var window: NSWindow?

    static let windowIdentifier = "comparison-board-window"

    init(
        environment: AppEnvironment,
        feedback: FeedbackDisplay,
        presentation: ComparisonBoardPresentation
    ) {
        self.environment = environment
        self.feedback = feedback
        self.presentation = presentation
        super.init()
    }

    func makeDraft(captures: [Capture]) throws -> ComparisonBoardDraft {
        try ComparisonBoardDraft(
            captures: captures,
            baseConfig: environment.appSettings.exportConfig,
            profile: environment.appSettings.export.colorProfile,
            renderScale: CGFloat(environment.appSettings.export.scale))
    }

    func makeRootView(draft: ComparisonBoardDraft) -> ComparisonBoardEditorView {
        ComparisonBoardEditorView(
            draft: draft,
            environment: environment,
            feedback: feedback,
            presentation: presentation)
    }

    func show(captures: [Capture]) {
        let draft: ComparisonBoardDraft
        do {
            draft = try makeDraft(captures: captures)
        } catch ComparisonBoardDraft.CreationError.renderFailure(_, let error) {
            feedback(ExportFeedback.renderFailure(error))
            return
        } catch {
            feedback(
                Notifier.failure(
                    String(localized: "Couldn't prepare the selected captures")))
            return
        }

        window?.close()
        let hosting = NSHostingController(rootView: makeRootView(draft: draft))
        let window = TitleBarAlignedWindow(contentViewController: hosting)
        window.title = String(localized: "Comparison Board")
        window.styleMask = [
            .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
        ]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 1080, height: 720))
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setAccessibilityIdentifier(Self.windowIdentifier)
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        window = nil
    }
}
