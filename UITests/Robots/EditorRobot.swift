import XCTest

/// Stable editor selectors and adaptive-toolbar actions shared by smoke and tour tests.
@MainActor
struct EditorRobot {
    let testCase: XCTestCase
    let app: XCUIApplication

    var window: XCUIElement { testCase.element("editor-window", in: app) }
    var secondWindow: XCUIElement { testCase.element("editor-window-2", in: app) }
    var toolbar: XCUIElement { testCase.element("editor-toolbar", in: app) }
    var inspector: XCUIElement { testCase.element("editor-inspector", in: app) }
    var previewStage: XCUIElement { testCase.element("editor-preview-stage", in: app) }
    var codeTextView: XCUIElement { app.textViews["code-editor-text-view"] }

    func action(_ identifier: String) -> XCUIElement {
        testCase.hittableElement(identifier, in: app)
    }

    @discardableResult
    func revealAction(
        _ identifier: String,
        from menuIdentifier: String = "editor-actions-menu",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        testCase.revealToolbarAction(
            identifier, from: menuIdentifier, in: app, file: file, line: line)
    }
}
