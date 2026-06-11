import AppKit
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
        assertExists(element("format-button", in: app), in: app)
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

    // MARK: - Multi-window editing and restoration (CS-053)

    @MainActor
    func testOpeningASecondEditorWindowKeepsBothOpen() {
        continueAfterFailure = false
        // `--open-second-editor` opens the primary editor plus an additional,
        // independent editor window (CS-053 "users can open multiple editor windows").
        let app = launch(arguments: ["--demo", "--open-second-editor"])
        defer { app.terminate() }

        // Both windows exist, each addressed by its own identifier: the primary keeps
        // the bare `editor-window`, the second is suffixed with its index.
        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        assertExists(element("editor-window-2", in: app), in: app, timeout: 8)

        // Each window carries the editor's primary controls; the encode/decode and
        // per-window-independence guarantees are pinned by WindowStateTests.
        XCTAssertTrue(
            app.windows.count >= 2,
            "Expected at least two editor windows to be open")
    }

    @MainActor
    func testClosingOneEditorWindowLeavesTheOtherOpen() {
        continueAfterFailure = false
        // Closing one window must not lose the other's state (CS-053). Close the second
        // window from the Window menu's window list and assert the primary survives.
        let app = launch(arguments: ["--demo", "--open-second-editor"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        let second = element("editor-window-2", in: app)
        XCTAssertTrue(second.waitForExistence(timeout: 8), "Second editor window did not open")

        // Close the key (second) window with the standard Close shortcut.
        second.click()
        second.typeKey("w", modifierFlags: .command)

        // The primary window remains; only the second one closed.
        assertExists(element("editor-window", in: app), in: app, timeout: 3)
        XCTAssertTrue(
            element("editor-window-2", in: app).waitForNonExistence(timeout: 3),
            "The second editor window did not close")
    }

    @MainActor
    func testEditorWindowRecoversFromOffScreenFrame() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        // `--force-offscreen-editor` opens the editor, shoves it far off the visible
        // screens, and runs the recovery pass, so a window saved on an unplugged
        // monitor is pulled back on-screen rather than stranded (CS-053 "behaves
        // correctly across display changes without off-screen windows").
        let app = launch(arguments: ["--demo", "--force-offscreen-editor"])
        defer { app.terminate() }

        // After recovery the window and its controls are reachable (hittable), which is
        // only true when the frame sits on a visible display. On a display smaller than
        // the editor's default size the recovery pass also shrinks the window to fit,
        // so this holds on a small CI display (1024x768) too.
        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        XCTAssertTrue(
            element("copy-button", in: app).waitForExistence(timeout: 3),
            "Editor control is missing after off-screen recovery")
        assertHittable(
            "copy-button", in: app,
            "Editor window was not recovered onto a visible screen")
    }

    @MainActor
    func testFileMenuExposesNewEditorWindowAndMakeDefault() {
        continueAfterFailure = false
        let app = launch(arguments: ["--demo", "--open-editor", "--standard-activation"])
        defer { app.terminate() }

        // The File menu carries the multi-window commands (CS-053): "New Editor
        // Window" (always available) and "Make This Window the Default" (editor-scoped).
        let editor = element("editor-window", in: app)
        assertExists(editor, in: app, timeout: 8)
        makeFrontmostForMenuBarAccess(app, clicking: editor)
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5), "Main menu bar is missing")

        menuBar.menuBarItems["File"].click()
        let fileMenu = menuBar.menuBarItems["File"].menus.firstMatch
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 3))
        for title in ["New Editor Window", "Make This Window the Default"] {
            XCTAssertTrue(
                fileMenu.menuItems[title].exists, "Missing File-menu command: \(title)")
        }
        // Close the menu without invoking anything.
        menuBar.menuBarItems["File"].click()
    }

    @MainActor
    func testEditorExposesMakeDefaultToolbarAction() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        // The editor surfaces an explicit "Make Default" affordance so promoting a
        // window's style to the app default is discoverable in the editor, not only in
        // the menu (CS-053 "make default is explicit").
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        assertExists(element("make-default-button", in: app), in: app, timeout: 3)
        assertHittable("make-default-button", in: app, "Make Default action is not reachable")
    }

    @MainActor
    func testEditorExposesFormatCodeToolbarAction() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        // Format Code is a primary editor affordance (CS-049) and should be reachable
        // by mouse as well as the Edit-menu shortcut. The pure formatting behavior is
        // covered by CodeFormatterTests; this UI smoke pins the accessible toolbar route.
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        assertExists(element("format-button", in: app), in: app, timeout: 3)
        assertHittable("format-button", in: app, "Format Code action is not reachable")
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

        let inspector = element("editor-inspector", in: app)
        assertExists(inspector, in: app, timeout: 8)

        // Advanced controls live behind collapsible inspector sections that start
        // closed (CS-037 "advanced controls remain available but are grouped behind
        // an inspector section or disclosure"). A collapsible `Section`'s disclosure
        // triangle is anonymous form chrome — the section title is a separate
        // sibling StaticText — so the triangle cannot be addressed by name: find
        // the "Background" header, then click the triangle that shares its row.
        let header = inspector.staticTexts["Background"]
        XCTAssertTrue(
            header.waitForExistence(timeout: 3),
            "Inspector is missing the collapsible Background section")
        let rowY = header.frame.midY
        let triangle = inspector.disclosureTriangles.allElementsBoundByIndex
            .min { abs($0.frame.midY - rowY) < abs($1.frame.midY - rowY) }
        guard let triangle else {
            XCTFail("Inspector has no disclosure triangles")
            return
        }
        triangle.click()
        assertExists(element("background-kind-picker", in: app), in: app, timeout: 3)
    }

    @MainActor
    func testEditorKeyboardCanReachPresetStripAndInspector() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        // The preset strip, inspector, and export toolbar are all standard
        // focusable controls, so keyboard navigation can reach each region
        // (CS-037 "keyboard navigation can reach editor, preset strip, inspector,
        // and export toolbar"). Asserting the elements are hittable is the
        // automatable proxy for reachability without scripting Full Keyboard Access.
        assertExists(element("editor-style-preset-picker", in: app), in: app, timeout: 8)
        assertHittable(
            "editor-style-preset-picker", in: app, "Style preset picker is not reachable")
        assertHittable("editor-inspector", in: app, "Inspector is not reachable")
        assertHittable("copy-button", in: app, "Export toolbar copy action is not reachable")
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
    func testInputPaneExposesReindentOnPasteToggle() {
        continueAfterFailure = false
        let app = launch(arguments: ["--open-settings"])
        defer { app.terminate() }

        // The Input pane surfaces the paste re-indent preference (CS-049), the
        // switch behind the editor's tidy-on-paste behavior.
        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        app.toolbars.buttons["Input"].click()
        assertExists(element("settings-input-pane", in: app), in: app, timeout: 3)
        assertExists(element("reindent-on-paste-toggle", in: app), in: app, timeout: 3)
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
        let app = launch(arguments: ["--demo", "--open-editor", "--standard-activation"])
        defer { app.terminate() }

        // The editor window makes the app active, so its agent-app main menu bar
        // (CS-032) is shown. Assert the standard top-level menus exist.
        let editor = element("editor-window", in: app)
        assertExists(editor, in: app, timeout: 8)
        makeFrontmostForMenuBarAccess(app, clicking: editor)
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
        let app = launch(
            arguments: ["--skip-onboarding", "--demo", "--open-editor", "--standard-activation"])
        defer { app.terminate() }

        // The editor makes the app active, so its main menu bar (CS-032) is shown.
        let editor = element("editor-window", in: app)
        assertExists(editor, in: app, timeout: 8)
        makeFrontmostForMenuBarAccess(app, clicking: editor)
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

    // MARK: - Localization smoke (CS-047)

    @MainActor
    func testSettingsPanesSurviveAccentedPseudolocale() {
        continueAfterFailure = false
        // The accented + lengthened pseudolocale (`en-XA`) padding-tests every
        // localized string: if a Settings pane truncated or clipped under longer,
        // accented text, its controls would no longer resolve. Walking the panes and
        // asserting each one's key controls exist *and* remain hittable is the
        // automatable proxy for "no truncation or clipping in Settings panes"
        // (CS-047 acceptance).
        let app = launch(arguments: ["--open-settings"], locale: .accentedPseudo)
        defer { app.terminate() }

        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        XCTAssertTrue(
            element("reset-all-settings-button", in: app).isHittable,
            "General pane control is clipped or unreachable under en-XA")

        // The toolbar tab titles are themselves localized (they pseudo-localize under
        // en-XA), so the tabs are selected by their stable order — General(0),
        // Style(1), Library(2), Output(3), Input(4), About(5) — rather than by visible title.
        let toolbarButtons = app.toolbars.buttons
        for (tabIndex, paneIdentifier, control) in [
            (1, "settings-style-pane", "style-theme-picker"),
            (2, "settings-library-pane", "style-preset-picker"),
            (3, "settings-output-pane", "output-format-picker"),
            (5, "settings-about-pane", "export-diagnostics-button"),
        ] {
            toolbarButtons.element(boundBy: tabIndex).click()
            assertExists(element(paneIdentifier, in: app), in: app, timeout: 3)
            XCTAssertTrue(
                element(control, in: app).waitForExistence(timeout: 3),
                "Pane \(paneIdentifier) is missing \(control) under en-XA")
            XCTAssertTrue(
                element(control, in: app).isHittable,
                "Control \(control) is clipped or unreachable under en-XA")
        }
    }

    @MainActor
    func testEditorLayoutIsSaneUnderRightToLeftPseudolocale() {
        continueAfterFailure = false
        // Under the right-to-left pseudolocale (`ar`, forced RTL) the editor should
        // still lay out and expose every primary control — mirrored, but never
        // dropped or stranded. Reachability of the preset strip, preview stage,
        // inspector, and export toolbar is the automatable proxy for "layout is sane
        // under RTL, mirrored where appropriate" (CS-047 acceptance).
        let app = launch(arguments: ["--demo", "--open-editor"], locale: .rightToLeftPseudo)
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        for identifier in [
            "editor-preset-strip", "editor-preview-stage", "editor-inspector", "copy-button",
            "save-button", "share-button",
        ] {
            XCTAssertTrue(
                element(identifier, in: app).waitForExistence(timeout: 3),
                "Editor control \(identifier) is missing under the RTL pseudolocale")
            // Through assertHittable because the toolbar ids can resolve to nested
            // wrapper+button pairs — a single-element `.isHittable` read would raise
            // "multiple matching elements" (see matches(_:in:)).
            assertHittable(
                identifier, in: app,
                "Editor control \(identifier) is clipped or unreachable under RTL")
        }
    }

    /// A locale/text-direction override applied to a launch (CS-047). Passed through
    /// the app's `NSArgumentDomain` (the standard `-AppleLanguages` / `-AppleLocale`
    /// / `-AppleTextDirection` overrides), so no app code is needed to force a
    /// pseudolocale or right-to-left layout under test.
    private enum LocaleOverride {
        /// The system locale (no override).
        case system
        /// The accented, lengthened pseudolocale that stresses string layout.
        case accentedPseudo
        /// A right-to-left locale with forced RTL writing direction.
        case rightToLeftPseudo

        var launchArguments: [String] {
            switch self {
            case .system:
                []
            case .accentedPseudo:
                ["-AppleLanguages", "(en-XA)", "-AppleLocale", "en_XA"]
            case .rightToLeftPseudo:
                [
                    "-AppleLanguages", "(ar)", "-AppleLocale", "ar",
                    "-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES",
                ]
            }
        }
    }

    @MainActor
    private func launch(arguments: [String], locale: LocaleOverride = .system) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + locale.launchArguments
        app.launchEnvironment["VITRINE_USER_DEFAULTS_SUITE"] =
            "VitrineUITests-\(name)-\(UUID().uuidString)"
        app.launch()
        return app
    }

    /// Brings the app genuinely frontmost so its main-menu bar realizes.
    ///
    /// An LSUIElement app's menu-bar items exist in the accessibility tree but keep
    /// zero-sized frames under synthetic activation, so they can never be clicked
    /// (see `ScreenshotTourUITests.testMainMenuTour`). The main-menu tests therefore
    /// launch with `--standard-activation` (the dev hook that runs the app as a
    /// regular app) and call this before touching the menus: a real click on one of
    /// the app's windows is what makes macOS hand it the menu bar.
    @MainActor
    private func makeFrontmostForMenuBarAccess(
        _ app: XCUIApplication, clicking window: XCUIElement
    ) {
        app.activate()
        window.click()
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// Skips a display-geometry-sensitive test when no attached display can hold the
    /// editor at its minimum supported size (`EditorView`'s 940x520 root frame plus
    /// window chrome, with a small margin). Below that, control hittability cannot
    /// hold no matter what the app does, so the assertion would be testing the
    /// display, not the product. The hosted CI runners' 1024x768 virtual display
    /// passes this guard — these tests are expected to *run* there, not skip.
    @MainActor
    private func skipUnlessADisplayFitsTheEditor() throws {
        let required = CGSize(width: 960, height: 600)
        let visible = NSScreen.screens.map(\.visibleFrame)
        try XCTSkipUnless(
            visible.contains { $0.width >= required.width && $0.height >= required.height },
            "No display fits the editor's minimum "
                + "\(Int(required.width))x\(Int(required.height)) window "
                + "(visible frames: \(visible)); hittability cannot be asserted here.")
    }

    /// Every AX element carrying `identifier`, resolved fresh on each call. A single
    /// identifier can legitimately match nested elements: an AppKit toolbar item
    /// wraps the SwiftUI button it hosts and both expose the same identifier
    /// (observed on the macOS 15 CI image once the editor window fits the display),
    /// so reading a property through a single-element query would raise "multiple
    /// matching elements found".
    @MainActor
    private func matches(_ identifier: String, in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .allElementsBoundByIndex
    }

    /// Asserts some element carrying `identifier` becomes hittable, polling briefly
    /// so a window still being positioned (centered, or pulled back on-screen by the
    /// recovery pass) is not a flake. The control is reachable when *any* of the
    /// identifier's matches is hittable — see `matches(_:in:)` for why there can be
    /// more than one. On failure it attaches the screen/window/match geometry and the
    /// full accessibility hierarchy, so a display-geometry regression — e.g. on a
    /// small CI virtual display — can be triaged from the .xcresult alone.
    @MainActor
    private func assertHittable(
        _ identifier: String,
        in app: XCUIApplication,
        _ message: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if matches(identifier, in: app).contains(where: { $0.isHittable }) { return }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline

        let found = matches(identifier, in: app)
            .map { "match frame=\($0.frame) hittable=\($0.isHittable)" }
        let windows = app.windows.allElementsBoundByIndex
            .map { "window \"\($0.title)\" frame=\($0.frame)" }
        let screens = NSScreen.screens
            .map { "screen frame=\($0.frame) visible=\($0.visibleFrame)" }
        let geometry = (["matches for '\(identifier)': \(found.count)"] + found + windows + screens)
            .joined(separator: "\n")
        let attachment = XCTAttachment(string: geometry + "\n\n" + app.debugDescription)
        attachment.name = "Hittability diagnostics"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail(message, file: file, line: line)
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
