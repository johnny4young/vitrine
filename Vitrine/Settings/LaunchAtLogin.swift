import OSLog
import ServiceManagement

/// Wraps `SMAppService.mainApp` for "launch at login" — the modern
/// ServiceManagement API, not the deprecated `SMLoginItemSetEnabled`.
enum LaunchAtLogin {
    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        isEnabled(for: SMAppService.mainApp.status)
    }

    /// Pure mapping of a service status to an enabled flag (unit-testable).
    static func isEnabled(for status: SMAppService.Status) -> Bool {
        status == .enabled
    }

    /// Registers or unregisters the login item. Failures are logged without user data;
    /// the system status remains the source of truth shown by the settings control.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let nsError = error as NSError
            Log.settings.error(
                "Launch-at-login update failed (\(nsError.domain, privacy: .public):\(nsError.code, privacy: .public))"
            )
        }
    }
}
