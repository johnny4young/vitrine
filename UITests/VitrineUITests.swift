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
    func testRecentsGalleryLaunches() {
        continueAfterFailure = false
        // `--demo` seeds the editor's code but the recents list starts empty in a
        // fresh defaults suite, so the gallery shows its branded empty state. The
        // smoke test asserts the window and gallery surface exist; the cache and
        // open-in-editor behavior are covered by RecentsStoreTests.
        let app = launch(arguments: ["--open-recents"])
        defer { app.terminate() }

        assertExists(element("recents-window", in: app), in: app, timeout: 8)
        assertExists(element("recents-gallery", in: app), in: app, timeout: 3)
    }

    @MainActor
    func testFirstRunShowsQuickStartWithPrivacyAndSampleCapture() {
        continueAfterFailure = false
        // A fresh defaults suite is a first run, so the quick-start appears on
        // launch with no extra hook (CS-035 "first launch shows the quick-start").
        let app = launch(arguments: [])
        defer { app.terminate() }

        assertExists(element("welcome-window", in: app), in: app, timeout: 8)
        assertExists(element("welcome-view", in: app), in: app, timeout: 3)
        // Local-only privacy copy is visible before any capture (CS-035).
        assertExists(element("welcome-privacy-badge", in: app), in: app)
        // The user can run a sample capture without external clipboard content,
        // and the hotkey/launch-at-login setup is offered (CS-035).
        assertExists(element("welcome-sample-capture-button", in: app), in: app)
        assertExists(element("welcome-launch-at-login-toggle", in: app), in: app)
        // A clear way out is present (CS-035 "user can skip immediately").
        assertExists(element("welcome-skip-button", in: app), in: app)
        assertExists(element("welcome-get-started-button", in: app), in: app)

        // Running the sample capture needs no clipboard setup and reports inline.
        element("welcome-sample-capture-button", in: app).click()
        assertExists(element("welcome-sample-status", in: app), in: app, timeout: 5)
    }

    @MainActor
    func testForcedQuickStartCanBeSkippedToReachTheEditor() {
        continueAfterFailure = false
        // Force the quick-start open and also open the editor: skipping the
        // quick-start must not gate access to the rest of the app (CS-035 "user can
        // skip immediately and still access all features").
        let app = launch(arguments: ["--show-welcome", "--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("welcome-window", in: app), in: app, timeout: 8)
        element("welcome-skip-button", in: app).click()

        // After skipping, the editor window and its primary controls are fully
        // reachable.
        assertExists(element("editor-window", in: app), in: app, timeout: 5)
        assertExists(element("copy-button", in: app), in: app, timeout: 3)
    }

    @MainActor
    func testSkippedOnboardingDoesNotReshowQuickStart() {
        continueAfterFailure = false
        // `--skip-onboarding` marks the quick-start as already seen, so a launch
        // that opens the editor shows no welcome window (CS-035 "shows the
        // quick-start only once").
        let app = launch(arguments: ["--skip-onboarding", "--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        XCTAssertFalse(
            element("welcome-window", in: app).exists,
            "The quick-start reappeared after it was already seen")
    }

    @MainActor
    func testHelpWindowOpensWithOfflineContent() {
        continueAfterFailure = false
        // `--show-help` force-opens the in-app Help window (CS-049). Its content is
        // bundled, so it renders with no network; the smoke test asserts the window
        // and its topic cards (hotkey, quick capture, editor, presets, privacy) are
        // present and that the offline help can be dismissed.
        let app = launch(arguments: ["--skip-onboarding", "--show-help"])
        defer { app.terminate() }

        assertExists(element("help-window", in: app), in: app, timeout: 8)
        assertExists(element("help-view", in: app), in: app, timeout: 3)
        assertExists(element("help-topic-hotkey", in: app), in: app)
        assertExists(element("help-topic-quick-capture", in: app), in: app)
        assertExists(element("help-topic-editor", in: app), in: app)
        assertExists(element("help-topic-presets", in: app), in: app)
        assertExists(element("help-topic-privacy", in: app), in: app)
        // The hotkey recorder makes Help actionable, and a clear way out is present.
        assertExists(element("help-hotkey-recorder", in: app), in: app)
        assertExists(element("help-done-button", in: app), in: app)
    }

    @MainActor
    func testWhatsNewAppearsForANewerVersionAndIsSkippable() {
        continueAfterFailure = false
        // `--seen-old-version` records an older last-seen version (and marks
        // onboarding done), so the version gate auto-presents the bundled notes for
        // the newer shipped version on launch (CS-049 "appears only when the bundled
        // notes version is newer than the last-seen version").
        let app = launch(arguments: ["--seen-old-version"])
        defer { app.terminate() }

        assertExists(element("whats-new-window", in: app), in: app, timeout: 8)
        assertExists(element("whats-new-view", in: app), in: app, timeout: 3)
        assertExists(element("whats-new-highlights", in: app), in: app)
        // It is skippable: a clear "Continue" dismisses it (CS-049 "skippable").
        assertExists(element("whats-new-continue-button", in: app), in: app)
        element("whats-new-continue-button", in: app).click()
        XCTAssertTrue(
            element("whats-new-window", in: app).waitForNonExistence(timeout: 3),
            "What's New did not dismiss after Continue")
    }

    @MainActor
    func testWhatsNewDoesNotAppearOnCleanFirstRun() {
        continueAfterFailure = false
        // A clean first run shows the quick-start, never What's New — onboarding owns
        // the first launch (CS-049 "never on a clean first run; onboarding owns that").
        let app = launch(arguments: [])
        defer { app.terminate() }

        assertExists(element("welcome-window", in: app), in: app, timeout: 8)
        XCTAssertFalse(
            element("whats-new-window", in: app).exists,
            "What's New appeared on a clean first run, pre-empting onboarding")
    }

    @MainActor
    func testHelpMenuExposesHelpAndWhatsNewCommands() {
        continueAfterFailure = false
        let app = launch(arguments: ["--skip-onboarding", "--demo", "--open-editor"])
        defer { app.terminate() }

        // The editor makes the app active, so its main menu bar (CS-032) is shown.
        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5), "Main menu bar is missing")

        menuBar.menuBarItems["Help"].click()
        let helpMenu = menuBar.menuBarItems["Help"].menus.firstMatch
        XCTAssertTrue(helpMenu.waitForExistence(timeout: 3))
        for title in ["Vitrine Help", "What's New"] {
            XCTAssertTrue(
                helpMenu.menuItems[title].exists, "Missing Help-menu command: \(title)")
        }
        // Close the menu without invoking anything.
        menuBar.menuBarItems["Help"].click()
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
