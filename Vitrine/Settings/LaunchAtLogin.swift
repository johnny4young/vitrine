import ServiceManagement

/// Wraps `SMAppService.mainApp` for "launch at login" (CS-014) — the modern
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

    /// Registers or unregisters the login item. Errors are swallowed for now;
    /// surfacing them in the UI is future work.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Ignore: typically an unsigned/dev build or a pending approval.
        }
    }
}
