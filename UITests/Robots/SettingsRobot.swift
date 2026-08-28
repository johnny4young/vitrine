import XCTest

/// Settings navigation and pane selectors shared by feature and screenshot journeys.
@MainActor
struct SettingsRobot {
    let testCase: XCTestCase
    let app: XCUIApplication

    var window: XCUIElement { testCase.element("settings-window", in: app) }
    var generalPane: XCUIElement { testCase.element("settings-general-pane", in: app) }

    func navigation(_ identifier: String) -> XCUIElement {
        testCase.element(identifier, in: app)
    }

    func pane(_ identifier: String) -> XCUIElement {
        testCase.element(identifier, in: app)
    }

    @discardableResult
    func open(
        navigation navigationIdentifier: String,
        pane paneIdentifier: String,
        timeout: TimeInterval = 3
    ) -> XCUIElement {
        navigation(navigationIdentifier).click()
        let destination = pane(paneIdentifier)
        XCTAssertTrue(
            destination.waitForExistence(timeout: timeout),
            "Settings pane \(paneIdentifier) did not appear")
        return destination
    }
}
