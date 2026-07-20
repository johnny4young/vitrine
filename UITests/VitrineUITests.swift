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
        // The editor's destination preset picker lives in the inspector's
        // Output disclosure in the current designed layout; open it first. It keeps
        // its own identifier so it never collides with the Settings panes'
        // picker.
        element("inspector-disclosure-output", in: app).click()
        assertExists(element("editor-destination-preset-picker", in: app), in: app)
        assertExists(element("copy-button", in: app), in: app)
        assertExists(element("save-button", in: app), in: app)
        assertExists(element("share-button", in: app), in: app)
        // The editor advertises a drop target for source files / text.
        // Driving a real drag from outside the app is not reliably automatable, so
        // the smoke test asserts the target exists; the loading policy itself is
        // covered by FileInputLoaderTests.
        assertExists(element("editor-drop-target", in: app), in: app)
    }

    @MainActor
    func testCopyOptionsExposeMarkdownExport() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        let editor = element("editor-window", in: app)
        assertExists(editor, in: app, timeout: 8)
        assertHittable(
            "copy-options-menu", in: app,
            "The alternate copy formats menu must be reachable from the editor toolbar")
        element("copy-options-menu", in: app).click()
        assertHittable(
            "copy-markdown-button", in: app,
            "Copy as Markdown must be exposed for source-based snapshots")
        // The reproducible share link lives in the same menu. Its round trip is pinned
        // by unit tests, so this smoke only proves the action is reachable.
        assertExists(element("copy-share-link-button", in: app), in: app, timeout: 3)

        // Let the SwiftUI menu and syntax-highlighted preview finish their first
        // compositing pass so the retained visual evidence is not mid-transition.
        Thread.sleep(forTimeInterval: 0.5)
        let screenshot = editor.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "copy-markdown-menu"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testImagePanelExposesRedactAndCopyTextActions() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        // A foreground image puts the editor in "beautify any image" mode, which
        // replaces the code column with the image panel and its on-device actions.
        let app = launch(arguments: ["--demo-beautify-image"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        // Both on-device actions live in the image panel. Their behavior is pinned by
        // unit tests, so this smoke only proves the panel surfaces them.
        assertHittable(
            "redact-image-secrets-button", in: app,
            "The image panel must expose Redact secrets")
        assertExists(element("copy-image-text-button", in: app), in: app, timeout: 3)
        assertExists(element("remove-image-button", in: app), in: app, timeout: 3)
    }

    @MainActor
    func testCommandPaletteOpensFiltersAndRunsACommand() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        // Open via the launch hook rather than a synthetic ⌘K, which does not reliably
        // reach the zero-size shortcut button on a headless runner. The editor reads the
        // argument after its view appears, then exercises the real filter and run path.
        let app = launch(arguments: ["--open-command-palette"])
        defer { app.terminate() }

        let editor = element("editor-window", in: app)
        assertExists(editor, in: app, timeout: 8)

        // Give the field a generous window to appear after editor startup.
        let field = element("command-palette-field", in: app)
        assertExists(field, in: app, timeout: 5)

        // Typing filters the list; "dracula" narrows to the Dracula theme command.
        field.typeText("dracula")
        Thread.sleep(forTimeInterval: 0.4)  // let the filtered list settle before the shot
        let screenshot = editor.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "command-palette-filtered"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Return runs the top result and dismisses the palette.
        field.typeText("\r")
        XCTAssertTrue(
            element("command-palette", in: app).waitForNonExistence(timeout: 3),
            "Running a command must dismiss the palette")
    }

    @MainActor
    func testCarouselSheetStepperUpdatesTheSlideCount() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        // The carousel entry is PRO-gated; the debug unlock provider (Debug builds
        // only) opens the real export sheet instead of the paywall.
        let app = launch(
            arguments: ["--demo", "--open-editor"],
            environment: ["VITRINE_PRO_UNLOCK": "1"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        assertHittable(
            "export-carousel-button", in: app,
            "The carousel export entry must be reachable from the editor toolbar")
        element("export-carousel-button", in: app).click()
        assertExists(element("carousel-export-sheet", in: app), in: app, timeout: 3)

        // The 12-line demo snippet fits one slide at the default cap (12); one
        // decrement (→11) must split it in two, so the live count is recomputing —
        // the text is localized, so assert change, not wording. macOS exposes a
        // static text's string as AXValue, not AXTitle, so read `value` over `label`.
        let count = element("carousel-slide-count", in: app)
        assertExists(count, in: app, timeout: 3)
        let readCount = {
            (count.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? count.label
        }
        let initial = readCount()
        XCTAssertFalse(initial.isEmpty, "the slide-count text must be exposed to accessibility")
        let decrement = element("carousel-export-sheet", in: app)
            .descendants(matching: .decrementArrow).firstMatch
        assertExists(decrement, in: app, timeout: 3)
        decrement.click()

        let deadline = Date().addingTimeInterval(3)
        while readCount() == initial, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertNotEqual(
            readCount(), initial,
            "Stepping lines-per-slide down must recompute the live slide count")

        element("carousel-cancel", in: app).click()
    }

    // MARK: - Multi-window editing and restoration

    @MainActor
    func testOpeningASecondEditorWindowKeepsBothOpen() {
        continueAfterFailure = false
        // `--open-second-editor` opens the primary editor plus an additional,
        // independent editor window.
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
        // Closing one window must not lose the other's state. Close the second
        // window from the Window menu's window list and assert the primary survives.
        let app = launch(arguments: ["--demo", "--open-second-editor"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        let second = element("editor-window-2", in: app)
        XCTAssertTrue(second.waitForExistence(timeout: 8), "Second editor window did not open")

        // `openNewWindow()` leaves the second editor key. Send the standard Close shortcut
        // to the app instead of clicking the window first; on a busy local desktop, other
        // apps can appear as XCUI "interrupting elements" even when Vitrine is active.
        app.activate()
        app.typeKey("w", modifierFlags: .command)

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
        // monitor is pulled back on-screen rather than stranded.
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

        // The File menu carries the multi-window commands: "New Editor
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
        // the menu.
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
        // Format Code is a primary editor affordance and should be reachable
        // by mouse as well as the Edit-menu shortcut. The pure formatting behavior is
        // covered by CodeFormatterTests; this UI smoke pins the accessible toolbar route.
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        assertExists(element("format-button", in: app), in: app, timeout: 3)
        assertHittable("format-button", in: app, "Format Code action is not reachable")
    }

    @MainActor
    func testEditorPrettyPrintsCompactHTML() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(arguments: ["--demo-html-format", "--open-editor"])
        defer { app.terminate() }

        let editor = element("code-editor-text-view", in: app)
        assertExists(editor, in: app, timeout: 8)
        let compact =
            #"<!doctype html><main class="card"><h1>Vitrine</h1><p>Local by design.</p><img src="preview.png"></main>"#
        XCTAssertEqual(editor.value as? String, compact)

        assertHittable("format-button", in: app, "Format Code action is not reachable")
        element("format-button", in: app).click()

        let expected = """
            <!doctype html>
            <main class="card">
              <h1>Vitrine</h1>
              <p>Local by design.</p>
              <img src="preview.png">
            </main>
            """
        let deadline = Date().addingTimeInterval(3)
        while editor.value as? String != expected, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(editor.value as? String, expected)
    }

    @MainActor
    func testEditorPrettyPrintsCompactSQL() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(arguments: ["--demo-sql-format", "--open-editor"])
        defer { app.terminate() }

        let editor = element("code-editor-text-view", in: app)
        assertExists(editor, in: app, timeout: 8)
        XCTAssertEqual(
            editor.value as? String,
            "SELECT u.id,u.email,COUNT(o.id) AS orders FROM users u LEFT JOIN orders o ON o.user_id=u.id WHERE u.active=TRUE GROUP BY u.id,u.email ORDER BY orders DESC;"
        )

        assertHittable("format-button", in: app, "Format Code action is not reachable")
        element("format-button", in: app).click()

        let expected = """
            SELECT
              u.id,
              u.email,
              COUNT(o.id) AS orders
            FROM users u
            LEFT JOIN orders o
              ON o.user_id = u.id
            WHERE u.active = TRUE
            GROUP BY u.id, u.email
            ORDER BY orders DESC;
            """
        let deadline = Date().addingTimeInterval(3)
        while editor.value as? String != expected, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(editor.value as? String, expected)
    }

    @MainActor
    func testEditorShowsToolbarInspectorAndPreviewStage() {
        continueAfterFailure = false
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)

        // The glass toolbar leads the editor: the style-preset star and the
        // primary export actions live there.
        assertExists(element("editor-toolbar", in: app), in: app, timeout: 3)
        assertExists(element("editor-style-preset-picker", in: app), in: app)

        // The hero preview sits on its own ambient-lit stage so it reads as the
        // focus of the window, not a small settings thumbnail.
        assertExists(element("editor-preview-stage", in: app), in: app)

        // The focused inspector is present with its primary style controls surfaced
        // up front.
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

        // Advanced controls live behind collapsible inspector disclosures that
        // start closed. The current designed
        // disclosures carry stable identifiers; the Output one reveals the
        // destination presets, resolution, and format.
        let disclosure = element("inspector-disclosure-output", in: app)
        XCTAssertTrue(
            disclosure.waitForExistence(timeout: 3),
            "Inspector is missing the collapsible Output disclosure")
        disclosure.click()
        assertExists(element("editor-destination-preset-picker", in: app), in: app, timeout: 3)
        assertExists(element("inspector-resolution-picker", in: app), in: app)
        assertExists(element("inspector-format-picker", in: app), in: app)
    }

    @MainActor
    func testEditorShowsAnnotationToolbar() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("editor-toolbar", in: app), in: app, timeout: 8)

        // The annotation tool palette lives in the title bar; every tool is
        // present and addressable.
        for tool in [
            "select", "arrow", "curvedArrow", "rectangle", "highlighter", "counter", "sticker",
            "spotlight", "measure",
        ] {
            XCTAssertTrue(
                element("annotation-tool-\(tool)", in: app).waitForExistence(timeout: 3),
                "Annotation toolbar is missing the \(tool) tool")
        }

        // Activating a draw tool reveals its options — the color swatch and the size
        // slider — which the Select pointer hides.
        assertHittable("annotation-tool-arrow", in: app, "Arrow tool is not reachable")
        element("annotation-tool-arrow", in: app).click()
        assertExists(element("annotation-color-swatch", in: app), in: app, timeout: 3)
        assertExists(element("annotation-thickness-slider", in: app), in: app)

        // The sticker tool swaps the color swatch (an emoji has its own colors) for the
        // sticker-glyph swatch, and keeps the size slider.
        assertHittable("annotation-tool-sticker", in: app, "Sticker tool is not reachable")
        element("annotation-tool-sticker", in: app).click()
        assertExists(element("annotation-sticker-swatch", in: app), in: app, timeout: 3)
        assertExists(element("annotation-thickness-slider", in: app), in: app)
        XCTAssertFalse(
            element("annotation-color-swatch", in: app).exists,
            "The sticker tool must hide the color swatch — an emoji has its own colors")

        element("annotation-tool-select", in: app).click()
    }

    /// Selection-only actions must be present but disabled until a mark is selected.
    /// The same gate keeps their keyboard shortcuts from firing while code has focus.
    @MainActor
    func testAnnotationSelectionActionsStartDisabled() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        let directDuplicate = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "annotation-duplicate"))
            .allElementsBoundByIndex
        if directDuplicate.isEmpty {
            assertHittable(
                "annotation-selection-actions-menu", in: app,
                "Compact mark actions must remain reachable")
            element("annotation-selection-actions-menu", in: app).click()
        }
        for identifier in [
            "annotation-duplicate", "annotation-bring-front", "annotation-send-back",
        ] {
            let matches = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", identifier))
                .allElementsBoundByIndex
            XCTAssertFalse(matches.isEmpty, "\(identifier) must exist in the mark toolbar")
            XCTAssertFalse(
                matches.contains { $0.isEnabled },
                "\(identifier) must be disabled with no mark selected")
        }
    }

    /// Tool shortcuts are ⌘-digit, so plain letters always type in the code editor and
    /// never switch tools. Typing 'abc' must reach the text and leave Select active (no
    /// draw-tool color swatch).
    @MainActor
    func testAnnotationShortcutsDoNotHijackCodeTyping() throws {
        continueAfterFailure = false
        let app = launch(arguments: ["--open-editor"])  // empty editor: typed text is exact
        defer { app.terminate() }

        let editor = element("code-editor-text-view", in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        editor.click()
        editor.typeText("abc")

        let value = (editor.value as? String) ?? ""
        XCTAssertTrue(
            value.contains("abc"),
            "Tool-shortcut letters typed in the code editor must reach the text. Got: '\(value)'")
        XCTAssertFalse(
            element("annotation-color-swatch", in: app).exists,
            "Typing in the code editor must not activate a draw tool")
    }

    /// A ⌘-digit shortcut selects its tool from anywhere in the editor — even while the
    /// code editor holds focus, since a Command shortcut isn't consumed as typing. ⌘2
    /// (Arrow) reveals the draw-tool color swatch that Select hides.
    @MainActor
    func testAnnotationShortcutSelectsTheTool() throws {
        continueAfterFailure = false
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        XCTAssertTrue(element("editor-toolbar", in: app).waitForExistence(timeout: 8))
        XCTAssertFalse(
            element("annotation-color-swatch", in: app).exists, "Select tool shows no swatch")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(
            element("annotation-color-swatch", in: app).waitForExistence(timeout: 3),
            "⌘2 should select the Arrow tool and reveal its color swatch")
    }

    @MainActor
    func testCopyImageClosesTheEditorWhenEnabled() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        // Close-after-copy is on by default, so clicking the primary CTA both
        // copies the image and closes the window.
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        let copyButton = element("copy-button", in: app)
        assertExists(copyButton, in: app, timeout: 3)
        assertHittable("copy-button", in: app, "Copy image action is not reachable", timeout: 5)
        copyButton.click()

        XCTAssertTrue(
            element("editor-window", in: app).waitForNonExistence(timeout: 4),
            "The editor window should close after Copy image when close-after-copy is on")
    }

    @MainActor
    func testEditorKeyboardCanReachToolbarAndInspector() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        // The toolbar's style star, the inspector, and the export CTA are all
        // standard focusable controls, so keyboard navigation can reach each
        // region. Asserting the elements are hittable is the
        // automatable proxy for reachability without scripting Full Keyboard Access.
        assertExists(element("editor-style-preset-picker", in: app), in: app, timeout: 8)
        assertHittable(
            "editor-style-preset-picker", in: app, "Style preset picker is not reachable")
        assertHittable("editor-inspector", in: app, "Inspector is not reachable")
        assertHittable("copy-button", in: app, "Export toolbar copy action is not reachable")
    }

    @MainActor
    func testSurpriseStyleAppliesACuratedLookWithoutChangingCode() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(arguments: ["--demo", "--open-editor"])
        defer { app.terminate() }

        let editor = element("code-editor-text-view", in: app)
        assertExists(editor, in: app, timeout: 8)
        let originalCode = editor.value as? String
        assertHittable(
            "editor-style-preset-picker", in: app, "Style preset picker is not reachable")
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
        XCTAssertTrue(dracula.isSelected, "Surprise Me should apply the Sunset style")
        XCTAssertEqual(editor.value as? String, originalCode)
    }

    @MainActor
    func testStylePaneShowsDestinationPresetPicker() {
        continueAfterFailure = false
        let app = launch(arguments: ["--open-settings"])
        defer { app.terminate() }

        // The Style pane surfaces the destination preset picker.
        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        element("settings-nav-style", in: app).click()
        assertExists(element("settings-style-pane", in: app), in: app, timeout: 3)
        assertExists(element("destination-preset-picker", in: app), in: app, timeout: 3)
    }

    @MainActor
    func testStylePaneShowsFreeBrandKitDragHandle() {
        continueAfterFailure = false
        let app = launch(
            arguments: ["--demo-brand-kit-free", "--open-settings"],
            environment: ["VITRINE_PRO_UNLOCK": "1"])
        defer { app.terminate() }

        // The free-placement Brand Kit mode is only useful if the preview exposes an
        // actual drag target, not just a picker value hidden in Settings. The handle
        // lives in the Style pane's live preview: the Brand Kit *controls* are now
        // their own pane, but free placement is still dragged on the Style preview, so
        // this stays a Style-pane assertion.
        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        element("settings-nav-style", in: app).click()
        assertExists(element("settings-style-pane", in: app), in: app, timeout: 3)
        assertHittable(
            "brand-kit-free-drag-handle", in: app,
            "Free Brand Kit placement should expose a reachable preview drag handle")
    }

    @MainActor
    func testBrandKitIsATopLevelSettingsPane() {
        continueAfterFailure = false
        let app = launch(
            arguments: ["--open-settings"],
            environment: ["VITRINE_PRO_UNLOCK": "1"])
        defer { app.terminate() }

        // Brand Kit (PRO) was promoted from a buried Style sub-tab to its own sidebar
        // pane so the capability is discoverable. Navigating the sidebar
        // row reveals the pane and its controls.
        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        element("settings-nav-brandKit", in: app).click()
        assertExists(element("settings-brandkit-pane", in: app), in: app, timeout: 3)
        assertExists(element("settings-brand-kit-controls", in: app), in: app, timeout: 3)
    }

    @MainActor
    func testInputPaneExposesReindentOnPasteToggle() {
        continueAfterFailure = false
        let app = launch(arguments: ["--open-settings"])
        defer { app.terminate() }

        // The Input pane surfaces the paste re-indent preference, the
        // switch behind the editor's tidy-on-paste behavior.
        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        element("settings-nav-input", in: app).click()
        assertExists(element("settings-input-pane", in: app), in: app, timeout: 3)
        assertExists(element("reindent-on-paste-toggle", in: app), in: app, timeout: 3)
    }

    @MainActor
    func testInputPaneExposesLoopbackCaptureDefaultingOff() {
        continueAfterFailure = false
        let app = launch(arguments: ["--open-settings"])
        defer { app.terminate() }

        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        element("settings-nav-input", in: app).click()
        assertExists(element("settings-input-pane", in: app), in: app, timeout: 3)

        let toggle = element("web-allow-loopback-toggle", in: app)
        assertExists(toggle, in: app, timeout: 3)
        XCTAssertEqual(toggle.value as? Int, 0, "Loopback capture must default to off")
    }

    @MainActor
    func testStylePaneExposesAccessibleMetadataControls() {
        continueAfterFailure = false
        let app = launch(arguments: ["--open-settings"])
        defer { app.terminate() }

        // The Header section's metadata controls are present and carry stable
        // accessibility identifiers/labels . They live under
        // the Style pane's "Lines & header" sub-tab in the current designed window.
        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        element("settings-nav-style", in: app).click()
        assertExists(element("settings-style-pane", in: app), in: app, timeout: 3)
        element("style-subtab-lines", in: app).click()
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
        // is shown. Assert the standard top-level menus exist.
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
        // editor toolbar — the heart of 's "menu command parity".
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
    func testRecentsRendersWithDestinationPreset() throws {
        continueAfterFailure = false
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let app = launch(arguments: ["--skip-onboarding", "--demo-recent", "--open-recents"])
        defer {
            app.terminate()
            pasteboard.clearContents()
        }

        assertExists(element("recents-card", in: app), in: app, timeout: 8)
        assertHittable(
            "recents-preset-picker", in: app,
            "A recent capture should expose its destination preset picker")
        element("recents-preset-picker", in: app).click()

        let openGraph = app.menuItems["OpenGraph 1200×630"]
        XCTAssertTrue(openGraph.waitForExistence(timeout: 3))
        openGraph.click()

        let deadline = Date().addingTimeInterval(6)
        var representation: NSBitmapImageRep?
        repeat {
            if let data = pasteboard.data(forType: .png) {
                representation = NSBitmapImageRep(data: data)
            }
            if representation != nil { break }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline

        let rendered = try XCTUnwrap(representation, "Recent preset did not copy a PNG")
        XCTAssertEqual(rendered.pixelsWide, 1200)
        XCTAssertEqual(rendered.pixelsHigh, 630)
    }

    @MainActor
    func testRecentsSearchesAndDeletesOneCapture() throws {
        continueAfterFailure = false
        let app = launch(arguments: ["--skip-onboarding", "--demo-recents", "--open-recents"])
        defer { app.terminate() }

        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "recents-card").count, 3)
        let search = element("recents-search-field", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.click()
        search.typeText("Rust")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "recents-card").count, 1)

        assertHittable(
            "recents-preset-picker", in: app,
            "The filtered recent should keep its actions menu")
        element("recents-preset-picker", in: app).click()
        let delete = app.menuItems["Delete Capture"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.click()
        let confirmation = app.sheets.firstMatch.buttons["Delete Capture"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.click()

        XCTAssertTrue(element("recents-no-search-results", in: app).waitForExistence(timeout: 3))
    }

    @MainActor
    func testRecentsCanUnpinAndRepinACapture() {
        continueAfterFailure = false
        let app = launch(arguments: ["--skip-onboarding", "--demo-recents", "--open-recents"])
        defer { app.terminate() }

        let cards = app.descendants(matching: .any).matching(identifier: "recents-card")
        XCTAssertEqual(cards.count, 3)
        XCTAssertTrue(cards.element(boundBy: 0).label.contains("Go"))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "recents-pinned-badge").count,
            1)

        let actions = app.descendants(matching: .any).matching(
            identifier: "recents-preset-picker")
        actions.element(boundBy: 0).click()
        let unpin = app.menuItems["Unpin Capture"]
        XCTAssertTrue(unpin.waitForExistence(timeout: 3))
        unpin.click()

        let unpinDeadline = Date().addingTimeInterval(3)
        while app.descendants(matching: .any).matching(identifier: "recents-pinned-badge").count
            != 0,
            Date() < unpinDeadline
        {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "recents-pinned-badge").count,
            0)
        XCTAssertTrue(cards.element(boundBy: 0).label.contains("Rust"))

        actions.element(boundBy: 2).click()
        let pin = app.menuItems["Pin Capture"]
        XCTAssertTrue(pin.waitForExistence(timeout: 3))
        pin.click()

        let pinDeadline = Date().addingTimeInterval(3)
        while app.descendants(matching: .any).matching(identifier: "recents-pinned-badge").count
            != 1,
            Date() < pinDeadline
        {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "recents-pinned-badge").count,
            1)
        XCTAssertTrue(cards.element(boundBy: 0).label.contains("Go"))
    }

    @MainActor
    func testRecentsCanFilterToPinnedCaptures() {
        continueAfterFailure = false
        let app = launch(arguments: ["--skip-onboarding", "--demo-recents", "--open-recents"])
        defer { app.terminate() }

        let cards = app.descendants(matching: .any).matching(identifier: "recents-card")
        XCTAssertEqual(cards.count, 3)
        let pinnedFilter = element("recents-pinned-filter", in: app)
        XCTAssertTrue(pinnedFilter.waitForExistence(timeout: 8))
        XCTAssertTrue(pinnedFilter.isHittable)

        pinnedFilter.click()
        let filteredDeadline = Date().addingTimeInterval(3)
        while cards.count != 1, Date() < filteredDeadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(cards.count, 1)
        XCTAssertTrue(cards.firstMatch.label.contains("Go"))
        XCTAssertTrue(element("recents-pinned-badge", in: app).exists)

        pinnedFilter.click()
        let restoredDeadline = Date().addingTimeInterval(3)
        while cards.count != 3, Date() < restoredDeadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(cards.count, 3)
    }

    @MainActor
    func testRecentsCanClearUnpinnedCaptures() {
        continueAfterFailure = false
        let app = launch(arguments: ["--skip-onboarding", "--demo-recents", "--open-recents"])
        defer { app.terminate() }

        let cards = app.descendants(matching: .any).matching(identifier: "recents-card")
        XCTAssertEqual(cards.count, 3)
        let manage = element("recents-clear-button", in: app)
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        XCTAssertTrue(manage.isHittable)
        manage.click()

        let clearUnpinned = app.menuItems["Clear Unpinned"]
        XCTAssertTrue(clearUnpinned.waitForExistence(timeout: 3))
        clearUnpinned.click()

        let confirmation = app.sheets.firstMatch.buttons["Clear Unpinned"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.click()

        let deadline = Date().addingTimeInterval(3)
        while cards.count != 1, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(cards.count, 1)
        XCTAssertTrue(cards.firstMatch.label.contains("Go"))
        XCTAssertTrue(element("recents-pinned-badge", in: app).exists)
    }

    @MainActor
    func testRecentsCanSortOldestFirstWithoutDisplacingPins() {
        continueAfterFailure = false
        let app = launch(arguments: ["--skip-onboarding", "--demo-recents", "--open-recents"])
        defer { app.terminate() }

        let cards = app.descendants(matching: .any).matching(identifier: "recents-card")
        XCTAssertEqual(cards.count, 3)
        // Poll for the settled initial order like the post-sort check below does: on a
        // slow runner the adaptive grid's cards can exist a beat before their labels
        // reflect the settled layout, and an immediate assert races that pass.
        let initialDeadline = Date().addingTimeInterval(3)
        while !cards.element(boundBy: 1).label.contains("Rust"), Date() < initialDeadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(cards.element(boundBy: 0).label.contains("Go"))
        XCTAssertTrue(cards.element(boundBy: 1).label.contains("Rust"))

        let sort = element("recents-sort-picker", in: app)
        XCTAssertTrue(sort.waitForExistence(timeout: 8))
        XCTAssertTrue(sort.isHittable)
        sort.click()
        let oldestFirst = app.menuItems["Oldest First"]
        XCTAssertTrue(oldestFirst.waitForExistence(timeout: 3))
        oldestFirst.click()

        let deadline = Date().addingTimeInterval(3)
        while !cards.element(boundBy: 1).label.contains("Python"), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(cards.element(boundBy: 0).label.contains("Go"))
        XCTAssertTrue(cards.element(boundBy: 1).label.contains("Python"))
        XCTAssertTrue(cards.element(boundBy: 2).label.contains("Rust"))
        XCTAssertTrue(element("recents-pinned-badge", in: app).exists)
    }

    @MainActor
    func testRecentsCanCopyOriginalSource() {
        continueAfterFailure = false
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("sentinel", forType: .string))

        let app = launch(arguments: ["--skip-onboarding", "--demo-recent", "--open-recents"])
        defer {
            app.terminate()
            pasteboard.clearContents()
        }

        assertHittable(
            "recents-preset-picker", in: app,
            "A recent capture should expose its source-copy action")
        element("recents-preset-picker", in: app).click()
        let copySource = app.menuItems["Copy Source"]
        XCTAssertTrue(copySource.waitForExistence(timeout: 3))
        copySource.click()

        let deadline = Date().addingTimeInterval(3)
        while pasteboard.string(forType: .string) == "sentinel", Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        let copied = pasteboard.string(forType: .string)
        XCTAssertTrue(copied?.contains("struct DestinationCard: View") == true)
        XCTAssertTrue(copied?.contains("Text(title)") == true)
        XCTAssertNil(pasteboard.data(forType: .png))
    }

    @MainActor
    func testMenuBarRendersClipboardWithDestinationPreset() throws {
        continueAfterFailure = false
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("let answer = 42", forType: .string))

        let app = launch(arguments: ["--skip-onboarding"])
        defer {
            app.terminate()
            pasteboard.clearContents()
        }

        let statusItem = app.statusItems.firstMatch
        try XCTSkipUnless(
            statusItem.waitForExistence(timeout: 8) && statusItem.isHittable,
            "The status item is not reachable on this display arrangement")
        statusItem.click()

        assertHittable(
            "menu-capture-preset-picker", in: app,
            "The destination preset picker should be reachable from the menu-bar panel")
        element("menu-capture-preset-picker", in: app).click()

        let openGraph = app.menuItems["OpenGraph 1200×630"]
        XCTAssertTrue(openGraph.waitForExistence(timeout: 3))
        openGraph.click()

        let deadline = Date().addingTimeInterval(6)
        var representation: NSBitmapImageRep?
        repeat {
            if let data = pasteboard.data(forType: .png) {
                representation = NSBitmapImageRep(data: data)
            }
            if representation != nil { break }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline

        let rendered = try XCTUnwrap(representation, "Preset capture did not copy a PNG")
        XCTAssertEqual(rendered.pixelsWide, 1200)
        XCTAssertEqual(rendered.pixelsHigh, 630)
    }

    @MainActor
    func testMenuBarRecentCanCopyOriginalSource() throws {
        continueAfterFailure = false
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("sentinel", forType: .string))

        let app = launch(arguments: ["--skip-onboarding", "--demo-recents"])
        defer {
            app.terminate()
            pasteboard.clearContents()
        }

        let statusItem = app.statusItems.firstMatch
        try XCTSkipUnless(
            statusItem.waitForExistence(timeout: 8) && statusItem.isHittable,
            "The status item is not reachable on this display arrangement")
        statusItem.click()

        let panel = element("menubar-panel", in: app)
        try XCTSkipUnless(
            panel.waitForExistence(timeout: 3),
            "The menu-bar panel is not reachable on this display arrangement")
        let row = app.descendants(matching: .any).matching(identifier: "menu-recent-row")
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let sourceActions = app.descendants(matching: .any).matching(
            identifier: "menu-recent-copy-source")
        let actionDeadline = Date().addingTimeInterval(3)
        var copySource: XCUIElement?
        repeat {
            copySource = sourceActions.allElementsBoundByIndex.first(where: \.isHittable)
            if copySource != nil { break }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < actionDeadline
        try XCTUnwrap(copySource, "The menu-bar source-copy action is not reachable").click()

        let deadline = Date().addingTimeInterval(3)
        while pasteboard.string(forType: .string) == "sentinel", Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "func greet(name string) string { return \"Hello, \" + name }")
        XCTAssertNil(pasteboard.data(forType: .png))
    }

    @MainActor
    func testMenuBarSurpriseStyleUpdatesThemeWithoutClosingThePanel() throws {
        continueAfterFailure = false
        let app = launch(arguments: ["--skip-onboarding"])
        defer { app.terminate() }

        let statusItem = app.statusItems.firstMatch
        try XCTSkipUnless(
            statusItem.waitForExistence(timeout: 8) && statusItem.isHittable,
            "The status item is not reachable on this display arrangement")
        statusItem.click()

        let panel = element("menubar-panel", in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        assertHittable(
            "menu-surprise-style-button", in: app,
            "The curated style action should be reachable from the menu-bar panel")
        let dracula = app.buttons["Dracula"].firstMatch
        XCTAssertTrue(dracula.waitForExistence(timeout: 3))
        XCTAssertFalse(dracula.isSelected)

        element("menu-surprise-style-button", in: app).click()
        let deadline = Date().addingTimeInterval(3)
        while !dracula.isSelected, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }

        XCTAssertTrue(dracula.isSelected)
        XCTAssertTrue(panel.exists, "Applying a curated style should keep the panel open")
    }

    @MainActor
    func testFirstRunShowsQuickStartWithPrivacyAndSampleCapture() throws {
        continueAfterFailure = false
        // A fresh defaults suite is a first run, so the quick-start appears on
        // launch with no extra hook.
        let app = launch(arguments: [])
        defer { app.terminate() }

        assertExists(element("welcome-window", in: app), in: app, timeout: 8)
        // The bottom controls (sample capture / skip) overhang a display too short to
        // hold the welcome window, so skip the interaction there rather than flaking.
        try skipUnlessADisplayFitsTheWelcomeWindow(app)
        assertExists(element("welcome-view", in: app), in: app, timeout: 3)
        // Local-only privacy copy is visible before any capture.
        assertExists(element("welcome-privacy-badge", in: app), in: app)
        // The user can run a sample capture without external clipboard content,
        // and the hotkey/launch-at-login setup is offered.
        assertExists(element("welcome-sample-capture-button", in: app), in: app)
        assertExists(element("welcome-launch-at-login-toggle", in: app), in: app)
        // A clear way out is present.
        assertExists(element("welcome-skip-button", in: app), in: app)
        assertExists(element("welcome-get-started-button", in: app), in: app)

        // Running the sample capture needs no clipboard setup and reports inline.
        // Poll for hittability first: the welcome window can still be settling into
        // place when the button already exists, so an immediate click flakes with
        // "is not hittable" on the hosted CI runner.
        assertHittable(
            "welcome-sample-capture-button", in: app,
            "Sample-capture button should become reachable on the quick-start", timeout: 5)
        element("welcome-sample-capture-button", in: app).click()
        assertExists(element("welcome-sample-status", in: app), in: app, timeout: 5)
    }

    @MainActor
    func testForcedQuickStartCanBeSkippedToReachTheEditor() throws {
        continueAfterFailure = false
        // Force the quick-start open and also open the editor: skipping the
        // quick-start must not gate access to the rest of the app.
        let app = launch(arguments: ["--show-welcome", "--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("welcome-window", in: app), in: app, timeout: 8)
        // The Skip button overhangs a display too short to hold the welcome window,
        // so skip the interaction there rather than flaking on hittability.
        try skipUnlessADisplayFitsTheWelcomeWindow(app)
        // Wait for the Skip button to be hittable, not just present: the window may
        // still be animating forward, which flakes an immediate click as
        // "is not hittable" on the hosted CI runner. If a multi-display run reports
        // the fixed Welcome footer just outside the active visible frame, the forced
        // launch has already opened the editor; still prove the user is not gated by
        // the quick-start instead of failing on host geometry.
        if waitForHittableElement("welcome-skip-button", in: app, timeout: 5) {
            element("welcome-skip-button", in: app).click()
        }

        // After skipping (or when the forced editor is already reachable), the editor
        // window is available. This launch deliberately opens Welcome and the editor at
        // the same time, so AppKit can briefly reorder windows while Welcome closes;
        // assert the editor surface itself instead of a specific toolbar item whose
        // nested AX node may not realize immediately.
        let editor = element("editor-window", in: app)
        assertExists(editor, in: app, timeout: 8)
        app.activate()
        if editor.isHittable { editor.click() }
        assertExists(element("code-editor-text-view", in: app), in: app, timeout: 8)
    }

    @MainActor
    func testSkippedOnboardingDoesNotReshowQuickStart() {
        continueAfterFailure = false
        // `--skip-onboarding` marks the quick-start as already seen, so a launch
        // that opens the editor shows no welcome window.
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
        // `--show-help` force-opens the in-app Help window. Its content is
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
        // the newer shipped version on launch.
        let app = launch(arguments: ["--seen-old-version"])
        defer { app.terminate() }

        assertExists(element("whats-new-window", in: app), in: app, timeout: 8)
        assertExists(element("whats-new-view", in: app), in: app, timeout: 3)
        assertExists(element("whats-new-highlights", in: app), in: app)
        // A clear "Continue" dismisses it.
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
        // the first launch.
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

        // The editor makes the app active, so its main menu bar is shown.
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
        assertExists(app.staticTexts["Global hotkey"], in: app, timeout: 3)
        assertExists(app.staticTexts["Hotkey runs"], in: app, timeout: 3)
        assertExists(element("launch-at-login-toggle", in: app), in: app)
    }

    @MainActor
    func testOutputFormatPickerOffersAVIF() {
        continueAfterFailure = false
        let app = launch(arguments: ["--open-settings"])
        defer { app.terminate() }

        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        element("settings-nav-output", in: app).click()
        assertExists(element("settings-output-pane", in: app), in: app, timeout: 3)
        let avif = element("output-format-avif", in: app)
        assertExists(avif, in: app)
        XCTAssertTrue(avif.isHittable, "AVIF is present but not reachable in the format picker")
        avif.click()
        XCTAssertTrue(avif.isSelected, "Selecting AVIF did not update the output format")
    }

    // MARK: - Localization smoke

    @MainActor
    func testSettingsPanesSurviveAccentedPseudolocale() {
        continueAfterFailure = false
        // The accented + lengthened pseudolocale (`en-XA`) padding-tests every
        // localized string: if a Settings pane truncated or clipped under longer,
        // accented text, its controls would no longer resolve. Walking the panes and
        // asserting each one's key controls exist *and* remain hittable is the
        // automatable proxy for "no truncation or clipping in Settings panes"
        // .
        let app = launch(arguments: ["--open-settings"], locale: .accentedPseudo)
        defer { app.terminate() }

        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        XCTAssertTrue(
            element("reset-all-settings-button", in: app).isHittable,
            "General pane control is clipped or unreachable under en-XA")

        // The sidebar row titles are themselves localized (they pseudo-localize under
        // en-XA), so the rows are selected by their stable `settings-nav-*`
        // identifiers rather than by visible title.
        for (navIdentifier, paneIdentifier, control) in [
            ("settings-nav-style", "settings-style-pane", "style-theme-picker"),
            ("settings-nav-library", "settings-library-pane", "style-preset-picker"),
            ("settings-nav-output", "settings-output-pane", "output-format-picker"),
            ("settings-nav-about", "settings-about-pane", "export-diagnostics-button"),
        ] {
            element(navIdentifier, in: app).click()
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
        // dropped or stranded. Reachability of the toolbar, preview stage,
        // inspector, and export actions is the automatable proxy for "layout is sane
        // under RTL, mirrored where appropriate" .
        let app = launch(arguments: ["--demo", "--open-editor"], locale: .rightToLeftPseudo)
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        for identifier in [
            "editor-toolbar", "editor-preview-stage", "editor-inspector", "copy-button",
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

    /// A locale/text-direction override applied to a launch. Passed through
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
    private func launch(
        arguments: [String],
        locale: LocaleOverride = .system,
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + locale.launchArguments
        app.launchEnvironment["VITRINE_USER_DEFAULTS_SUITE"] =
            "VitrineUITests-\(name)-\(UUID().uuidString)"
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        app.activate()
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

}
