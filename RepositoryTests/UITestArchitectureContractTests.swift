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
