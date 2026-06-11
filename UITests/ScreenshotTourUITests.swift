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
        // An accessory (LSUIElement) app only owns the on-screen menu bar while it is
        // truly frontmost. `XCUIApplication.activate()` alone leaves the menu-bar
        // items with zero-size frames here, so click the editor window — a real
        // synthetic click is what makes macOS hand the menu bar to the accessory app.
        app.activate()
        editor.click()
        Thread.sleep(forTimeInterval: 1.5)
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
        guard statusItem.waitForExistence(timeout: 8) else {
            miss("50-menubar-panel", reason: "status item not exposed to automation")
            return
        }
        // The redesigned status surface is a MenuBarExtra window panel, not an
        // NSMenu: clicking the item opens a panel window (design/handoff).
        statusItem.click()
        let panel = element("menubar-panel", in: app)
        if panel.waitForExistence(timeout: 3) {
            Thread.sleep(forTimeInterval: 0.5)
            save(panel.screenshot(), as: "50-menubar-panel", note: "Menu-bar panel (.window)")
        } else {
            miss("50-menubar-panel", reason: "status panel did not open")
        }

        // The standard About panel, branded with the Settings About pane's identity copy.
        let about = element("command-about", in: app)
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

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
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
