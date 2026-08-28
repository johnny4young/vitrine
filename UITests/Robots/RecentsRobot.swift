import XCTest

/// Recents gallery selectors resolved fresh after every adaptive-grid rebuild.
@MainActor
struct RecentsRobot {
    let testCase: XCTestCase
    let app: XCUIApplication

    var window: XCUIElement { testCase.element("recents-window", in: app) }
    var gallery: XCUIElement { testCase.element("recents-gallery", in: app) }
    var searchField: XCUIElement { testCase.element("recents-search-field", in: app) }
    var cards: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "recents-card")
    }
    var pinnedBadges: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "recents-pinned-badge")
    }
    var presetPickers: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "recents-preset-picker")
    }

    func action(_ identifier: String) -> XCUIElement {
        testCase.hittableElement(identifier, in: app)
    }
}
