import Foundation
import Observation

/// Turns a quick-capture `Result` into the right on-screen feedback and performs
/// any recovery action the user chooses.
///
/// This is the side-effecting counterpart to the pure `Notifier` policy: it asks
/// `Notifier` what to say, then presents it through the in-app `CaptureHUD`. The most
/// recent feedback is published so the menu-bar menu can echo the last outcome and
/// offer the same recovery actions there.
///
/// HUD presentation and recovery navigation enter as small operation values. The live
/// adapters bridge to the reusable AppKit window owners; this coordinator remains
/// deterministic and can be exercised without constructing UI.
@Observable
final class CaptureFeedbackPresenter {
    static let shared = CaptureFeedbackPresenter()

    /// The most recent capture feedback, for the menu-bar surface. The
    /// menu shows this as a status line plus any inline recovery actions, so the
    /// last result stays reachable after the transient HUD fades.
    private(set) var lastFeedback: Notifier.CaptureFeedback?

    /// The URL detected by the last capture, if any, prefilled by the Web Snapshot
    /// recovery. Never logged (privacy policy).
    private var pendingURLText: String?

    let display: FeedbackDisplay
    let routing: CaptureRecoveryRouting

    init(
        display: FeedbackDisplay = .live,
        routing: CaptureRecoveryRouting = .live
    ) {
        self.display = display
        self.routing = routing
    }

    /// Presents feedback for a completed capture `result`.
    ///
    /// `environment` is the same graph the capture ran against, used to re-render on a
    /// recovery action and record the result in the same recents store. Routine success
    /// shows the HUD only; dead ends show the HUD with inline recovery buttons.
    func present(_ result: QuickCapture.Result, environment: AppEnvironment) {
        let feedback = Notifier.feedback(
            for: result.outcome,
            copiedToClipboard: result.copiedToClipboard,
            savedToFile: result.savedToFile)

        if case .url(let text) = result.outcome {
            pendingURLText = text
        } else {
            pendingURLText = nil
        }

        lastFeedback = feedback
        display(feedback) { [weak self] action in
            self?.run(action, environment: environment)
        }
    }

    /// Presents an already-resolved feedback value and keeps the panel's retained
    /// status in sync with the transient HUD.
    func present(_ feedback: Notifier.CaptureFeedback) {
        pendingURLText = nil
        lastFeedback = feedback
        display(feedback)
    }

    /// Runs a recovery action the user picked from the HUD or the menu.
    func run(_ action: Notifier.RecoveryAction, environment: AppEnvironment) {
        switch action {
        case .openEditor:
            // Show, never load: the editor may hold an unsaved document.
            routing.showEditor()
        case .openWebSnapshot:
            if let text = pendingURLText {
                pendingURLText = nil
                routing.showWebSnapshot(prefillURL: text)
            } else {
                routing.showWebSnapshot()
            }
        }
    }
}
