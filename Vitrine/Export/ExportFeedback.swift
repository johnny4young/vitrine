import Foundation
import VitrineRendering

/// The one place a copy/save/share outcome maps to transient feedback.
///
/// Callers present the returned feedback themselves; keeping the mapping here keeps
/// the localized strings and the cancelled-save-is-silent rule in one spot.
enum ExportFeedback {
    /// `pngBytes` is the size of the PNG that reached the clipboard, when the caller knows it.
    static func copyOutcome(
        _ outcome: ExportManager.CopyOutcome, pngBytes: Int? = nil
    ) -> Notifier.CaptureFeedback {
        switch outcome {
        case .copied:
            Notifier.confirmation(
                String(localized: "Image copied to clipboard"),
                detail: pngBytes.map(Notifier.Detail.copiedPNG(bytes:)))
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
        _ outcome: ExportManager.SaveOutcome, embedding plan: EmbeddedProject.Plan = .off
    ) -> Notifier.CaptureFeedback? {
        switch (outcome, plan) {
        case (.saved, .withheld(let reason)):
            Notifier.confirmation(String(localized: "Image saved"), detail: withheldDetail(reason))
        case (.saved, _):
            Notifier.confirmation(String(localized: "Image saved"))
        case (.failed, _):
            Notifier.failure(String(localized: "Couldn't save the image"))
        case (.renderFailed(let error), _):
            renderFailure(error)
        case (.cancelled, _):
            nil
        }
    }

    /// Names why an opted-in save went out without its editable project.
    static func withheldDetail(_ reason: EmbeddedProject.Withheld) -> Notifier.Detail {
        let text =
            switch reason {
            case .redactedLines:
                String(localized: "Editable project left out: the capture has redacted lines")
            case .blurBoxes:
                String(localized: "Editable project left out: the capture has blur boxes")
            case .terminal:
                String(localized: "Editable project left out: terminal captures are never embedded")
            case .secret:
                String(localized: "Editable project left out: it may contain a secret")
            case .tooLarge:
                String(localized: "Editable project left out: it's too large")
            }
        return Notifier.Detail(text: text, spokenText: text)
    }

    static var shareFailure: Notifier.CaptureFeedback {
        Notifier.failure(String(localized: "Couldn't share the image"))
    }

    static func renderFailure(_ error: RenderBudgetError) -> Notifier.CaptureFeedback {
        Notifier.renderFailure(error)
    }
}
