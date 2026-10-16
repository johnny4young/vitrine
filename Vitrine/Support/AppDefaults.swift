import Foundation

/// Resolves the app's defaults store.
///
/// UI tests can set `VITRINE_USER_DEFAULTS_SUITE` to isolate preferences and
/// recents from a developer's real app data while still exercising persistence.
enum AppDefaults {
    /// Followed by newline-separated suite names, asks a Debug launch to delete those
    /// suites. Harnesses send it once a run ends: the UI-test runner is sandboxed away
    /// from the app's container, and a suite must outlive individual launches so
    /// relaunch tests can read it back.
    static let purgeSuiteArgument = "--purge-user-defaults-suite"
    /// Keeps a purge launch alive until it is terminated; XCUIApplication fails a launch
    /// whose process exits on its own.
    static let purgeStayRunningArgument = "--purge-stay-running"
    /// Posted with the last purged suite as its object; the sandboxed runner cannot read
    /// the exit status or the container, so this is its proof.
    static let suitePurgedNotification = Notification.Name(
        "com.johnny4young.vitrine.ui-test.defaults-suite-purged")
    /// cfprefsd persists a killed process's pending writes about ten seconds after its
    /// last write, even over a deleted plist, so a purge keeps deleting for this long.
    static let purgeSettleDuration = Duration.seconds(15)

    static var current: UserDefaults {
        // A purge launch must not write any suite back, whichever object asks first.
        if isPurgeLaunchProcess { return InMemoryUserDefaults() }
        let suiteName = ProcessInfo.processInfo.environment["VITRINE_USER_DEFAULTS_SUITE"]
        guard let suiteName, !suiteName.isEmpty else { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Arguments never change at runtime, and `applicationWillUpdate` asks on every event.
    static let isPurgeLaunchProcess = isPurgeLaunch()

    static func isPurgeLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
            arguments.contains(purgeSuiteArgument)
        #else
            false
        #endif
    }

    /// Harness suites end in a UUID, so a purge can never reach a real preferences domain,
    /// and contain no path separator, so it never leaves the Preferences directory.
    static func isTestScoped(_ suite: String) -> Bool {
        suite.count > 36 && !suite.contains("/")
            && UUID(uuidString: String(suite.suffix(36))) != nil
    }

    /// The suites a purge launch names, or `nil` unless every one is test-scoped.
    static func requestedSuites(arguments: [String]) -> [String]? {
        guard let flag = arguments.firstIndex(of: purgeSuiteArgument),
            arguments.indices.contains(flag + 1)
        else { return nil }
        let suites = arguments[flag + 1].split(separator: "\n").map(String.init)
        guard !suites.isEmpty, suites.allSatisfy(isTestScoped) else { return nil }
        return suites
    }

    /// Deletes a test-scoped suite's plist and the shortcut it recorded in the standard
    /// store; returns whether both are gone.
    static func purge(
        suite: String,
        preferencesDirectory: URL = .libraryDirectory.appending(path: "Preferences"),
        standard: UserDefaults = .standard
    ) -> Bool {
        guard isTestScoped(suite) else { return false }
        let shortcutKey = GlobalShortcutMigration.uiTestShortcutKey(suite: suite)
        standard.removeObject(forKey: shortcutKey)
        // Delete the file only: `removePersistentDomain` makes cfprefsd write an empty
        // plist back about ten seconds later, even after a synchronize.
        let file = preferencesDirectory.appending(path: "\(suite).plist")
        try? FileManager.default.removeItem(at: file)
        return !FileManager.default.fileExists(atPath: file.path)
            && standard.object(forKey: shortcutKey) == nil
    }

    /// Starts a purge launch's request. It reports success once the settle window has
    /// passed, then exits unless asked to stay running; any failure exits with status 1.
    static func performPurgeRequest(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard isPurgeLaunch(arguments: arguments) else { return }
        guard let suites = requestedSuites(arguments: arguments) else { exit(1) }
        let stayRunning = arguments.contains(purgeStayRunningArgument)
        Task {
            let deadline = ContinuousClock.now + purgeSettleDuration
            while ContinuousClock.now < deadline {
                for suite in suites { _ = purge(suite: suite) }
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard suites.allSatisfy({ purge(suite: $0) }) else { exit(1) }
            DistributedNotificationCenter.default().postNotificationName(
                suitePurgedNotification, object: suites.last, userInfo: nil,
                deliverImmediately: true)
            if !stayRunning { exit(0) }
        }
    }
}
