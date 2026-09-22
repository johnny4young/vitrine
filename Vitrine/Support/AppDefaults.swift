import Foundation

/// Resolves the app's defaults store.
///
/// UI tests can set `VITRINE_USER_DEFAULTS_SUITE` to isolate preferences and
/// recents from a developer's real app data while still exercising persistence.
enum AppDefaults {
    static var current: UserDefaults {
        let suiteName = ProcessInfo.processInfo.environment["VITRINE_USER_DEFAULTS_SUITE"]
        guard let suiteName, !suiteName.isEmpty else { return .standard }
        guard let defaults = UserDefaults(suiteName: suiteName) else { return .standard }
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--history-recovery-demo"),
                !defaults.bool(forKey: "historyRecoveryFixtureSeeded")
            {
                // Seed once, before the composition root reads the archive, in an
                // explicitly isolated UI-test suite only. Never touch standard defaults.
                let capture = Capture(
                    code: "Recovered sample", languageID: "swift", themeID: "one-dark")
                if let entry = try? JSONEncoder().encode(capture) {
                    var archive = Data("[".utf8)
                    archive.append(entry)
                    archive.append(Data(", {\"unfinished\":".utf8))
                    defaults.set(archive, forKey: "recentCaptures")
                    defaults.set(true, forKey: "historyRecoveryFixtureSeeded")
                }
            }
        #endif
        return defaults
    }
}
