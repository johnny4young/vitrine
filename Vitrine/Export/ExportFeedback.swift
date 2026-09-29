import Foundation
import VitrineRendering

/// The one place a copy/save/share outcome maps to transient feedback.
///
/// Callers present the returned feedback themselves; keeping the mapping here keeps
/// the localized strings and the cancelled-save-is-silent rule in one spot.
enum ExportFeedback {
    static func copyOutcome(_ outcome: ExportManager.CopyOutcome) -> Notifier.CaptureFeedback {
        switch outcome {
        case .copied:
            Notifier.confirmation(String(localized: "Image copied to clipboard"))
        case .failed:
            Notifier.failure(String(localized: "Couldn't copy the image"))
        case .renderFailed(let error):
            renderFailure(error)
        }
    }

    static func sourceCopyOutcome(_ copied: Bool) -> Notifier.CaptureFeedback {
        copied
            ? Notifier.confirmation(String(localized: "Source copied to clipboard"))
            : Notifier.failure(String(localized: "Couldn't copy the source"))
    }

    static func imageTextCopyOutcome(_ copied: Bool) -> Notifier.CaptureFeedback {
        copied
            ? Notifier.confirmation(String(localized: "Text copied from image"))
            : Notifier.failure(String(localized: "Couldn't copy text from the image"))
    }

    static func shareLinkCopyOutcome(_ copied: Bool) -> Notifier.CaptureFeedback {
        copied
            ? Notifier.confirmation(String(localized: "Share link copied"))
            : Notifier.failure(String(localized: "Couldn't copy the share link"))
    }

    static func saveOutcome(
        _ outcome: ExportManager.SaveOutcome
    ) -> Notifier.CaptureFeedback? {
        switch outcome {
        case .saved:
            Notifier.confirmation(String(localized: "Image saved"))
        case .failed:
            Notifier.failure(String(localized: "Couldn't save the image"))
        case .renderFailed(let error):
            renderFailure(error)
        case .cancelled:
            nil
        }
    }

    static var shareFailure: Notifier.CaptureFeedback {
        Notifier.failure(String(localized: "Couldn't share the image"))
    }

    static func renderFailure(_ error: RenderBudgetError) -> Notifier.CaptureFeedback {
        Notifier.renderFailure(error)
    }
}
