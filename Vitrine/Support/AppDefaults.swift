import Foundation

/// Resolves the app's defaults store.
///
/// UI tests can set `VITRINE_USER_DEFAULTS_SUITE` to isolate preferences and
/// recents from a developer's real app data while still exercising persistence.
enum AppDefaults {
    static var current: UserDefaults {
        let suiteName = ProcessInfo.processInfo.environment["VITRINE_USER_DEFAULTS_SUITE"]
        guard let suiteName, !suiteName.isEmpty else { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}
