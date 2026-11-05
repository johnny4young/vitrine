import AppKit

/// The app's single activation call site, so the activation policy changes in one place.
enum AppActivation {
    /// Brings Vitrine forward. Cooperative `NSApp.activate()` is refused while another
    /// app stays active (Terminal running `render --edit`, a global hotkey, Services),
    /// which leaves the new window behind it, so this keeps the forcing call.
    static func bringForward() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Whether activation should go back to `previousProcessID` after a Vitrine surface
    /// closes. A visible Vitrine window, or another app the user already switched to,
    /// keeps the current focus.
    static func shouldRestoreFocus(
        previousProcessID: pid_t?,
        appIsActive: Bool,
        hasVisibleAppWindow: Bool,
        appProcessID: pid_t = ProcessInfo.processInfo.processIdentifier,
        helperProcessID: pid_t? = nil
    ) -> Bool {
        guard let previousProcessID, appIsActive, !hasVisibleAppWindow else { return false }
        return previousProcessID != appProcessID && previousProcessID != helperProcessID
    }

    /// The app to return focus to: the frontmost one, unless it is Vitrine or its helper.
    static func frontmostOtherApplication(helperProcessID: pid_t? = nil) -> NSRunningApplication? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
            frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            frontmost.processIdentifier != helperProcessID
        else { return nil }
        return frontmost
    }

    /// Whether a regular Vitrine window (one that can become main) is on screen. Panels
    /// such as the HUD, the popover, and the status-item anchor never count.
    static var hasVisibleAppWindow: Bool {
        NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
    }

    /// Returns activation to `previous` when nothing in Vitrine needs it any more.
    static func restoreFocus(to previous: NSRunningApplication?, helperProcessID: pid_t? = nil) {
        guard
            let previous,
            !previous.isTerminated,
            shouldRestoreFocus(
                previousProcessID: previous.processIdentifier,
                appIsActive: NSApp.isActive,
                hasVisibleAppWindow: hasVisibleAppWindow,
                helperProcessID: helperProcessID)
        else { return }
        previous.activate()
    }

    /// Whether to go back to `previousProcessID` after a prompt that interrupted it. Unlike
    /// closing a surface, a visible Vitrine window is no reason to keep focus here.
    static func shouldReturnFocusAfterPrompt(
        previousProcessID: pid_t?,
        appIsActive: Bool,
        appProcessID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> Bool {
        guard let previousProcessID, appIsActive else { return false }
        return previousProcessID != appProcessID
    }
}

/// Holds the app a capture interrupted until all of that capture's prompts are answered.
/// Activation is asynchronous, so returning between prompts would leave the next one
/// reading Vitrine as the frontmost app and losing the real target.
final class PromptFocus {
    private let returnFocus: () -> Void
    private var didAsk = false

    init(returnFocus: @escaping () -> Void) {
        self.returnFocus = returnFocus
    }

    convenience init(returningTo previous: NSRunningApplication?) {
        self.init {
            guard let previous, !previous.isTerminated,
                AppActivation.shouldReturnFocusAfterPrompt(
                    previousProcessID: previous.processIdentifier, appIsActive: NSApp.isActive)
            else { return }
            previous.activate()
        }
    }

    func asking<Answer>(_ prompt: () -> Answer) -> Answer {
        didAsk = true
        return prompt()
    }

    func finish() {
        guard didAsk else { return }
        didAsk = false
        returnFocus()
    }
}
