import Combine
import Foundation

/// Turns a quick-capture `Result` into the right on-screen feedback and performs
/// any recovery action the user chooses (CS-038).
///
/// This is the side-effecting counterpart to the pure `Notifier` policy: it asks
/// `Notifier` what to say, then presents it through the in-app `CaptureHUD` so
/// Notification Center is *not* used for routine success (CS-038 acceptance:
/// "Notification Center is not used repeatedly for routine success if an in-app
/// HUD is available."). Notification Center remains a fallback for when the HUD
/// cannot be shown. The most recent feedback is published so the menu-bar menu can
/// echo the last outcome and offer the same recovery actions there.
@MainActor
final class CaptureFeedbackPresenter: ObservableObject {
    static let shared = CaptureFeedbackPresenter()

    /// The most recent capture feedback, for the menu-bar surface (CS-038). The
    /// menu shows this as a status line plus any inline recovery actions, so the
    /// last result stays reachable after the transient HUD fades.
    @Published private(set) var lastFeedback: Notifier.CaptureFeedback?

    /// The URL detected by the last capture, if any — the payload the "Render as
    /// Text" recovery acts on. Never logged (CS-048 privacy rule).
    private var pendingURLText: String?

    private let hud: CaptureHUDController
    private let settingsProvider: () -> AppSettings

    init(
        hud: CaptureHUDController = .shared,
        settings: @escaping @autoclosure () -> AppSettings = .shared
    ) {
        self.hud = hud
        self.settingsProvider = settings
    }

    /// Presents feedback for a completed capture `result` (CS-038).
    ///
    /// `settings` is the same settings instance the capture ran against, used to
    /// re-render on a recovery action. Routine success shows the HUD only; dead
    /// ends (empty clipboard, deferred URL) show the HUD with inline recovery
    /// buttons.
    func present(_ result: QuickCapture.Result, settings: AppSettings) {
        let feedback = Notifier.feedback(
            for: result.outcome,
            copiedToClipboard: result.copiedToClipboard,
            savedToFile: result.savedToFile)

        // Remember the URL so a later "Render as Text" tap has something to render.
        if case .url(let text) = result.outcome {
            pendingURLText = text
        } else {
            pendingURLText = nil
        }

        lastFeedback = feedback
        hud.present(feedback) { [weak self] action in
            self?.run(action, settings: settings)
        }
    }

    /// Runs a recovery action the user picked from the HUD or the menu (CS-038).
    func run(_ action: Notifier.RecoveryAction, settings: AppSettings? = nil) {
        let settings = settings ?? settingsProvider()
        switch action {
        case .openEditor:
            // The deferred capture's combined source lives in `settings.config`; load
            // it into the primary editor so the "Open Editor" recovery surfaces it even
            // if the editor is already open (CS-027 + CS-053).
            EditorWindowController.shared.loadIntoPrimary(settings.config)
        case .renderAsText:
            renderPendingURLAsText(settings: settings)
        }
    }

    /// Renders the previously-detected URL as plain text and confirms it (CS-038).
    /// Falls back to opening the editor if there is no pending URL to render, so
    /// the action is never a no-op dead end.
    private func renderPendingURLAsText(settings: AppSettings) {
        guard let text = pendingURLText else {
            EditorWindowController.shared.show()
            return
        }
        pendingURLText = nil
        let result = QuickCapture.renderText(text, settings: settings)
        let feedback = Notifier.feedback(
            for: result.outcome,
            copiedToClipboard: result.copiedToClipboard,
            savedToFile: result.savedToFile)
        lastFeedback = feedback
        hud.present(feedback)
    }
}
