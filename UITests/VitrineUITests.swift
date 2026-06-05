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
        // The editor's destination preset picker carries its own identifier so it
        // never collides with the Settings panes' picker (CS-032).
        assertExists(element("editor-destination-preset-picker", in: app), in: app)
        assertExists(element("copy-button", in: app), in: app)
        assertExists(element("save-button", in: app), in: app)
        assertExists(element("share-button", in: app), in: app)
        // The editor advertises a drop target for source files / text (CS-028).
        // Driving a real drag from outside the app is not reliably automatable, so
        // the smoke test asserts the target exists; the loading policy itself is
        // covered by FileInputLoaderTests.
        assertExists(element("editor-drop-target", in: app), in: app)
    }

    @MainActor
    func testEditorIsPresetFirstWithStripInspectorAndPreviewStage() {
        continueAfterFailure = false
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)

        // The preset-first command strip leads the editor: it carries both the
        // destination preset picker and the style preset picker (CS-037 "the first
        // visible editor controls are preset/style choices").
        assertExists(element("editor-preset-strip", in: app), in: app, timeout: 3)
        assertExists(element("editor-destination-preset-picker", in: app), in: app)
        assertExists(element("editor-style-preset-picker", in: app), in: app)

        // The hero preview sits on its own neutral stage so it reads as the focus
        // of the window, not a small settings thumbnail (CS-037 "preview gets
        // visual priority").
        assertExists(element("editor-preview-stage", in: app), in: app)

        // The focused inspector is present with its primary style controls surfaced
        // up front (CS-037).
        assertExists(element("editor-inspector", in: app), in: app)
        assertExists(element("style-theme-picker", in: app), in: app)
        assertExists(element("style-font-picker", in: app), in: app)
    }

    @MainActor
    func testEditorInspectorDisclosesAdvancedControls() {
        continueAfterFailure = false
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("editor-inspector", in: app), in: app, timeout: 8)

        // Advanced controls live behind collapsible inspector sections that start
        // closed (CS-037 "advanced controls remain available but are grouped behind
        // an inspector section or disclosure"). The disclosure headers are present
        // and reachable; expanding "Background" reveals its kind picker.
        let background = app.disclosureTriangles["Background"]
        XCTAssertTrue(
            background.waitForExistence(timeout: 3),
            "Inspector is missing the collapsible Background section")
        background.click()
        assertExists(element("background-kind-picker", in: app), in: app, timeout: 3)
    }

    @MainActor
    func testEditorKeyboardCanReachPresetStripAndInspector() {
        continueAfterFailure = false
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        // The preset strip, inspector, and export toolbar are all standard
        // focusable controls, so keyboard navigation can reach each region
        // (CS-037 "keyboard navigation can reach editor, preset strip, inspector,
        // and export toolbar"). Asserting the elements are hittable is the
        // automatable proxy for reachability without scripting Full Keyboard Access.
        assertExists(element("editor-style-preset-picker", in: app), in: app, timeout: 8)
        XCTAssertTrue(
            element("editor-style-preset-picker", in: app).isHittable,
            "Style preset picker is not reachable")
        XCTAssertTrue(
            element("editor-inspector", in: app).isHittable,
            "Inspector is not reachable")
        XCTAssertTrue(
            element("copy-button", in: app).isHittable,
            "Export toolbar copy action is not reachable")
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
    func testMainMenuExposesPrimaryCommands() {
        continueAfterFailure = false
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        // The editor window makes the app active, so its agent-app main menu bar
        // (CS-032) is shown. Assert the standard top-level menus exist.
        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5), "Main menu bar is missing")

        for title in ["File", "Edit", "View", "Window", "Help"] {
            XCTAssertTrue(
                menuBar.menuBarItems[title].exists, "Missing top-level menu: \(title)")
        }

        // The File menu carries the capture/editor/export commands that mirror the
        // editor toolbar — the heart of CS-032's "menu command parity".
        menuBar.menuBarItems["File"].click()
        let fileMenu = menuBar.menuBarItems["File"].menus.firstMatch
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 3))
        for title in [
            "New Capture from Clipboard", "Open Editor", "Copy Image", "Save Image…",
            "Share Image…",
        ] {
            XCTAssertTrue(
                fileMenu.menuItems[title].exists, "Missing File-menu command: \(title)")
        }
        // Close the menu without invoking anything.
        menuBar.menuBarItems["File"].click()
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
