import Foundation
import Testing

@Suite("UI test architecture contracts")
struct UITestArchitectureContractTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Both journeys must keep a substantial suite rather than quietly shrinking to a
    /// smoke test. An exact count would instead fail whenever a journey is ADDED, which
    /// taxes the change this contract wants to encourage; the screenshot tour's own
    /// per-state contract is enforced by `scripts/validate-screenshot-tour.py`.
    @Test func preservesAllSmokeAndVisualTourJourneys() throws {
        let smoke = try Self.text("UITests/VitrineUITests.swift")
        let tour = try Self.text("UITests/ScreenshotTourUITests.swift")

        #expect(Self.testMethodCount(in: smoke) >= 50)
        #expect(Self.testMethodCount(in: tour) >= 20)
    }

    /// Captures wait for the surface, not for the clock.
    ///
    /// Every capture in the tour used to follow a hand-tuned sleep, 24 seconds of them, and
    /// a fixed wait is both too long once a surface is already still and too short when a
    /// slower machine is mid-transition. `save(_:as:note:)` now waits for the pixels to stop
    /// changing. The sleeps that remain are poll intervals inside loops that end as soon as
    /// their condition holds, so this pins that shape: no sleep outside a bounded wait.
    @Test func theVisualTourWaitsForSurfacesRatherThanTheClock() throws {
        let tour = try Self.text("UITests/ScreenshotTourUITests.swift")
        #expect(tour.contains("private func waitUntilStill("))
        #expect(
            tour.contains("waitUntilStill(element, timeout: settleTimeout)"),
            "every capture must go through the stillness wait")

        let lines = tour.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() where line.contains("Thread.sleep(") {
            let context = lines[max(0, index - 6)..<min(lines.count, index + 3)]
            #expect(
                context.contains(where: { $0.contains("deadline") }),
                "line \(index + 1) waits on the clock; wait on a condition or the surface")
        }
    }

    @Test func keepsDomainRobotsAndSerialExecutionPolicy() throws {
        let robots = [
            "EditorRobot.swift": "struct EditorRobot",
            "RecentsRobot.swift": "struct RecentsRobot",
            "SettingsRobot.swift": "struct SettingsRobot",
            "VitrineAppRobot.swift": "struct VitrineAppRobot",
            "WebSnapshotRobot.swift": "struct WebSnapshotRobot",
        ]
        for (filename, declaration) in robots {
            #expect(try Self.text("UITests/Robots/\(filename)").contains(declaration))
        }

        let project = try Self.text("project.yml")
        #expect(project.contains("parallelizable: false"))
        let appRobot = try Self.text("UITests/Robots/VitrineAppRobot.swift")
        #expect(appRobot.contains("VITRINE_USER_DEFAULTS_SUITE"))
        #expect(appRobot.contains("locale.launchArguments"))
    }

    @Test func menuBarFallbackContractStaysOptInAndPerLaunchAuthenticated() throws {
        let appControl = try Self.text("Vitrine/MenuBar/MenuBarUITestControl.swift")
        let appRobot = try Self.text("UITests/Robots/VitrineAppRobot.swift")
        let support = try Self.text("UITests/VitrineUITestSupport.swift")
        let argument = "--menu-panel-ui-test-control="
        let notification = "com.johnny4young.vitrine.ui-test.open-menu-panel"

        #expect(appControl.contains(argument))
        #expect(appRobot.contains(argument))
        #expect(appControl.contains(notification))
        #expect(appRobot.contains(notification))
        #expect(appControl.contains("UUID(uuidString: token)"))
        #expect(support.contains("object: token"))
    }

    private static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static func testMethodCount(in source: String) -> Int {
        source.components(separatedBy: .newlines).count { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("func test")
        }
    }
}
