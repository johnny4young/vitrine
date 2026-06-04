import XCTest

final class VitrineUITests: XCTestCase {
    @MainActor
    func testEditorLaunchesWithPrimaryControls() {
        continueAfterFailure = false
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        assertExists(element("code-editor-text-view", in: app), in: app, timeout: 3)
        assertExists(element("language-picker", in: app), in: app)
        assertExists(element("destination-preset-picker", in: app), in: app)
        assertExists(element("copy-button", in: app), in: app)
        assertExists(element("save-button", in: app), in: app)
        assertExists(element("share-button", in: app), in: app)
    }

    @MainActor
    func testStylePaneShowsDestinationPresetPicker() {
        continueAfterFailure = false
        let app = launch(arguments: ["--open-settings"])
        defer { app.terminate() }

        // The Style pane surfaces the destination preset picker (CS-020).
        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        app.toolbars.buttons["Style"].click()
        assertExists(element("settings-style-pane", in: app), in: app, timeout: 3)
        assertExists(element("destination-preset-picker", in: app), in: app, timeout: 3)
    }

    @MainActor
    func testStylePaneExposesAccessibleMetadataControls() {
        continueAfterFailure = false
        let app = launch(arguments: ["--open-settings"])
        defer { app.terminate() }

        // The Header section's metadata controls are present and carry stable
        // accessibility identifiers/labels (CS-022 acceptance).
        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        app.toolbars.buttons["Style"].click()
        assertExists(element("settings-style-pane", in: app), in: app, timeout: 3)
        assertExists(element("metadata-filename-field", in: app), in: app, timeout: 3)
        assertExists(element("metadata-title-field", in: app), in: app)
        assertExists(element("metadata-caption-field", in: app), in: app)
        assertExists(element("metadata-language-badge-toggle", in: app), in: app)
    }

    @MainActor
    func testSettingsLaunchesWithGeneralPane() {
        continueAfterFailure = false
        let app = launch(arguments: ["--open-settings"])
        defer { app.terminate() }

        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        assertExists(app.staticTexts["Global hotkey:"], in: app, timeout: 3)
        assertExists(app.staticTexts["Hotkey runs"], in: app, timeout: 3)
        assertExists(element("launch-at-login-toggle", in: app), in: app)
    }

    @MainActor
    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["VITRINE_USER_DEFAULTS_SUITE"] =
            "VitrineUITests-\(name)-\(UUID().uuidString)"
        app.launch()
        return app
    }

    @MainActor
    private func assertExists(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let exists = timeout > 0 ? element.waitForExistence(timeout: timeout) : element.exists
        if !exists {
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "Accessibility hierarchy"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("Missing UI element: \(element)", file: file, line: line)
        }
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
