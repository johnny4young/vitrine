import AppKit
import KeyboardShortcuts
import VitrineDomain

/// Global keyboard shortcuts, persisted by the KeyboardShortcuts package.
///
/// With the module's default actor isolation set to `MainActor`, these statics are
/// main-actor isolated and need no `Sendable`/`nonisolated(unsafe)` annotations.
extension KeyboardShortcuts.Name {
    /// New installations opt in through the recorder. Existing assignments are
    /// retained by the migration before the preferences graph is constructed.
    static let quickCapture: Self = {
        #if DEBUG
            // Recorder journeys must not change a developer's real global shortcut.
            if let suite = ProcessInfo.processInfo.environment["VITRINE_USER_DEFAULTS_SUITE"],
                !suite.isEmpty
            {
                return Self("quickCapture.ui-test.\(suite)")
            }
        #endif
        return Self("quickCapture")
    }()

    /// Open the editor window.
    static let openEditor = Self("openEditor")
}

/// Installation-local policy, intentionally not part of exportable style settings.
/// Run before SettingsSchema stamps an otherwise empty first-launch store.
enum GlobalShortcutMigration {
    static let policyKey = "quickCaptureShortcutPolicyVersion"
    // KeyboardShortcuts' pinned persistence format. Compatibility is checked by
    // decoding the saved value through its public Shortcut type in tests.
    static let shortcutKey = "KeyboardShortcuts_quickCapture"

    static func prepare(in defaults: UserDefaults) {
        guard defaults.integer(forKey: policyKey) < 1 else { return }
        let existingInstallation =
            defaults.object(forKey: SettingsSchema.versionKey) != nil
            || SettingsCodec.Keys.all.contains { defaults.object(forKey: $0) != nil }
        // Presence, not getShortcut(), preserves explicit false and malformed data.
        // Neither an upgrade nor a later reset should silently reactivate a shortcut.
        if existingInstallation, defaults.object(forKey: shortcutKey) == nil {
            let previousDefault = KeyboardShortcuts.Shortcut(.s, modifiers: [.command, .shift])
            guard let data = try? JSONEncoder().encode(previousDefault),
                let encoded = String(data: data, encoding: .utf8)
            else { return }
            defaults.set(encoded, forKey: shortcutKey)
        }
        defaults.set(1, forKey: policyKey)
    }
}
