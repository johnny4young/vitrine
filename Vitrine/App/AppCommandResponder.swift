import AppKit

/// Performs the app-scoped commands (New Capture, Open Editor, Settings, Help,
/// About) from the main menu. A small `@objc` target rather than free functions
/// so menu items can wire to selectors and AppKit's standard validation applies.
final class AppCommandResponder: NSObject {
    let environment: AppEnvironment
    let feedback: CaptureFeedbackPresenter

    init(
        environment: AppEnvironment,
        feedback: CaptureFeedbackPresenter
    ) {
        self.environment = environment
        self.feedback = feedback
        super.init()
    }

    @objc func newCaptureFromClipboard(_ sender: Any?) {
        QuickCapture.perform(environment: environment, feedback: feedback)
    }

    @objc func openEditor(_ sender: Any?) {
        EditorWindowController.shared.show()
    }

    /// Opens an additional, independent editor window.
    @objc func newEditorWindow(_ sender: Any?) {
        EditorWindowController.shared.openNewWindow()
    }

    /// Opens the social-card editor — the local 1200×630 card composer.
    @objc func openSocialCardEditor(_ sender: Any?) {
        SocialCardWindowController.shared.show()
    }

    /// Opens the Web Snapshot editor — local HTML rendering and gated URL capture.
    /// Routed through `WebSnapshotPresenter` so this command surface
    /// carries no dependency on the WebKit-backed window (which the CLI excludes).
    @objc func openWebSnapshotEditor(_ sender: Any?) {
        WebSnapshotPresenter.show()
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowManager.shared.show()
    }

    @objc func showHelp(_ sender: Any?) {
        HelpWindowController.shared.show()
    }

    @objc func showWhatsNew(_ sender: Any?) {
        WhatsNewWindowController.shared.show(settings: environment.appSettings)
    }

    @objc func showAbout(_ sender: Any?) {
        AboutPanel.present()
    }

    /// Restyles the key editor window's theme from the View ▸ Theme submenu (or the
    /// app-wide default when no editor is key), so a theme is one click from the menu
    /// bar. The chosen theme id rides on the menu item's `representedObject`.
    @objc func selectTheme(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let themeID = item.representedObject as? String
        else { return }
        let theme = environment.customThemes.theme(withID: themeID)
        let target =
            EditorWindowController.shared.keyWindowSession?.settings ?? environment.appSettings
        target.config.theme = theme
    }

    /// Starts a user-initiated update check on the direct-download build. The
    /// menu item that targets this is only added on a build that ships Sparkle, so on the
    /// App Store build (which excludes Sparkle) there is no item and `checkForUpdates()`
    /// degrades to a no-op.
    @objc func checkForUpdates(_ sender: Any?) {
        SoftwareUpdater.shared.checkForUpdates()
    }
}
