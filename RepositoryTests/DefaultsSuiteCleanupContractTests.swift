import Foundation
import Testing

/// Every harness that launches the app with its own defaults suite deletes that suite
/// through the app afterwards. Neither harness can delete the plist itself: the UI-test
/// runner is sandboxed away from the app's container, and `defaults delete` leaves an
/// empty plist behind.
@Suite("Defaults suite cleanup contract")
struct DefaultsSuiteCleanupContractTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static let purgeArgument = #""--purge-user-defaults-suite""#
    private static let purgedNotification =
        #""com.johnny4young.vitrine.ui-test.defaults-suite-purged""#

    @Test func aPurgeLaunchDeletesOnlyTestSuitesAndSkipsAppSetup() throws {
        let defaults = try Self.text("Vitrine/Support/AppDefaults.swift")
        #expect(defaults.contains(Self.purgeArgument))
        #expect(defaults.contains(Self.purgedNotification))
        #expect(defaults.contains("guard isTestScoped(suite) else { return false }"))

        let app = try Self.text("Vitrine/App/VitrineApp.swift")
        #expect(app.contains("AppDefaults.performPurgeRequest()"))
        let delegate = try Self.text("Vitrine/App/AppDelegate.swift")
        #expect(
            delegate.components(
                separatedBy: "guard !AppDefaults.isPurgeLaunchProcess else { return }"
            )
            .count == 4, "a purge launch must skip every launch-time setup hook")
    }

    @Test func theLastUITestClassPurgesEverySuiteTheUITestsLaunched() throws {
        let robot = try Self.text("UITests/Robots/VitrineAppRobot.swift")
        let defaultsSource = try Self.text("Vitrine/Support/AppDefaults.swift")
        #expect(robot.contains(Self.purgeArgument))
        #expect(robot.contains(Self.purgedNotification))
        #expect(robot.contains(#""--purge-stay-running""#))
        #expect(robot.contains("[purgeArgument] + launched + [stayRunningArgument]"))
        #expect(defaultsSource.contains(#""--purge-stay-running""#))
        #expect(robot.contains("UITestDefaultsSuite.register(suite)"))
        #expect(robot.contains("XCTestObservationCenter.shared.addTestObserver(fallbackPurge)"))

        let purgeTest = try Self.text("UITests/ZZDefaultsSuitePurgeUITests.swift")
        #expect(purgeTest.contains("XCTAssertTrue("))
        #expect(purgeTest.contains("UITestDefaultsSuite.purgeLaunchedSuites()"))

        var classNames: [String] = []
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: Self.root.appendingPathComponent("UITests"), includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            if url.lastPathComponent != "VitrineAppRobot.swift" {
                #expect(
                    !source.contains("VITRINE_USER_DEFAULTS_SUITE"),
                    "\(url.lastPathComponent) sets a suite outside the robot, which would leak it")
            }
            classNames += source.matches(of: /class\s+(\w+)\s*:\s*XCTestCase\b/).map {
                String($0.output.1)
            }
        }
        // XCTest runs classes alphabetically; a class sorting after the purge would leak.
        #expect(classNames.max() == "ZZDefaultsSuitePurgeUITests", "\(classNames.sorted())")
    }

    @Test func memorySmokePurgesThroughTheAppAndFailsWhenItCannot() throws {
        let script = try Self.text("scripts/run-memory-smoke.py")
        #expect(script.contains(Self.purgeArgument))
        #expect(
            script.contains("purge_failure = purge_defaults_suite(executable, suite)"))
        #expect(script.contains("if purge_failure is not None:"))
        #expect(!script.contains(#"["defaults", "delete""#))
    }
}
