import Foundation
import Testing

@testable import Vitrine

/// Tests for the quick-capture feedback policy and the capture HUD's
/// reduced-motion / timing behavior (CS-038).
///
/// Everything asserted here is the *pure* policy layer — the message a user sees,
/// which recovery actions an outcome offers, and whether decorative animation runs
/// — so no window is created. The actual presentation (`CaptureHUDController`,
/// `CaptureFeedbackPresenter`) is exercised manually via the menu-bar smoke
/// checklist documented at the bottom of this file.
@MainActor
@Suite("Notifier feedback policy")
struct NotifierFeedbackTests {

    // MARK: Legacy single-line messages (CS-016 compatibility)

    @Test func legacyMessagesAreStable() {
        #expect(Notifier.message(for: .copied) != nil)
        #expect(Notifier.message(for: .rendered) != nil)
        #expect(Notifier.message(for: .empty)?.localizedCaseInsensitiveContains("empty") == true)
        #expect(Notifier.message(for: .url("x"))?.localizedCaseInsensitiveContains("url") == true)
        #expect(Notifier.message(for: .deferredToEditor(blocks: 2)) != nil)
    }

    // MARK: Categories

    @Test func copiedIsSuccess() {
        #expect(Notifier.feedback(for: .copied).category == .success)
        #expect(Notifier.feedback(for: .rendered).category == .success)
    }

    @Test func emptyClipboardIsFailure() {
        #expect(Notifier.feedback(for: .empty).category == .failure)
    }

    @Test func urlAndDeferredAreInformational() {
        #expect(Notifier.feedback(for: .url("https://example.com")).category == .info)
        #expect(Notifier.feedback(for: .deferredToEditor(blocks: 3)).category == .info)
    }

    // MARK: Destination-aware success copy
    //
    // CS-038 acceptance: "Feedback says whether output was copied, saved, shared,
    // or blocked." The success message names exactly what happened to the image.

    @Test func successMessageNamesTheDestination() {
        #expect(
            Notifier.successMessage(copied: true, saved: false)
                .localizedCaseInsensitiveContains("clipboard"))
        #expect(
            Notifier.successMessage(copied: false, saved: true)
                .localizedCaseInsensitiveContains("saved"))
        let both = Notifier.successMessage(copied: true, saved: true)
        #expect(both.localizedCaseInsensitiveContains("clipboard"))
        #expect(both.localizedCaseInsensitiveContains("saved"))
        // Neither copied nor saved still reads as a produced image, not an error.
        #expect(!Notifier.successMessage(copied: false, saved: false).isEmpty)
    }

    @Test func feedbackThreadsCopiedAndSavedIntoTheMessage() {
        let copiedAndSaved = Notifier.feedback(
            for: .copied, copiedToClipboard: true, savedToFile: true)
        #expect(copiedAndSaved.message.localizedCaseInsensitiveContains("saved"))

        let savedOnly = Notifier.feedback(
            for: .rendered, copiedToClipboard: false, savedToFile: true)
        #expect(savedOnly.message.localizedCaseInsensitiveContains("saved"))
        #expect(savedOnly.category == .success)
    }

    // MARK: Standalone action confirmation (CS-053)
    //
    // "Make This Window the Default" is an explicit action that changes nothing on
    // screen, so it confirms through the shared HUD. The confirmation reuses the
    // success styling and carries no recovery actions — it is a glance, not a prompt.

    @Test func confirmationCarriesItsMessageAsSuccessWithNoActions() {
        let feedback = Notifier.confirmation("Set as the default style")
        #expect(feedback.category == .success)
        #expect(feedback.message == "Set as the default style")
        #expect(feedback.actions.isEmpty)
        // The success category resolves to a checkmark glyph, the same affordance
        // routine capture success uses.
        #expect(feedback.systemImageName == "checkmark.circle.fill")
    }

    // MARK: Recovery actions (failure recovery)
    //
    // CS-038 acceptance: an empty clipboard or a deferred URL must offer the user a
    // way forward rather than leaving them stuck.

    @Test func emptyClipboardOffersTheEditor() {
        #expect(Notifier.feedback(for: .empty).actions == [.openEditor])
    }

    @Test func deferredURLOffersRenderAsTextAndEditor() {
        // Product Phase 2 deferral: until URL screenshot capture ships, the user
        // can render the URL as text or open the editor.
        let actions = Notifier.feedback(for: .url("https://example.com")).actions
        #expect(actions.contains(.renderAsText))
        #expect(actions.contains(.openEditor))
    }

    @Test func routineSuccessHasNoRecoveryActions() {
        #expect(Notifier.feedback(for: .copied).actions.isEmpty)
        #expect(Notifier.feedback(for: .rendered).actions.isEmpty)
    }

    // MARK: Icons

    @Test func eachCategoryHasASymbol() {
        #expect(!Notifier.feedback(for: .copied).systemImageName.isEmpty)
        #expect(!Notifier.feedback(for: .empty).systemImageName.isEmpty)
        #expect(!Notifier.feedback(for: .url("x")).systemImageName.isEmpty)
    }

    // MARK: Recovery-action metadata

    @Test func recoveryActionTitlesAreHumanReadable() {
        #expect(!Notifier.RecoveryAction.openEditor.title.isEmpty)
        #expect(!Notifier.RecoveryAction.renderAsText.title.isEmpty)
    }

    @Test func recoveryActionAccessibilityTokensAreStableAndNonLocalized() {
        // Accessibility identifiers must not be localized (UI tests rely on them).
        #expect(Notifier.RecoveryAction.openEditor.accessibilityToken == "open-editor")
        #expect(Notifier.RecoveryAction.renderAsText.accessibilityToken == "render-as-text")
    }
}

