import Foundation

/// The one place a copy/save/share outcome turns into transient feedback.
///
/// The code editor, the social-card editor, and the web-snapshot editor expose
/// the same three actions; each used to re-implement the outcome → HUD mapping
/// (and its localized strings) inline, and the copies had drifted. Routing all
/// three through one presenter keeps the strings, the cancelled-save-is-silent
/// rule, and the feedback behavior in a single reviewable spot.
enum ExportFeedback {
    static func copyOutcome(_ copied: Bool) -> Notifier.CaptureFeedback {
        copied
            ? Notifier.confirmation(String(localized: "Image copied to clipboard"))
            : Notifier.failure(String(localized: "Couldn't copy the image"))
    }

    static func sourceCopyOutcome(_ copied: Bool) -> Notifier.CaptureFeedback {
        copied
            ? Notifier.confirmation(String(localized: "Source copied to clipboard"))
            : Notifier.failure(String(localized: "Couldn't copy the source"))
    }

    static func saveOutcome(
        _ outcome: ExportManager.SaveOutcome
    ) -> Notifier.CaptureFeedback? {
        switch outcome {
        case .saved:
            Notifier.confirmation(String(localized: "Image saved"))
        case .failed:
            Notifier.failure(String(localized: "Couldn't save the image"))
        case .cancelled:
            nil
        }
    }

    static var shareFailure: Notifier.CaptureFeedback {
        Notifier.failure(String(localized: "Couldn't share the image"))
    }

    /// Presents the copy outcome: a confirmation on success, a failure otherwise.
    static func presentCopy(_ copied: Bool) {
        CaptureHUDController.shared.present(copyOutcome(copied))
    }

    /// Presents the source-copy outcome without describing plain text as an image.
    static func presentSourceCopy(_ copied: Bool) {
        CaptureHUDController.shared.present(sourceCopyOutcome(copied))
    }

    /// Presents the save outcome. A cancelled panel is deliberately silent — the
    /// user changed their mind; there is nothing to confirm or apologize for.
    static func presentSave(_ outcome: ExportManager.SaveOutcome) {
        guard let feedback = saveOutcome(outcome) else { return }
        CaptureHUDController.shared.present(feedback)
    }

    /// Presents a share failure. Success needs no HUD — the share sheet itself
    /// is the feedback.
    static func presentShareFailure() {
        CaptureHUDController.shared.present(shareFailure)
    }
}
