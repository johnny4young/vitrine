import Foundation
import UserNotifications

/// Surfaces quick-capture outcomes as tasteful, non-intrusive feedback (CS-016,
/// CS-038).
///
/// `Notifier` is the pure *policy* layer: it turns a `QuickCapture.Outcome` into a
/// `CaptureFeedback` value (a category, a human message, and any inline recovery
/// actions) and decides how that feedback should be delivered — an in-app HUD for
/// routine success, with Notification Center reserved as a fallback. The mapping
/// is deliberately free of side effects so it is unit-testable; the actual
/// presentation (the HUD window, running a recovery action) is wired up by the
/// app delegate (CS-038).
enum Notifier {
    /// What kind of feedback an outcome represents, used to pick an icon and to
    /// decide whether routine in-app confirmation is enough (CS-038).
    enum Category: Equatable {
        /// The capture succeeded and produced an image the user now has.
        case success
        /// The capture did not produce an image, but it is not an error the user
        /// must fix — e.g. several blocks were handed to the editor.
        case info
        /// The capture could not complete; the user likely needs to act.
        case failure
    }

    /// A discrete recovery action offered alongside feedback (CS-038).
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
        /// Render the detected URL as plain text instead of opening Web Snapshot.
        case renderAsText

        /// The button label shown for this action. Localized through the String
        /// Catalog (CS-047); the `accessibilityToken` below stays non-localized.
        var title: String {
            switch self {
            case .openEditor: String(localized: "Open Editor")
            case .openWebSnapshot: String(localized: "Open Web Snapshot")
            case .renderAsText: String(localized: "Render as Text")
            }
        }

        /// A stable, non-localized token for accessibility identifiers used by UI
        /// tests, so an action's control can be found regardless of its visible
        /// title (accessibility-identifier convention; CS-038).
        var accessibilityToken: String {
            switch self {
            case .openEditor: "open-editor"
            case .openWebSnapshot: "open-web-snapshot"
            case .renderAsText: "render-as-text"
            }
        }
    }

    /// A fully-resolved piece of user feedback for one capture outcome (CS-038):
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

    /// The legacy single-line message for an outcome (CS-016). Retained as the
    /// stable, side-effect-free entry point used by older tests; it now simply
    /// reads the message off the richer `feedback(for:)` value. Returns `nil` only
    /// where an outcome has no user-facing message (there are none today).
    static func message(for outcome: QuickCapture.Outcome) -> String? {
        feedback(for: outcome).message
    }

    /// Resolves the rich feedback for `outcome` (CS-038).
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
            return CaptureFeedback(
                category: .success,
                message: successMessage(copied: copiedToClipboard, saved: savedToFile),
                actions: [])
        case .url:
            // A raw `.url` outcome normally opens Web Snapshot directly from
            // `QuickCapture.perform`. If another caller surfaces it as feedback, still
            // offer a direct Web Snapshot action plus the plain-text fallback.
            return CaptureFeedback(
                category: .info,
                message: String(
                    localized: "That looks like a URL — open Web Snapshot to capture it"),
                actions: [.openWebSnapshot, .renderAsText])
        case .empty:
            // An empty clipboard is the most common dead end; route the user
            // straight to the editor rather than leaving them stuck (CS-038).
            return CaptureFeedback(
                category: .failure,
                message: String(localized: "Clipboard is empty — copy some code first"),
                actions: [.openEditor])
        case .deferredToEditor(let blocks):
            // A count-aware, localized message: the catalog carries singular and
            // plural variants per locale, and the number is formatted for the
            // user's locale (CS-047).
            return CaptureFeedback(
                category: .info,
                message: String(
                    localized: "\(blocks) code blocks found — opening the editor to choose one"),
                actions: [])
        }
    }

    /// A standalone success confirmation for a discrete, non-capture action — e.g.
    /// promoting a window's style to the app-wide default (CS-053). It reuses the
    /// HUD's success styling (a checkmark, the accent tint) so an explicit action
    /// gets explicit, transient feedback consistent with the rest of the app's
    /// microinteractions, without a Notification Center banner. Pure data, so the
    /// message is unit-testable; the presentation is wired up by the caller.
    static func confirmation(_ message: String) -> CaptureFeedback {
        CaptureFeedback(category: .success, message: message, actions: [])
    }

    /// A standalone failure notice for a discrete action that could not complete — e.g.
    /// a menu "Copy Image" / "Save Image" whose render or write failed. Reuses the HUD's
    /// failure styling so the command never silently no-ops (CS-038 "Feedback says whether
    /// output was copied, saved, shared, or blocked").
    static func failure(_ message: String) -> CaptureFeedback {
        CaptureFeedback(category: .failure, message: message, actions: [])
    }

    /// Builds the success message from what actually happened to the image, so the
    /// user is told precisely where it went: copied, saved, both, or just rendered
    /// (auto-copy off and no save) (CS-038 acceptance: "Feedback says whether
    /// output was copied, saved, shared, or blocked.").
    static func successMessage(copied: Bool, saved: Bool) -> String {
        switch (copied, saved) {
        case (true, true): String(localized: "Image copied to the clipboard and saved to a file")
        case (true, false): String(localized: "Image copied to the clipboard")
        case (false, true): String(localized: "Image saved to a file")
        case (false, false): String(localized: "Image rendered")
        }
    }

    /// Posts feedback for `outcome` (CS-016). Kept for callers that do not need
    /// the in-app HUD; it routes through Notification Center only.
    ///
    /// Routine success should prefer the in-app HUD (`CaptureHUD`) so Notification
    /// Center is not used repeatedly for ordinary captures (CS-038); the app
    /// delegate owns that decision in `CaptureFeedbackPresenter`.
    static func notify(_ outcome: QuickCapture.Outcome) {
        postNotification(feedback(for: outcome).message)
    }

    /// Posts a single Notification Center banner with `body`. No-op when
    /// notifications are unauthorized. Used as the fallback channel when no in-app
    /// HUD is available (CS-038).
    static func postNotification(_ body: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Vitrine"
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            do {
                try await center.add(request)
            } catch {
                // Don't leave a failed post completely silent; the body is non-PII
                // feedback text, but log only the error domain/code to be safe (CS-048).
                Log.app.error(
                    "Notification post failed (\((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public))"
                )
            }
        }
    }
}
