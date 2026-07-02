import Foundation

/// The one place a copy/save/share outcome turns into HUD feedback.
///
/// The code editor, the social-card editor, and the web-snapshot editor expose
/// the same three actions; each used to re-implement the outcome → HUD mapping
/// (and its localized strings) inline, and the copies had drifted. Routing all
/// three through one presenter keeps the strings, the cancelled-save-is-silent
/// rule, and the feedback behavior in a single reviewable spot.
enum ExportFeedback {
    /// Presents the copy outcome: a confirmation on success, a failure otherwise.
    static func presentCopy(_ copied: Bool) {
        CaptureHUDController.shared.present(
            copied
                ? Notifier.confirmation(String(localized: "Image copied to clipboard"))
                : Notifier.failure(String(localized: "Couldn't copy the image")))
    }

    /// Presents the save outcome. A cancelled panel is deliberately silent — the
    /// user changed their mind; there is nothing to confirm or apologize for.
    static func presentSave(_ outcome: ExportManager.SaveOutcome) {
        switch outcome {
        case .saved:
            CaptureHUDController.shared.present(
                Notifier.confirmation(String(localized: "Image saved")))
        case .failed:
            CaptureHUDController.shared.present(
                Notifier.failure(String(localized: "Couldn't save the image")))
        case .cancelled:
            break
        }
    }

    /// Presents a share failure. Success needs no HUD — the share sheet itself
    /// is the feedback.
    static func presentShareFailure() {
        CaptureHUDController.shared.present(
            Notifier.failure(String(localized: "Couldn't share the image")))
    }
}
