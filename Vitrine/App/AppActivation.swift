import AppKit

/// The app's single activation call site, so the activation policy changes in one place.
enum AppActivation {
    /// Brings Vitrine forward with cooperative activation. The menu-bar helper yields to
    /// the app before a panel click, and every other caller follows a user action.
    static func bringForward() {
        NSApp.activate()
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
}
