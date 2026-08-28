import XCTest

/// Web Snapshot's real accessibility surface, without knowledge of renderer internals.
@MainActor
struct WebSnapshotRobot {
    let testCase: XCTestCase
    let app: XCUIApplication

    var window: XCUIElement { testCase.element("web-snapshot-window", in: app) }
    var inspector: XCUIElement { testCase.element("web-snapshot-inspector", in: app) }
    var previewStage: XCUIElement { testCase.element("web-snapshot-preview-stage", in: app) }
    var htmlMode: XCUIElement { testCase.element("web-snapshot-mode-html", in: app) }
    var htmlEditor: XCUIElement { app.textViews["web-snapshot-html-editor"] }
    var captureButton: XCUIElement {
        testCase.hittableElement("web-snapshot-capture-button", in: app)
    }
    var results: XCUIElement { testCase.element("web-snapshot-results", in: app) }

    func viewport(_ identifier: String) -> XCUIElement {
        testCase.element("web-viewport-chip-\(identifier)", in: app)
    }

    func result(_ identifier: String) -> XCUIElement {
        testCase.element("web-snapshot-result-\(identifier)", in: app)
    }

    func exportAction(_ identifier: String) -> XCUIElement {
        testCase.hittableElement("web-snapshot-\(identifier)-button", in: app)
    }
}
