import AppKit
import SwiftUI

/// Owns the single session-only comparison-board window.
final class ComparisonBoardWindowController: NSObject, NSWindowDelegate {
    static let shared = ComparisonBoardWindowController(
        environment: .shared,
        feedback: .live,
        presentation: .live(environment: .shared, feedback: .live))

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
            themes: environment.recents.themeLookup,
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

    func makeVariantDraft(of capture: Capture) throws -> ComparisonBoardDraft {
        let recents = environment.recents
        return try ComparisonBoardDraft(
            variantsOf: recents.document(for: capture, over: environment.appSettings.exportConfig),
            themes: ComparisonBoardDraft.variantThemes(startingWith: recents.theme(for: capture)),
            profile: environment.appSettings.export.colorProfile,
            renderScale: CGFloat(environment.appSettings.export.scale))
    }

    func show(captures: [Capture]) {
        present { try makeDraft(captures: captures) }
    }

    func showThemeVariants(of capture: Capture) {
        present { try makeVariantDraft(of: capture) }
    }

    private func present(_ makeDraft: () throws -> ComparisonBoardDraft) {
        let draft: ComparisonBoardDraft
        do {
            draft = try makeDraft()
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
        // 1080 pt is wider than a 1024 pt display; fit before centering.
        WindowPlacement.placeNew(window)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        AppActivation.bringForward()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        window = nil
    }
}
