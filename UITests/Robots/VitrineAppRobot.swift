import XCTest

/// Locale overrides shared by every UI-test journey. They use the standard
/// `NSArgumentDomain` keys so product code stays unaware of test-only locales.
enum VitrineLocaleOverride {
    case system
    case accentedPseudo
    case rightToLeftPseudo

    var launchArguments: [String] {
        switch self {
        case .system:
            []
        case .accentedPseudo:
            ["-AppleLanguages", "(en-XA)", "-AppleLocale", "en_XA"]
        case .rightToLeftPseudo:
            [
                "-AppleLanguages", "(ar)", "-AppleLocale", "ar",
                "-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES",
            ]
        }
    }
}

/// Canonical launch-argument groups for the app's highest-frequency UI journeys.
enum VitrineLaunchArguments {
    static let editor = ["--demo", "--open-editor"]
    static let emptyEditor = ["--open-editor"]
    static let settings = ["--open-settings"]
    static let editorTour = ["--skip-onboarding", "--demo", "--open-editor"]
    static let emptyEditorTour = ["--skip-onboarding", "--open-editor"]
    static let settingsTour = ["--skip-onboarding", "--open-settings"]
    static let recents = ["--skip-onboarding", "--demo-recents", "--open-recents"]
    static let emptyRecents = ["--skip-onboarding", "--open-recents"]
    static let populatedRecent = ["--skip-onboarding", "--demo-recent", "--open-recents"]
    static let webSnapshot = ["--skip-onboarding", "--open-web-snapshot"]
    static let deterministicWebSnapshot = [
        "--skip-onboarding", "--web-snapshot-ui-test-renderer", "--open-web-snapshot",
    ]
    static var menuBar: [String] {
        ["--skip-onboarding", MenuBarTestControl.makeLaunchArgument()]
    }
    static var menuBarRecents: [String] {
        ["--skip-onboarding", "--demo-recents", MenuBarTestControl.makeLaunchArgument()]
    }
}

/// UI-runner copy of the app's `AppDefaults` purge contract; a repository contract test
/// keeps the literals aligned. The sandboxed runner cannot write the app's container, so
/// a purge-only launch of the app deletes the suites a test class launched.
@MainActor
enum UITestDefaultsSuite {
    static let environmentKey = "VITRINE_USER_DEFAULTS_SUITE"
    static let purgeArgument = "--purge-user-defaults-suite"
    static let stayRunningArgument = "--purge-stay-running"
    static let purgedNotification = Notification.Name(
        "com.johnny4young.vitrine.ui-test.defaults-suite-purged")

    private static var launched: [String] = []

    static func register(_ suite: String) {
        launched.append(suite)
    }

    /// Launches through XCUIApplication: LaunchServices drops the arguments and
    /// environment of a sandboxed caller such as this runner. One launch per class keeps
    /// the app's settle window, which outlasts cfprefsd's deferred writes, off every test.
    static func purgeLaunchedSuites() {
        guard let last = launched.last else { return }
        let purged = XCTNSNotificationExpectation(
            name: purgedNotification, object: last,
            notificationCenter: DistributedNotificationCenter.default())
        let purger = XCUIApplication()
        purger.launchArguments = [
            purgeArgument, launched.joined(separator: "\n"), stayRunningArgument,
        ]
        purger.launchEnvironment[environmentKey] = last
        purger.launch()
        let outcome = XCTWaiter().wait(for: [purged], timeout: 40)
        purger.terminate()
        XCTAssertEqual(
            outcome, .completed, "Vitrine did not delete \(launched.count) defaults suites")
        launched.removeAll()
    }
}

/// Every UI test class inherits this so the suites its tests launched are deleted.
class VitrineUITestCase: XCTestCase {
    override class func tearDown() {
        MainActor.assumeIsolated { UITestDefaultsSuite.purgeLaunchedSuites() }
        super.tearDown()
    }
}

/// UI-runner copy of the app's private menu-panel control contract. UI tests cannot
/// import the application module; a source contract test keeps both literals aligned.
enum MenuBarTestControl {
    static let launchArgumentPrefix = "--menu-panel-ui-test-control="
    static let notificationName = Notification.Name(
        "com.johnny4young.vitrine.ui-test.open-menu-panel")

    static func makeLaunchArgument() -> String {
        launchArgumentPrefix + UUID().uuidString
    }

    static func token(in arguments: [String]) -> String? {
        arguments.first(where: { $0.hasPrefix(launchArgumentPrefix) })?
            .split(separator: "=", maxSplits: 1).last.map(String.init)
    }
}

/// Launches Vitrine with an isolated defaults suite and deterministic locale.
/// Every smoke and visual-tour test uses this path so argument, environment, and
/// foreground diagnostics cannot drift between suites.
@MainActor
struct VitrineAppRobot {
    let testCase: XCTestCase
    let suitePrefix: String

    @discardableResult
    func launch(
        arguments: [String],
        locale: VitrineLocaleOverride = .system,
        environment: [String: String] = [:],
        requireForeground: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let suite = "\(suitePrefix)-\(testCase.name)-\(UUID().uuidString)"
        app.launchArguments = arguments + locale.launchArguments
        app.launchEnvironment[UITestDefaultsSuite.environmentKey] = suite
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        UITestDefaultsSuite.register(suite)
        app.launch()
        app.activate()

        if requireForeground {
            XCTAssertTrue(
                app.wait(for: .runningForeground, timeout: 5),
                "Vitrine never reached the foreground after launch")
        }
        return app
    }
}
