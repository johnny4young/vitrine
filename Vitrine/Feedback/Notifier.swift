import Foundation
import VitrineRendering
import os

/// Surfaces quick-capture outcomes as tasteful, non-intrusive feedback.
///
/// `Notifier` is the pure *policy* layer: it turns a `QuickCapture.Outcome` into a
/// `CaptureFeedback` value (a category, a human message, and any inline recovery
/// actions) and decides how that feedback should be delivered — an in-app HUD for
/// routine success, with Notification Center reserved as a fallback. The mapping
/// is deliberately free of side effects so it is unit-testable; the actual
/// presentation (the HUD window, running a recovery action) is wired up by the
/// app delegate.
enum Notifier {
    /// What kind of feedback an outcome represents, used to pick an icon and to
    /// decide whether routine in-app confirmation is enough.
    enum Category: Equatable {
        /// The capture succeeded and produced an image the user now has.
        case success
        /// The capture did not produce an image, but it is not an error the user
        /// must fix — e.g. several blocks were handed to the editor.
        case info
        /// The capture could not complete; the user likely needs to act.
        case failure
    }

    /// A discrete recovery action offered alongside feedback.
    ///
    /// These are the *intents* the feedback surfaces; the app delegate maps each
    /// to a concrete handler (e.g. opening the editor). Keeping them as a small
    /// enum — rather than closures — keeps `Notifier` pure and lets tests assert
    /// exactly which actions an outcome offers.
    enum RecoveryAction: Equatable {
        /// Open the editor window so the user can paste or write code themselves.
        case openEditor
        /// Open the Web Snapshot window with the detected URL prefilled.
        case openWebSnapshot

        /// The button label shown for this action. Localized through the String
        /// Catalog; the `accessibilityToken` below stays non-localized.
        var title: String {
            switch self {
            case .openEditor: String(localized: "Open Editor")
            case .openWebSnapshot: String(localized: "Open Web Snapshot")
            }
        }

        /// A stable, non-localized token for accessibility identifiers used by UI
        /// tests, so an action's control can be found regardless of its visible
        /// title (accessibility-identifier convention).
        var accessibilityToken: String {
            switch self {
            case .openEditor: "open-editor"
            case .openWebSnapshot: "open-web-snapshot"
            }
        }
    }

    /// A fully-resolved piece of user feedback for one capture outcome:
    /// its category, a short human-readable message, and any inline recovery
    /// actions. Pure data — safe to build and assert in tests.
    struct CaptureFeedback: Equatable {
        var category: Category
        var message: String
        var actions: [RecoveryAction]

        /// An SF Symbol matching the category, for the HUD and menu surfaces.
        var systemImageName: String {
            switch category {
            case .success: "checkmark.circle.fill"
            case .info: "rectangle.stack.badge.plus"
            case .failure: "exclamationmark.triangle.fill"
            }
        }
    }

    /// The legacy single-line message for an outcome. Retained as the
    /// stable, side-effect-free entry point used by older tests; it now simply
    /// reads the message off the richer `feedback(for:)` value. Returns `nil` only
    /// where an outcome has no user-facing message (there are none today).
    static func message(for outcome: QuickCapture.Outcome) -> String? {
        feedback(for: outcome).message
    }

    /// Resolves the rich feedback for `outcome`.
    ///
    /// `copiedToClipboard` and `savedToFile` describe what actually happened with
    /// the produced image so a success message can name the destination precisely
    /// ("copied", "saved", or both) rather than guessing. They default to a
    /// copy-only success so existing call sites and tests keep their meaning.
    static func feedback(
        for outcome: QuickCapture.Outcome,
        copiedToClipboard: Bool = true,
        savedToFile: Bool = false
    ) -> CaptureFeedback {
        switch outcome {
        case .copied, .rendered:
            // With copy and save both off the capture reached only history, so it is
            // not reported as a success the user could paste.
            return CaptureFeedback(
                category: copiedToClipboard || savedToFile ? .success : .info,
                message: successMessage(copied: copiedToClipboard, saved: savedToFile),
                actions: [])
        case .renderFailed(let error):
            return renderFailure(error)
        case .url:
            // `QuickCapture.perform` opens Web Snapshot directly; another caller that
            // surfaces the outcome still offers it.
            return CaptureFeedback(
                category: .info,
                message: String(
                    localized: "That looks like a URL — open Web Snapshot to capture it"),
                actions: [.openWebSnapshot])
        case .empty:
            // An empty clipboard is the most common dead end; route the user
            // straight to the editor rather than leaving them stuck.
            return CaptureFeedback(
                category: .failure,
                message: String(localized: "Clipboard is empty — copy some code first"),
                actions: [.openEditor])
        case .deferredToEditor(let blocks):
            // A count-aware, localized message: the catalog carries singular and
            // plural variants per locale, and the number is formatted for the
            // user's locale.
            return CaptureFeedback(
                category: .info,
                message: String(
                    localized: "\(blocks) code blocks found — opening the editor to choose one"),
                actions: [])
        }
    }

    /// A standalone success confirmation for a discrete, non-capture action — e.g.
    /// promoting a window's style to the app-wide default. It reuses the
    /// HUD's success styling (a checkmark, the accent tint) so an explicit action
    /// gets explicit, transient feedback consistent with the rest of the app's
    /// microinteractions, without a Notification Center banner. Pure data, so the
    /// message is unit-testable; the presentation is wired up by the caller.
    static func confirmation(_ message: String) -> CaptureFeedback {
        CaptureFeedback(category: .success, message: message, actions: [])
    }

    /// A standalone failure notice for a discrete action that could not complete — e.g.
    /// a menu "Copy Image" / "Save Image" whose render or write failed. Reuses the HUD's
    /// failure styling so the command never silently no-ops ("Feedback says whether
    /// output was copied, saved, shared, or blocked").
    static func failure(_ message: String) -> CaptureFeedback {
        CaptureFeedback(category: .failure, message: message, actions: [])
    }

    /// Actionable, localized feedback shared by quick capture and the explicit
    /// copy/save/share surfaces for every checked render failure category.
    static func renderFailure(_ error: RenderBudgetError) -> CaptureFeedback {
        let message =
            switch error {
            case .tooLarge:
                String(
                    localized:
                        "The image is too large to render safely. Reduce the canvas size or scale.")
            case .allocationFailed:
                String(
                    localized:
                        "Vitrine couldn't allocate the image buffer. Reduce the canvas size or scale and try again."
                )
            case .encodingFailed:
                String(localized: "Vitrine couldn't encode the selected image format.")
            case .cancelled:
                String(localized: "Rendering was cancelled.")
            }
        return failure(message)
    }

    /// Builds the success message from what actually happened to the image, so the
    /// user is told precisely where it went: copied, saved, both, or just rendered
    /// (auto-copy off and no save) ( "Feedback says whether
    /// output was copied, saved, shared, or blocked.").
    static func successMessage(copied: Bool, saved: Bool) -> String {
        switch (copied, saved) {
        case (true, true): String(localized: "Image copied to the clipboard and saved to a file")
        case (true, false): String(localized: "Image copied to the clipboard")
        case (false, true): String(localized: "Image saved to a file")
        case (false, false):
            String(
                localized:
                    "Nothing was copied or saved. Turn on Copy or Save in Settings ▸ Export.")
        }
    }
}