/// Reduced-motion and timing behavior of the capture HUD (CS-038).
@MainActor
@Suite("CaptureHUD behavior")
struct CaptureHUDBehaviorTests {

    // CS-038 acceptance: "Reduced Motion disables decorative animation while
    // keeping status feedback." The animation is gated; the feedback itself (the
    // message/category) is independent of motion and always present.

    @Test func reduceMotionDisablesDecorativeAnimation() {
        #expect(CaptureHUD.shouldAnimate(reduceMotion: true) == false)
        #expect(CaptureHUD.shouldAnimate(reduceMotion: false) == true)
    }

    @Test func statusFeedbackIsIndependentOfMotion() {
        // The same feedback is produced regardless of the motion setting; only the
        // animation flag differs. Build the view both ways and confirm the message
        // is unchanged (the status survives a reduced-motion presentation).
        let feedback = Notifier.feedback(for: .copied)
        let animated = CaptureHUDView(feedback: feedback, animate: true) { _ in }
        let still = CaptureHUDView(feedback: feedback, animate: false) { _ in }
        #expect(animated.feedback.message == still.feedback.message)
        #expect(animated.feedback.message == feedback.message)
    }

    // CS-038: routine confirmations are brief; feedback offering recovery actions
    // lingers long enough to click one.

    @Test func feedbackWithActionsStaysLonger() {
        let routine = CaptureHUD.displayDuration(hasActions: false)
        let withActions = CaptureHUD.displayDuration(hasActions: true)
        #expect(withActions > routine)
    }

    @Test func routineConfirmationIsBrief() {
        // "non-intrusive visual confirmation in under one second" — the entrance is
        // immediate and the dwell is short; assert the routine dwell is well under
        // the lingering, action-bearing duration and not an alert-length hold.
        #expect(CaptureHUD.displayDuration(hasActions: false) <= .seconds(2))
    }
}

/// The save-outcome plumbing that lets feedback name a real save vs. a cancel or
/// failure (CS-038), exercised through the quick-capture `Result` rather than the
/// interactive save panel.
@MainActor
@Suite("Capture result destinations", .serialized)
struct CaptureResultDestinationTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "VitrineNotifierTests-\(UUID().uuidString)")!
    }

    @Test func copyOnlyResultReportsCopiedNotSaved() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.autoCopy = true
        settings.alsoSaveToFile = false
        let result = QuickCapture.capture(
            settings: settings,
            recents: RecentsStore(defaults: freshDefaults()),
            clipboard: { "let x = 1" })
        #expect(result.outcome == .copied)
        #expect(result.copiedToClipboard)
        #expect(!result.savedToFile)
    }

    @Test func autoCopyOffReportsRenderedAndOffersNoSave() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.autoCopy = false
        settings.alsoSaveToFile = false
        let result = QuickCapture.capture(
            settings: settings,
            recents: RecentsStore(defaults: freshDefaults()),
            clipboard: { "let x = 1" })
        #expect(result.outcome == .rendered)
        #expect(!result.copiedToClipboard)
        #expect(!result.savedToFile)
        // The feedback for this result still reads as success, not a failure.
        #expect(
            Notifier.feedback(
                for: result.outcome, copiedToClipboard: result.copiedToClipboard,
                savedToFile: result.savedToFile
            ).category == .success)
    }

    @Test func nonProducingOutcomesReportNeitherCopiedNorSaved() {
        let settings = AppSettings(defaults: freshDefaults())
        let result = QuickCapture.capture(
            settings: settings,
            recents: RecentsStore(defaults: freshDefaults()),
            clipboard: { nil })
        #expect(result.outcome == .empty)
        #expect(!result.copiedToClipboard)
        #expect(!result.savedToFile)
    }

    @Test func saveOutcomeEnumDistinguishesStates() {
        // The exporter reports a written file apart from a cancel or a failure so
        // feedback can be precise (CS-038).
        #expect(ExportManager.SaveOutcome.saved != .cancelled)
        #expect(ExportManager.SaveOutcome.failed != .saved)
    }
}

// MARK: - Manual menu-bar smoke checklist (CS-038)
//
// These steps are verified by hand on a real menu-bar build; they are recorded
// here so the checklist lives next to the automated coverage.
//
//  1. Copy a code snippet, fire the global hotkey. A success HUD appears near the
//     menu bar in well under a second and reads "Image copied to the clipboard".
//  2. Enable "Also save to file" and repeat. The HUD names both destinations and
//     a save panel appears; after saving, the menu's "Last capture" line matches.
//  3. Clear the clipboard, fire the hotkey. The HUD reads "Clipboard is empty…"
//     and shows an "Open Editor" button; clicking it opens the editor. The same
//     action is offered under "Last capture" in the menu.
//  4. Enable URL → screenshot, copy a URL, fire the hotkey. The HUD offers
//     "Render as Text" and "Open Editor"; "Render as Text" frames the URL string.
//  5. Turn on System Settings ▸ Accessibility ▸ Display ▸ Reduce motion. Repeat
//     step 1: the HUD still appears with its status but does not slide/scale in.
//  6. Fire several captures in quick succession. HUDs replace one another; windows
//     never stack, and Notification Center is not spammed for routine success.
