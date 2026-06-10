import AppKit
import OSLog

/// Relaunches Vitrine in a fresh process and quits the current one.
///
/// macOS resolves an app's localization once, at launch, from `AppleLanguages`. The
/// Settings language switcher writes that override immediately, but it only takes
/// effect next launch — and Vitrine is a menu-bar agent with no Dock icon, so quitting
/// and reopening by hand is non-obvious. This gives the language picker a one-click
/// "Relaunch to Apply" so the new language takes effect at once (CS-047).
enum AppRelauncher {
    /// Launches a replacement instance of the app bundle, then terminates this one. The
    /// new process reads the just-written `AppleLanguages` override and localizes
    /// accordingly. The replacement is started *before* this instance quits, so a
    /// failed launch never leaves the user with no running app.
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        Task {
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: url, configuration: configuration)
            } catch {
                // Keep this instance alive: terminating after a failed launch would
                // leave the user with no running app, breaking the guarantee above.
                // Log only the error domain/code, never a path (CS-048).
                Log.app.error(
                    "Relaunch failed; staying in the current instance (\((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public))"
                )
                return
            }
            NSApp.terminate(nil)
        }
    }
}
