import XCTest

/// A design-audit screenshot tour (not a regression gate): walks every user-facing
/// surface and writes window-cropped PNGs to `VITRINE_SCREENSHOT_DIR` (passed through
/// `TEST_RUNNER_VITRINE_SCREENSHOT_DIR`). Each test launches into an isolated defaults
/// suite, so the tour never touches the real app state. Surfaces that cannot be
/// captured (e.g. the status-item menu under some automation contexts) are recorded
/// as misses in `manifest.txt` instead of failing the tour.
final class ScreenshotTourUITests: XCTestCase {
    /// Opt-in only (mirrors the golden/gallery recorders): the tour runs solely when
    /// `VITRINE_SCREENSHOT_DIR` is provided, so `make test-ui` and CI never pay for it.
    override func setUpWithError() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["VITRINE_SCREENSHOT_DIR"] == nil,
            "Design-audit tour is opt-in: set TEST_RUNNER_VITRINE_SCREENSHOT_DIR")
    }

    // MARK: - Surfaces

    @MainActor
    func testWelcomeTour() throws {
        let app = launch(arguments: [])
        defer { app.terminate() }

        let window = element("welcome-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        save(window.screenshot(), as: "01-welcome", note: "Onboarding quick-start (first run)")

        // Inline sample-capture feedback state. NOTE: performs a real sample capture,
        // which places a PNG on the system clipboard.
        element("welcome-sample-capture-button", in: app).click()
        if element("welcome-sample-status", in: app).waitForExistence(timeout: 6) {
            save(
                window.screenshot(), as: "02-welcome-sample-status",
                note: "Onboarding after running the sample capture (inline status)")
        } else {
            miss("02-welcome-sample-status", reason: "sample status never appeared")
        }
    }

    @MainActor
    func testEditorTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo", "--open-editor"])
        defer { app.terminate() }

        let window = element("editor-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        XCTAssertTrue(element("editor-preview-stage", in: app).waitForExistence(timeout: 5))
        // Let the preview render settle before the hero shot.
        Thread.sleep(forTimeInterval: 1.5)
        save(
            window.screenshot(), as: "10-editor",
            note: "Editor: glass toolbar, code pane, ambient-light stage, inspector")

        let output = element("inspector-disclosure-output", in: app)
        if output.waitForExistence(timeout: 3) {
            output.click()
            _ = element("editor-destination-preset-picker", in: app).waitForExistence(timeout: 3)
            Thread.sleep(forTimeInterval: 0.5)
            save(
                window.screenshot(), as: "11-editor-inspector-output",
                note: "Editor inspector with the Output disclosure open")
        } else {
            miss("11-editor-inspector-output", reason: "Output disclosure not found")
        }
    }

    @MainActor
    func testEditorEmptyStateTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--open-editor"])
        defer { app.terminate() }

        let window = element("editor-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.0)
        save(
            window.screenshot(), as: "12-editor-empty-state",
            note: "Editor empty state (no code loaded)")
    }

    @MainActor
    func testSettingsTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--open-settings"])
        defer { app.terminate() }

        XCTAssertTrue(element("settings-general-pane", in: app).waitForExistence(timeout: 8))
        let panes: [(nav: String, identifier: String, slug: String)] = [
            ("settings-nav-general", "settings-general-pane", "20-settings-general"),
            ("settings-nav-style", "settings-style-pane", "21-settings-style"),
            ("settings-nav-library", "settings-library-pane", "22-settings-library"),
            ("settings-nav-output", "settings-output-pane", "23-settings-output"),
            ("settings-nav-input", "settings-input-pane", "24-settings-input"),
            ("settings-nav-about", "settings-about-pane", "25-settings-about"),
        ]
        let window = app.windows.firstMatch
        for pane in panes {
            element(pane.nav, in: app).click()
            guard element(pane.identifier, in: app).waitForExistence(timeout: 4) else {
                miss(pane.slug, reason: "pane \(pane.identifier) did not appear")
                continue
            }
            // Give the pane transition a beat to settle before capturing.
            Thread.sleep(forTimeInterval: 0.8)
            save(window.screenshot(), as: pane.slug, note: "Settings pane: \(pane.identifier)")
        }

        // The custom-theme editor sheet hangs off the Library pane.
        element("settings-nav-library", in: app).click()
        _ = element("settings-library-pane", in: app).waitForExistence(timeout: 4)
        let newTheme = element("new-custom-theme-button", in: app)
        if newTheme.waitForExistence(timeout: 3) {
            newTheme.click()
            if element("custom-theme-name-field", in: app).waitForExistence(timeout: 4) {
                Thread.sleep(forTimeInterval: 0.5)
                save(
                    window.screenshot(), as: "26-settings-custom-theme-editor",
                    note: "Custom theme editor sheet (Library pane)")
                app.typeKey(.escape, modifierFlags: [])
            } else {
                miss("26-settings-custom-theme-editor", reason: "theme editor never appeared")
            }
        } else {
            miss("26-settings-custom-theme-editor", reason: "new-custom-theme-button not found")
        }
    }

    @MainActor
    func testRecentsGalleryTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--open-recents"])
        defer { app.terminate() }

        let window = element("recents-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        XCTAssertTrue(element("recents-gallery", in: app).waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.5)
        save(
            window.screenshot(), as: "30-recents-gallery-empty",
            note: "Recents gallery (branded empty state — fresh defaults suite)")
    }

    @MainActor
    func testRecentsPresetRerenderTour() throws {
        let app = launch(
            arguments: ["--skip-onboarding", "--demo-recent", "--open-recents"])
        defer { app.terminate() }

        let window = element("recents-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        let picker = element("recents-preset-picker", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        save(
            window.screenshot(), as: "31-recents-gallery-populated",
            note: "Recents gallery with one locally rendered capture and preset action")

        if picker.isHittable {
            picker.click()
            let openGraph = app.menuItems["OpenGraph 1200×630"]
            if openGraph.waitForExistence(timeout: 3),
                let visibleMenu = app.menus.allElementsBoundByIndex.first(where: {
                    !$0.frame.isEmpty
                })
            {
                Thread.sleep(forTimeInterval: 0.3)
                save(
                    visibleMenu.screenshot(), as: "32-recents-destination-presets",
                    note: "One-off destination preset picker for a recent capture")
                app.typeKey(.escape, modifierFlags: [])
            } else {
                miss("32-recents-destination-presets", reason: "preset menu did not open")
            }
        } else {
            miss("32-recents-destination-presets", reason: "preset picker was not hittable")
        }
    }

    @MainActor
    func testRecentsSearchAndActionsTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo-recents", "--open-recents"])
        defer { app.terminate() }

        let window = element("recents-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        let search = element("recents-search-field", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("Rust")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "recents-card").count, 1)
        Thread.sleep(forTimeInterval: 0.4)
        save(
            window.screenshot(), as: "33-recents-search-filtered",
            note: "Recents filtered locally by source, language, or theme")

        if waitForHittableElement("recents-preset-picker", in: app, timeout: 3) {
            let actions = element("recents-preset-picker", in: app)
            actions.click()
            if app.menuItems["Delete Capture"].waitForExistence(timeout: 3),
                let visibleMenu = app.menus.allElementsBoundByIndex.first(where: {
                    !$0.frame.isEmpty
                })
            {
                Thread.sleep(forTimeInterval: 0.3)
                save(
                    visibleMenu.screenshot(), as: "34-recents-capture-actions",
                    note: "Destination presets and individual deletion for a recent capture")
                app.typeKey(.escape, modifierFlags: [])
            } else {
                miss("34-recents-capture-actions", reason: "capture actions menu did not open")
            }
        } else {
            miss("34-recents-capture-actions", reason: "capture actions menu was not hittable")
        }
    }

    @MainActor
    func testEditorSurpriseStyleTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo", "--open-editor"])
        defer { app.terminate() }

        let window = element("editor-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        let stageMatches = app.descendants(matching: .any).matching(
            identifier: "editor-preview-stage")
        XCTAssertTrue(stageMatches.firstMatch.waitForExistence(timeout: 5))
        let stage = try XCTUnwrap(
            stageMatches.allElementsBoundByIndex.max {
                $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
            })
        app.activate()
        window.click()
        Thread.sleep(forTimeInterval: 0.8)
        save(
            stage.screenshot(), as: "35-editor-before-surprise",
            note: "Editor before applying a curated style")
        XCTAssertTrue(waitForHittableElement("editor-style-preset-picker", in: app, timeout: 5))
        element("editor-style-preset-picker", in: app).click()
        let surprise = app.menuItems["Surprise Me"]
        XCTAssertTrue(surprise.waitForExistence(timeout: 3))
        surprise.click()
        let dracula = app.buttons["Dracula"].firstMatch
        XCTAssertTrue(dracula.waitForExistence(timeout: 3))
        let deadline = Date().addingTimeInterval(3)
        while !dracula.isSelected, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(dracula.isSelected)
        app.activate()
        window.click()
        Thread.sleep(forTimeInterval: 1.2)
        save(
            stage.screenshot(), as: "36-editor-surprise-style-applied",
            note: "Editor after applying the curated Sunset style without changing code")
    }

    @MainActor
    func testStickerToolTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo", "--open-editor"])
        defer { app.terminate() }

        let window = element("editor-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittableElement("annotation-tool-sticker", in: app, timeout: 5))
        element("annotation-tool-sticker", in: app).click()
        let swatch = element("annotation-sticker-swatch", in: app)
        XCTAssertTrue(swatch.waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.4)
        save(
            window.screenshot(), as: "56-editor-sticker-tool-active",
            note: "Sticker tool active: glyph swatch + size slider, no color swatch")

        if swatch.isHittable {
            swatch.click()
            Thread.sleep(forTimeInterval: 0.5)
            save(
                window.screenshot(), as: "57-editor-sticker-picker-open",
                note: "Curated sticker picker popover (👀 🔥 ✅ …)")
            app.typeKey(.escape, modifierFlags: [])
        } else {
            miss("57-editor-sticker-picker-open", reason: "sticker swatch was not hittable")
        }
    }

    @MainActor
    func testSafeAreaGuidesTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo", "--open-editor"])
        defer { app.terminate() }

        let window = element("editor-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        // Open the Output disclosure, pick a fixed-size destination, flip the guides on.
        XCTAssertTrue(waitForHittableElement("inspector-disclosure-output", in: app, timeout: 5))
        element("inspector-disclosure-output", in: app).click()
        let toggle = element("inspector-safe-area-toggle", in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        if toggle.isHittable {
            toggle.click()
            Thread.sleep(forTimeInterval: 0.6)
            save(
                window.screenshot(), as: "58-editor-safe-area-guides",
                note: "Safe-area guide toggle on: budget chip over the preview")
            toggle.click()  // leave the isolated defaults as found
        } else {
            miss("58-editor-safe-area-guides", reason: "safe-area toggle was not hittable")
        }
    }

    @MainActor
    func testHTMLPrettyPrintTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo-html-format", "--open-editor"])
        defer { app.terminate() }

        let window = element("editor-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittableElement("format-button", in: app, timeout: 5))
        element("format-button", in: app).click()

        let editor = element("code-editor-text-view", in: app)
        let deadline = Date().addingTimeInterval(3)
        while !(editor.value as? String ?? "").contains("\n  <h1>"), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue((editor.value as? String ?? "").contains("\n  <h1>"))
        Thread.sleep(forTimeInterval: 0.8)
        save(
            window.screenshot(), as: "59-editor-html-pretty-print",
            note: "Format Code expanded compact HTML into a readable element hierarchy")
    }

    @MainActor
    func testSQLPrettyPrintTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo-sql-format", "--open-editor"])
        defer { app.terminate() }

        let window = element("editor-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittableElement("format-button", in: app, timeout: 5))
        element("format-button", in: app).click()

        let editor = element("code-editor-text-view", in: app)
        let deadline = Date().addingTimeInterval(3)
        while !(editor.value as? String ?? "").contains("\nLEFT JOIN orders"), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue((editor.value as? String ?? "").contains("\nLEFT JOIN orders"))
        Thread.sleep(forTimeInterval: 0.8)
        save(
            window.screenshot(), as: "60-editor-sql-pretty-print",
            note: "Format Code expanded compact SQL into select, join, and predicate lines")
    }

    @MainActor
    func testPinnedRecentsTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo-recents", "--open-recents"])
        defer { app.terminate() }

        let window = element("recents-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        XCTAssertTrue(element("recents-pinned-badge", in: app).waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        save(
            window.screenshot(), as: "37-recents-pinned",
            note: "Pinned capture leading the local Recents gallery")

        let actions = app.descendants(matching: .any).matching(
            identifier: "recents-preset-picker"
        ).element(boundBy: 0)
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
        XCTAssertTrue(actions.isHittable)
        actions.click()
        if app.menuItems["Unpin Capture"].waitForExistence(timeout: 3),
            let visibleMenu = app.menus.allElementsBoundByIndex.first(where: {
                !$0.frame.isEmpty
            })
        {
            Thread.sleep(forTimeInterval: 0.3)
            save(
                visibleMenu.screenshot(), as: "38-recents-pinned-actions",
                note: "Pinned capture actions with a reversible Unpin command")
            app.typeKey(.escape, modifierFlags: [])
        } else {
            miss("38-recents-pinned-actions", reason: "pinned actions menu did not open")
        }
    }

    @MainActor
    func testPinnedRecentsFilterTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo-recents", "--open-recents"])
        defer { app.terminate() }

        let window = element("recents-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        let pinnedFilter = element("recents-pinned-filter", in: app)
        XCTAssertTrue(pinnedFilter.waitForExistence(timeout: 5))
        XCTAssertTrue(pinnedFilter.isHittable)
        pinnedFilter.click()

        let cards = app.descendants(matching: .any).matching(identifier: "recents-card")
        let deadline = Date().addingTimeInterval(3)
        while cards.count != 1, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(cards.count, 1)
        Thread.sleep(forTimeInterval: 0.6)
        save(
            window.screenshot(), as: "53-recents-pinned-filter",
            note: "Recents gallery filtered to the locally pinned captures")
    }

    @MainActor
    func testRecentSourceCopyActionTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo-recent", "--open-recents"])
        defer { app.terminate() }

        let window = element("recents-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        app.activate()
        let actions = element("recents-preset-picker", in: app)
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
        XCTAssertTrue(actions.isHittable)
        actions.click()

        if app.menuItems["Copy Source"].waitForExistence(timeout: 3),
            let visibleMenu = app.menus.allElementsBoundByIndex.first(where: {
                !$0.frame.isEmpty
            })
        {
            Thread.sleep(forTimeInterval: 0.3)
            save(
                visibleMenu.screenshot(), as: "54-recents-copy-source-action",
                note: "Recent capture actions exposing the original-source copy command")
            app.typeKey(.escape, modifierFlags: [])
        } else {
            miss("54-recents-copy-source-action", reason: "source-copy action menu did not open")
        }
    }

    @MainActor
    func testClearUnpinnedRecentsTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo-recents", "--open-recents"])
        defer { app.terminate() }

        let window = element("recents-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        let manage = element("recents-clear-button", in: app)
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        XCTAssertTrue(manage.isHittable)
        manage.click()

        let clearUnpinned = app.menuItems["Clear Unpinned"]
        XCTAssertTrue(clearUnpinned.waitForExistence(timeout: 3))
        clearUnpinned.click()
        let confirmation = app.sheets.firstMatch.buttons["Clear Unpinned"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.4)
        save(
            window.screenshot(), as: "56-recents-clear-unpinned-confirmation",
            note: "Safe Recents cleanup confirmation that explicitly preserves pinned captures")
    }

    @MainActor
    func testRecentsSortTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo-recents", "--open-recents"])
        defer { app.terminate() }

        let window = element("recents-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        let sort = element("recents-sort-picker", in: app)
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        XCTAssertTrue(sort.isHittable)
        sort.click()

        let oldestFirst = app.menuItems["Oldest First"]
        XCTAssertTrue(oldestFirst.waitForExistence(timeout: 3))
        if let visibleMenu = app.menus.allElementsBoundByIndex.first(where: { !$0.frame.isEmpty }) {
            Thread.sleep(forTimeInterval: 0.3)
            save(
                visibleMenu.screenshot(), as: "57-recents-sort-options",
                note: "Local Recents ordering choices with newest first selected")
        }
        oldestFirst.click()

        let cards = app.descendants(matching: .any).matching(identifier: "recents-card")
        let deadline = Date().addingTimeInterval(3)
        while !cards.element(boundBy: 1).label.contains("Python"), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(cards.element(boundBy: 0).label.contains("Go"))
        XCTAssertTrue(cards.element(boundBy: 1).label.contains("Python"))
        Thread.sleep(forTimeInterval: 0.5)
        save(
            window.screenshot(), as: "58-recents-oldest-first",
            note: "Recents sorted oldest-first within pinned and unpinned groups")
    }

    @MainActor
    func testHelpTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--show-help"])
        defer { app.terminate() }

        let window = element("help-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        XCTAssertTrue(element("help-view", in: app).waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.5)
        save(window.screenshot(), as: "40-help", note: "In-app Help window (offline topics)")
    }

    @MainActor
    func testWhatsNewTour() throws {
        let app = launch(arguments: ["--seen-old-version"])
        defer { app.terminate() }

        let window = element("whats-new-window", in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        XCTAssertTrue(element("whats-new-highlights", in: app).waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.5)
        save(window.screenshot(), as: "41-whats-new", note: "What's New release-notes window")
    }

    @MainActor
    func testMainMenuTour() throws {
        // `--standard-activation` runs the app as a regular (non-accessory) app for
        // this tour only: an LSUIElement app's menu-bar items never realize under
        // synthetic activation, so the menus cannot otherwise be opened or shot.
        let app = launch(
            arguments: ["--skip-onboarding", "--demo", "--open-editor", "--standard-activation"])
        defer { app.terminate() }

        let editor = element("editor-window", in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        makeFrontmostForMenuBarAccess(app, clicking: editor)
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5))

        for (title, slug) in [
            ("Vitrine", "60-mainmenu-app"),
            ("File", "61-mainmenu-file"),
            ("Edit", "62-mainmenu-edit"),
            ("View", "63-mainmenu-view"),
            ("Window", "64-mainmenu-window"),
            ("Help", "65-mainmenu-help"),
        ] {
            let item = menuBar.menuBarItems[title]
            guard item.exists, item.isHittable else {
                miss(slug, reason: "menu-bar item \(title) not found or not hittable")
                continue
            }
            item.click()
            let menu = item.menus.firstMatch
            if menu.waitForExistence(timeout: 3) {
                Thread.sleep(forTimeInterval: 0.3)
                save(menu.screenshot(), as: slug, note: "Main menu: \(title)")
            } else {
                miss(slug, reason: "menu \(title) did not open")
            }
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    @MainActor
    func testStatusItemMenuTour() throws {
        let app = launch(arguments: ["--skip-onboarding"])
        defer { app.terminate() }

        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 8), statusItem.isHittable else {
            // Off-screen/negative frames happen under some display arrangements;
            // the tour records a miss instead of failing (it is an audit, not a gate).
            miss("50-menubar-panel", reason: "status item not exposed or not hittable")
            return
        }
        // The redesigned status surface is a MenuBarExtra window panel, not an
        // NSMenu: clicking the item opens a panel window (design/handoff).
        statusItem.click()
        let panel = element("menubar-panel", in: app)
        if panel.waitForExistence(timeout: 3) {
            Thread.sleep(forTimeInterval: 0.5)
            save(panel.screenshot(), as: "50-menubar-panel", note: "Menu-bar panel (.window)")

            let presetPicker = element("menu-capture-preset-picker", in: app)
            if presetPicker.isHittable {
                presetPicker.click()
                let openGraph = app.menuItems["OpenGraph 1200×630"]
                if openGraph.waitForExistence(timeout: 3) {
                    Thread.sleep(forTimeInterval: 0.3)
                    if let visibleMenu = app.menus.allElementsBoundByIndex.first(where: {
                        !$0.frame.isEmpty
                    }) {
                        save(
                            visibleMenu.screenshot(), as: "51-menubar-destination-presets",
                            note: "Menu-bar one-off destination preset picker")
                    } else {
                        miss(
                            "51-menubar-destination-presets",
                            reason: "preset menu had no visible accessibility frame")
                    }
                    app.typeKey(.escape, modifierFlags: [])
                } else {
                    miss("51-menubar-destination-presets", reason: "preset menu did not open")
                }
            } else {
                miss("51-menubar-destination-presets", reason: "preset picker was not hittable")
            }
        } else {
            miss("50-menubar-panel", reason: "status panel did not open")
        }

        // The standard About panel, branded with the Settings About pane's identity copy.
        let about = app.buttons["command-about"]
        if about.waitForExistence(timeout: 3) {
            about.click()
            let aboutWindow = app.windows.firstMatch
            if aboutWindow.waitForExistence(timeout: 4) {
                Thread.sleep(forTimeInterval: 0.5)
                save(aboutWindow.screenshot(), as: "53-about-panel", note: "Standard About panel")
            } else {
                miss("53-about-panel", reason: "About panel did not appear")
            }
        } else {
            miss("53-about-panel", reason: "About command not reachable from status panel")
        }
    }

    @MainActor
    func testMenuBarSurpriseStyleTour() throws {
        let app = launch(arguments: ["--skip-onboarding"])
        defer { app.terminate() }

        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 8), statusItem.isHittable else {
            miss("52-menubar-surprise-style", reason: "status item not exposed or not hittable")
            return
        }
        statusItem.click()

        let panel = element("menubar-panel", in: app)
        guard panel.waitForExistence(timeout: 3) else {
            miss("52-menubar-surprise-style", reason: "status panel did not open")
            return
        }
        let surprise = element("menu-surprise-style-button", in: app)
        guard surprise.waitForExistence(timeout: 3), surprise.isHittable else {
            miss("52-menubar-surprise-style", reason: "curated style action was not hittable")
            return
        }
        surprise.click()
        let dracula = app.buttons["Dracula"].firstMatch
        let deadline = Date().addingTimeInterval(3)
        while !dracula.isSelected, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(dracula.isSelected)
        Thread.sleep(forTimeInterval: 0.5)
        save(
            panel.screenshot(), as: "52-menubar-surprise-style",
            note: "Menu-bar curated style action with the applied theme selected")
    }

    @MainActor
    func testMenuBarRecentSourceActionsTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--demo-recents"])
        defer { app.terminate() }
        app.activate()

        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 8), statusItem.isHittable else {
            miss("55-menubar-recent-copy-actions", reason: "status item is not reachable")
            return
        }
        statusItem.click()

        let panel = element("menubar-panel", in: app)
        guard panel.waitForExistence(timeout: 3) else {
            miss("55-menubar-recent-copy-actions", reason: "status panel did not open")
            return
        }
        guard element("menu-recent-copy-source", in: app).waitForExistence(timeout: 3) else {
            miss("55-menubar-recent-copy-actions", reason: "source-copy action is missing")
            return
        }
        Thread.sleep(forTimeInterval: 0.5)
        save(
            panel.screenshot(), as: "55-menubar-recent-copy-actions",
            note: "Menu-bar Recents rows with visible image and original-source copy actions")
    }

    @MainActor
    func testWebSnapshotTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--open-web-snapshot"])
        defer { app.terminate() }

        XCTAssertTrue(element("web-snapshot-inspector", in: app).waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.0)
        let window = app.windows.firstMatch
        save(
            window.screenshot(), as: "60-web-snapshot",
            note: "Web Snapshot: source picker, viewport chips, branded empty stage")

        // HTML mode swaps the input field and the empty-state copy.
        let html = element("web-snapshot-mode-html", in: app)
        if html.waitForExistence(timeout: 3) {
            html.click()
            Thread.sleep(forTimeInterval: 0.6)
            save(
                window.screenshot(), as: "61-web-snapshot-html",
                note: "Web Snapshot HTML mode (code field + branded empty state)")
        } else {
            miss("61-web-snapshot-html", reason: "HTML segment not found")
        }

        // The secondary capture controls fold into a disclosure (the editor pattern).
        let advanced = element("web-advanced-disclosure", in: app)
        if advanced.waitForExistence(timeout: 3) {
            advanced.click()
            Thread.sleep(forTimeInterval: 0.4)
            save(
                window.screenshot(), as: "62-web-snapshot-advanced",
                note: "Web Snapshot inspector with the Capture options disclosure open")
        } else {
            miss("62-web-snapshot-advanced", reason: "advanced disclosure not found")
        }
    }

    @MainActor
    func testSocialCardTour() throws {
        let app = launch(arguments: ["--skip-onboarding", "--open-social-card"])
        defer { app.terminate() }

        XCTAssertTrue(element("social-card-inspector", in: app).waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.0)
        let window = app.windows.firstMatch
        save(
            window.screenshot(), as: "63-social-card",
            note: "Social Card: template, content, code, footer, theme; advanced collapsed")

        // Typography and Background fold into disclosures so the panel leads with content.
        let typography = element("social-card-typography-disclosure", in: app)
        if typography.waitForExistence(timeout: 3) {
            typography.click()
            Thread.sleep(forTimeInterval: 0.4)
            save(
                window.screenshot(), as: "64-social-card-typography",
                note: "Social Card with the Typography disclosure open")
        } else {
            miss("64-social-card-typography", reason: "typography disclosure not found")
        }
    }

    // MARK: - Harness

    @MainActor
    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["VITRINE_USER_DEFAULTS_SUITE"] =
            "VitrineScreenshotTour-\(name)-\(UUID().uuidString)"
        app.launch()
        return app
    }

    private var outputDirectory: URL {
        let path =
            ProcessInfo.processInfo.environment["VITRINE_SCREENSHOT_DIR"]
            ?? NSTemporaryDirectory().appending("vitrine-ui-screenshots")
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func save(_ screenshot: XCUIScreenshot, as slug: String, note: String) {
        let directory = outputDirectory
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("\(slug).png")
            try screenshot.pngRepresentation.write(to: file)
            log("\(slug).png — \(note)")
        } catch {
            // Sandboxed runner fallback: keep the image in the result bundle.
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = slug
            attachment.lifetime = .keepAlways
            add(attachment)
            log("\(slug) (attachment only — disk write failed: \(error.localizedDescription))")
        }
    }

    private func miss(_ slug: String, reason: String) {
        log("MISS \(slug) — \(reason)")
    }

    private func log(_ line: String) {
        let manifest = outputDirectory.appendingPathComponent("manifest.txt")
        let entry = line + "\n"
        if let handle = try? FileHandle(forWritingTo: manifest) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? FileManager.default.createDirectory(
                at: outputDirectory, withIntermediateDirectories: true)
            try? entry.write(to: manifest, atomically: true, encoding: .utf8)
        }
    }
}
