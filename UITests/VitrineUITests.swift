import AppKit
import ImageIO
import XCTest

final class VitrineUITests: XCTestCase {
    @MainActor
    func testVisualChromeFitsCompactAndDesktopEditors() throws {
        continueAfterFailure = false
        let visible = try XCTUnwrap(NSScreen.main).visibleFrame.size
        try XCTSkipUnless(
            visible.width >= 960 && visible.height >= 600,
            "The primary display cannot hold the 960×600 editor viewport")
        // Appearance never changes geometry, so each size runs in one appearance. Launch at
        // each frame through the Debug-only hook rather than pointer drags at a display edge.
        for (size, dark) in [
            (CGSize(width: 960, height: 600), false),
            (CGSize(width: min(1280, visible.width), height: min(800, visible.height)), true),
        ] {
            // End each cohort before launching the next one. A defer in
            // this loop's outer scope leaves previous app windows alive.
            do {
                let app = launch(
                    arguments: VitrineLaunchArguments.editor + [
                        dark ? "--appearance-dark" : "--appearance-light"
                    ],
                    environment: [
                        "VITRINE_UI_TEST_EDITOR_VIEWPORT": "\(Int(size.width))x\(Int(size.height))"
                    ])
                defer { app.terminate() }
                let resizedWindow = element("editor-window", in: app)
                assertExists(resizedWindow, in: app, timeout: 8)
                XCTAssertEqual(resizedWindow.frame.width, size.width, accuracy: 2)
                XCTAssertEqual(resizedWindow.frame.height, size.height, accuracy: 2)
                // Accessory apps can lose the foreground to another process
                // between launches. Activate and click the editor before
                // checking real pointer reachability.
                app.activate()
                resizedWindow.click()
                let bounds = resizedWindow.frame.insetBy(dx: -1, dy: -1)
                for identifier in ["editor-toolbar", "editor-preview-stage", "editor-inspector"] {
                    // SwiftUI repeats a container identifier on its leaves; the first
                    // match is the container itself, so one frame read covers them.
                    let container = app.descendants(matching: .any)
                        .matching(identifier: identifier).firstMatch
                    assertExists(container, in: app, timeout: 3)
                    XCTAssertTrue(bounds.contains(container.frame), identifier)
                }
                app.activate()
                assertHittable(
                    "copy-button", in: app, "The primary action must remain reachable")
                // XCUIElement screenshots read composited screen pixels;
                // another desktop app can cover this accessory window
                // after the hit test even while the AX frame is correct.
                app.activate()
                let attachment = XCTAttachment(screenshot: resizedWindow.screenshot())
                attachment.name =
                    "chrome-en-\(dark ? "dark" : "light")-\(Int(size.width))x\(Int(size.height))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testPaletteExposesSelectedResultAndKeepsSearchEditable() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(arguments: ["--open-command-palette"])
        defer { app.terminate() }
        let field = element("command-palette-field", in: app)
        assertExists(field, in: app, timeout: 8)
        field.typeText("theme")
        let themes = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "command-palette-command-theme."))
        assertExists(themes.element(boundBy: 1), in: app, timeout: 3)
        let first = themes.element(boundBy: 0)
        let second = themes.element(boundBy: 1)
        XCTAssertTrue(first.wait(for: \.isSelected, toEqual: true, timeout: 3))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(second.wait(for: \.isSelected, toEqual: true, timeout: 3))
        XCTAssertFalse(first.isSelected)
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(first.wait(for: \.isSelected, toEqual: true, timeout: 3))
        // Send typing to the current responder, without clicking the search field again.
        app.typeText(" zzzz")
        assertExists(app.staticTexts["No matching commands"], in: app, timeout: 3)
        for _ in 0..<5 { app.typeKey(.delete, modifierFlags: []) }
        app.typeText(" dracula")
        let result = element("command-palette-command-theme.dracula", in: app)
        assertExists(result, in: app, timeout: 3)
        XCTAssertTrue(result.wait(for: \.isSelected, toEqual: true, timeout: 3))
        // Return runs the selected command and dismisses the palette.
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("command-palette", in: app).waitForNonExistence(timeout: 3))
    }

    #if !VITRINE_DIRECT_DOWNLOAD
        @MainActor
        func testStorePaywallLoadsLocalizedPriceRetriesAndRestoresWithoutAnAccount() {
            continueAfterFailure = false
            let app = launch(
                arguments: VitrineLaunchArguments.settings,
                environment: ["VITRINE_MANAGED_STORE_UI_TEST": "price-retry"])
            defer { app.terminate() }
            assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
            element("settings-nav-brandKit", in: app).click()
            app.buttons["Unlock Vitrine PRO"].click()
            assertExists(element("pro-price-unavailable", in: app), in: app, timeout: 5)
            XCTAssertFalse(element("pro-buy-button", in: app).isEnabled)
            XCTAssertTrue(element("pro-restore-button", in: app).isEnabled)
            element("pro-price-retry", in: app).click()
            let price = app.staticTexts["pro-display-price"]
            assertExists(price, in: app, timeout: 5)
            XCTAssertEqual(
                price.value as? String ?? price.label, "12,34 €",
                "Storefront text must be displayed verbatim")
            XCTAssertTrue(element("pro-buy-button", in: app).isEnabled)
            element("pro-restore-button", in: app).click()
            XCTAssertTrue(element("pro-paywall-sheet", in: app).waitForNonExistence(timeout: 5))
            assertExists(element("settings-brand-kit-controls", in: app), in: app)
        }
    #endif

    /// The unlocked value and paywall routing are unit-tested (`EntitlementsTests`,
    /// `EditorExportSheetTests`); this proves the locked toolbar at both widths.
    @MainActor
    func testExportControlsAnnounceProRequirementsAndKeepAnEscapePath() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        #if VITRINE_DIRECT_DOWNLOAD
            var environment = ["VITRINE_MANAGED_LICENSE_UI_TEST": "activation-success"]
        #else
            var environment = ["VITRINE_MANAGED_STORE_UI_TEST": "price-available"]
        #endif
        for compact in [false, true] {
            if compact { environment["VITRINE_UI_TEST_EDITOR_VIEWPORT"] = "960x600" }
            let app = launch(arguments: VitrineLaunchArguments.editor, environment: environment)
            defer { app.terminate() }
            assertExists(element("editor-window", in: app), in: app, timeout: 8)
            if compact {
                let width = element("editor-window", in: app).frame.width
                XCTAssertLessThanOrEqual(width, 1000, "The compact pass must run compact")
                assertHittable(
                    "editor-actions-menu", in: app, "A compact editor must expose its toolbar menu")
            }
            let sizes = revealToolbarAction(
                "export-sizes-button", from: "editor-actions-menu", in: app)
            let titles = ["Export sizes", "Export carousel"]
            for (index, identifier) in ["export-sizes-button", "export-carousel-button"]
                .enumerated()
            {
                let button = hittableElement(identifier, in: app)
                if button.elementType == .menuItem {
                    XCTAssertEqual(button.title, titles[index] + " — Requires PRO")
                } else {
                    XCTAssertEqual(button.value as? String ?? "", "Requires PRO")
                }
            }
            sizes.click()
            assertExists(element("pro-paywall-sheet", in: app), in: app, timeout: 3)
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(element("pro-paywall-sheet", in: app).waitForNonExistence(timeout: 3))
            XCTAssertTrue(
                revealToolbarAction(
                    "export-sizes-button", from: "editor-actions-menu", in: app
                ).isEnabled)
            app.terminate()
        }
    }

    @MainActor
    func testEditorLaunchesWithPrimaryControls() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(arguments: VitrineLaunchArguments.editor)
        defer { app.terminate() }
        let editor = EditorRobot(testCase: self, app: app)

        assertExists(editor.window, in: app, timeout: 8)
        assertExists(editor.codeTextView, in: app, timeout: 3)
        assertExists(element("language-picker", in: app), in: app)
        assertHittable("format-button", in: app, "Format Code action is not reachable")
        assertExists(element("living-snapshot-menu", in: app), in: app)
        // The editor advertises a drop target for source files / text. A real drag from
        // outside the app is not reliably automatable; FileInputLoaderTests covers loading.
        assertExists(element("editor-drop-target", in: app), in: app)
        // Standard focusable controls; hittability is the proxy for keyboard reachability.
        assertHittable(
            "editor-style-preset-picker", in: app, "Style preset picker is not reachable")
        assertHittable("editor-inspector", in: app, "Inspector is not reachable")
        assertHittable("copy-button", in: app, "Export toolbar copy action is not reachable")

        // Advanced controls start behind the collapsed Output disclosure.
        element("inspector-disclosure-output", in: app).click()
        assertExists(element("editor-destination-preset-picker", in: app), in: app, timeout: 3)
        assertExists(element("inspector-resolution-picker", in: app), in: app)
        assertExists(element("inspector-format-picker", in: app), in: app)

        assertHittable(
            "copy-options-menu", in: app, "The alternate copy formats menu must be reachable")
        element("copy-options-menu", in: app).click()
        assertHittable(
            "copy-markdown-button", in: app,
            "Copy as Markdown must be exposed for source-based snapshots")
        assertExists(element("copy-share-link-button", in: app), in: app, timeout: 3)
        app.typeKey(.escape, modifierFlags: [])

        assertToolbarActionsReachable(
            ["save-button", "share-button", "make-default-button"],
            from: "editor-actions-menu", in: app)
    }

    @MainActor
    func testImageProcessingShowsProgressAndCanCancelOrRemoveItsSource() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(
            arguments: ["--demo-beautify-image"],
            environment: [
                "VITRINE_MANAGED_IMAGE_UI_TEST": "pending",
                "VITRINE_UI_TEST_EDITOR_VIEWPORT": "960x600",
            ])
        defer { app.terminate() }
        let copy = element("copy-image-text-button", in: app)
        let redact = element("redact-image-secrets-button", in: app)
        let status = element("image-processing-status", in: app)
        let cancel = element("cancel-image-processing-button", in: app)
        assertExists(copy, in: app, timeout: 8)
        let window = element("editor-window", in: app)
        // The Debug launch hook requests a real compact AppKit frame; assert the
        // resulting size so the test fails if the editor's minimum grows too large.
        XCTAssertLessThanOrEqual(window.frame.width, 980)
        XCTAssertLessThanOrEqual(window.frame.height, 620)
        copy.click()
        assertExists(status, in: app, timeout: 3)
        XCTAssertEqual(status.label, "Recognizing text…")
        XCTAssertFalse(copy.isEnabled)
        XCTAssertFalse(redact.isEnabled)
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(window.frame.contains(cancel.frame))
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "image-processing"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        cancel.click()
        XCTAssertTrue(status.waitForNonExistence(timeout: 3))
        XCTAssertTrue(copy.isEnabled)
        XCTAssertTrue(redact.isEnabled)

        // Starting a different operation immediately must not let the cancelled
        // task clear its progress. Removal cancels the new job and restores code mode.
        redact.click()
        assertExists(status, in: app, timeout: 3)
        XCTAssertEqual(status.label, "Redacting secrets…")
        element("remove-image-button", in: app).click()
        assertExists(element("code-editor-text-view", in: app), in: app, timeout: 3)
        XCTAssertTrue(status.waitForNonExistence(timeout: 3))
        XCTAssertFalse(copy.exists)
    }

    // MARK: - Multi-window editing and restoration

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
    func testEditorShowsToolbarInspectorAndPreviewStage() {
        continueAfterFailure = false
        let app = launch(
            arguments: ["--skip-onboarding", "--demo-large-document", "--open-editor"])
        defer { app.terminate() }

        let editor = element("editor-window", in: app)
        assertExists(editor, in: app, timeout: 8)

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

        // The same launch pins the large-document mode without another app launch.
        assertExists(element("large-document-highlight-notice", in: app), in: app, timeout: 5)
        assertExists(element("code-editor-text-view", in: app), in: app, timeout: 3)
        assertExists(element("format-button", in: app), in: app)

        // Real evidence for the intentionally visible fallback. This attachment is not part of
        // the strict marketing screenshot tour, so adding the reliability state does not churn
        // the tracked 53-state contract.
        let attachment = XCTAttachment(screenshot: editor.screenshot())
        attachment.name = "large-document-mode"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testEditorShowsAnnotationToolbar() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(arguments: VitrineLaunchArguments.editor)
        defer { app.terminate() }

        assertExists(element("editor-toolbar", in: app), in: app, timeout: 8)

        // The annotation tool palette lives in the title bar. At compact widths it
        // becomes a menu, but every tool remains addressable.
        let toolIdentifiers = [
            "select", "arrow", "curvedArrow", "rectangle", "highlighter", "counter", "sticker",
            "spotlight", "measure",
        ].map { "annotation-tool-\($0)" }
        assertToolbarActionsReachable(
            toolIdentifiers, from: "annotation-tool-picker", in: app)

        // Activating a draw tool reveals its options — the color swatch and the size
        // slider — which the Select pointer hides.
        revealToolbarAction(
            "annotation-tool-arrow", from: "annotation-tool-picker", in: app
        ).click()
        assertExists(element("annotation-color-swatch", in: app), in: app, timeout: 3)
        assertExists(element("annotation-thickness-slider", in: app), in: app)

        // The sticker tool swaps the color swatch (an emoji has its own colors) for the
        // sticker-glyph swatch, and keeps the size slider.
        revealToolbarAction(
            "annotation-tool-sticker", from: "annotation-tool-picker", in: app
        ).click()
        assertExists(element("annotation-sticker-swatch", in: app), in: app, timeout: 3)
        assertExists(element("annotation-thickness-slider", in: app), in: app)
        XCTAssertFalse(
            element("annotation-color-swatch", in: app).exists,
            "The sticker tool must hide the color swatch — an emoji has its own colors")

        revealToolbarAction(
            "annotation-tool-select", from: "annotation-tool-picker", in: app
        ).click()

        // Selection-only actions exist but stay disabled until a mark is selected; the
        // same gate keeps their shortcuts from firing while code has focus.
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
            XCTAssertTrue(
                element(identifier, in: app).waitForExistence(timeout: 3),
                "\(identifier) did not materialize after opening the compact mark-actions menu")
            let matches = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", identifier))
                .allElementsBoundByIndex
            XCTAssertFalse(matches.isEmpty, "\(identifier) must exist in the mark toolbar")
            XCTAssertFalse(
                matches.contains { $0.isEnabled },
                "\(identifier) must be disabled with no mark selected")
        }
    }

    /// Real pointer and keyboard routing complements the pure canvas geometry tests.
    /// A fixed-size destination scales the same overlay without a second zoom transform.
    @MainActor
    func testAnnotationDrawingSelectionResizeAndKeyboardNudge() throws {
        continueAfterFailure = false
        let visible = try XCTUnwrap(NSScreen.main).visibleFrame.size
        try XCTSkipUnless(
            visible.width >= 1024 && visible.height >= 680,
            "The primary display cannot hold the 1024×680 editor viewport")
        // A 15-point drag at XCTest's .slow (250 points/s) lasts only 60 ms.
        // Use deliberate pointer motion rather than a near-click on hosted displays.
        let dragVelocity = XCUIGestureVelocity(rawValue: 40)
        // A 1024-point window exercises the compact toolbar on any display.
        let app = launch(
            arguments: VitrineLaunchArguments.editor,
            environment: ["VITRINE_UI_TEST_EDITOR_VIEWPORT": "1024x680"])
        defer { app.terminate() }
        let window = element("editor-window", in: app)
        assertExists(window, in: app, timeout: 8)
        XCTAssertEqual(window.frame.width, 1024, accuracy: 2)
        let delete = app.buttons["Delete annotation"]
        for fixedCanvas in [false, true] {
            if fixedCanvas {
                element("inspector-disclosure-output", in: app).click()
                let destinations = element("editor-destination-preset-picker", in: app)
                assertExists(destinations, in: app, timeout: 3)
                destinations.buttons["OG"].click()
            }
            revealToolbarAction(
                "annotation-tool-arrow", from: "annotation-tool-picker", in: app
            ).click()
            // Target the synthetic demo's rendered code, not the status capsule.
            let stage = element("editor-preview-stage", in: app).staticTexts.matching(
                NSPredicate(format: "value BEGINSWITH %@", "import SwiftUI")
            ).firstMatch
            assertExists(stage, in: app, timeout: 3)
            let center = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            center.click()
            XCTAssertFalse(delete.exists, "A click must not create a zero-size arrow")
            let start = center.withOffset(CGVector(dx: -30, dy: -20))
            let end = center.withOffset(CGVector(dx: 30, dy: 20))
            start.press(
                forDuration: 0.1, thenDragTo: end, withVelocity: dragVelocity,
                thenHoldForDuration: 0.15)
            assertExists(delete, in: app)
            revealToolbarAction(
                "annotation-tool-select", from: "annotation-tool-picker", in: app
            ).click()
            center.withOffset(CGVector(dx: -30, dy: 35)).click()
            XCTAssertTrue(delete.waitForNonExistence(timeout: 3), "Empty canvas clears selection")
            center.click()
            assertExists(delete, in: app)

            let beforeMove = delete.frame
            let movedCenter = center.withOffset(CGVector(dx: 15, dy: 0))
            center.press(
                forDuration: 0.1, thenDragTo: movedCenter, withVelocity: dragVelocity,
                thenHoldForDuration: 0.15)
            XCTAssertEqual(delete.frame.minX - beforeMove.minX, 15, accuracy: 3)
            let beforeResize = delete.frame
            let movedEnd = end.withOffset(CGVector(dx: 15, dy: 0))
            movedEnd.press(
                forDuration: 0.1, thenDragTo: movedEnd.withOffset(CGVector(dx: 15, dy: 15)),
                withVelocity: dragVelocity, thenHoldForDuration: 0.15)
            XCTAssertEqual(delete.frame.minX - beforeResize.minX, 15, accuracy: 3)
            let beforeKey = delete.frame
            app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [.shift])
            XCTAssertGreaterThan(
                delete.frame.minX, beforeKey.minX, "The focused mark receives arrow keys")
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = fixedCanvas ? "annotation-fixed-canvas" : "annotation-natural-canvas"
            attachment.lifetime = .keepAlways
            add(attachment)
            delete.click()
            XCTAssertTrue(delete.waitForNonExistence(timeout: 3))
            if fixedCanvas { continue }

            // Text callouts: a drag moves, a click selects, a double click edits.
            revealToolbarAction(
                "annotation-tool-text", from: "annotation-tool-picker", in: app
            ).click()
            center.click()
            let field = app.textFields.matching(identifier: "annotation-text-field").firstMatch
            assertExists(field, in: app)
            // A new callout owns keyboard focus: type without clicking the field.
            field.typeText("Callout\r")
            XCTAssertTrue(field.waitForNonExistence(timeout: 3))
            revealToolbarAction(
                "annotation-tool-select", from: "annotation-tool-picker", in: app
            ).click()
            center.click()
            assertExists(delete, in: app)
            let beforeTextMove = delete.frame
            let textTarget = center.withOffset(CGVector(dx: 15, dy: 0))
            center.press(
                forDuration: 0.1, thenDragTo: textTarget, withVelocity: dragVelocity,
                thenHoldForDuration: 0.15)
            XCTAssertEqual(delete.frame.minX - beforeTextMove.minX, 15, accuracy: 3)
            XCTAssertFalse(field.exists, "A move must not reopen the text field")
            textTarget.doubleClick()
            assertExists(field, in: app)
            // Clear the canvas so the fixed-canvas pass starts from no marks.
            field.typeText("\r")
            XCTAssertTrue(field.waitForNonExistence(timeout: 3))
            textTarget.click()
            assertExists(delete, in: app, timeout: 3)
            delete.click()
            XCTAssertTrue(delete.waitForNonExistence(timeout: 3))
        }
    }

    /// A callout placed after choosing the Text tool by shortcut takes keyboard focus.
    @MainActor
    func testTextCalloutFromShortcutTakesKeyboardFocus() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let app = launch(arguments: VitrineLaunchArguments.editor)
        defer { app.terminate() }
        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        app.typeKey("5", modifierFlags: .command)
        let stage = element("editor-preview-stage", in: app).staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "import SwiftUI")
        ).firstMatch
        assertExists(stage, in: app, timeout: 3)
        stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let field = app.textFields.matching(identifier: "annotation-text-field").firstMatch
        assertExists(field, in: app, timeout: 3)
        field.typeText("Callout")
        XCTAssertEqual(field.value as? String, "Callout")
    }

    /// Tool shortcuts are ⌘-digit, so plain letters always type in the code editor and
    /// never switch tools, while ⌘2 (Arrow) still selects its tool with code focused.
    @MainActor
    func testAnnotationShortcutsDoNotHijackCodeTyping() throws {
        continueAfterFailure = false
        // An empty editor keeps the typed text exact.
        let app = launch(arguments: VitrineLaunchArguments.emptyEditor)
        defer { app.terminate() }

        let editor = element("code-editor-text-view", in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        editor.click()
        editor.typeText("abc")

        let value = (editor.value as? String) ?? ""
        XCTAssertTrue(
            value.contains("abc"),
            "Tool-shortcut letters typed in the code editor must reach the text. Got: '\(value)'")
        let swatch = element("annotation-color-swatch", in: app)
        XCTAssertFalse(swatch.exists, "Typing in the code editor must not activate a draw tool")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(
            swatch.waitForExistence(timeout: 3),
            "⌘2 should select the Arrow tool and reveal its color swatch")
    }

    @MainActor
    func testStylePaneShowsDestinationPresetPicker() {
        continueAfterFailure = false
        let app = launch(arguments: VitrineLaunchArguments.settings)
        defer { app.terminate() }
        let settings = SettingsRobot(testCase: self, app: app)
        assertExists(settings.generalPane, in: app, timeout: 8)
        _ = settings.open(navigation: "settings-nav-style", pane: "settings-style-pane")
        assertExists(element("destination-preset-picker", in: app), in: app, timeout: 3)
        let scope = element("settings-style-scope", in: app)
        assertExists(scope, in: app)
        XCTAssertEqual(
            (scope.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? scope.label,
            "Defaults for new windows and captures. Open editors keep their own style.")
        for id in ["twitter", "linkedin", "opengraph", "keynote", "docs", "transparent-slide"] {
            assertHittable(
                "settings-destination-\(id)", in: app, "Every destination should be reachable")
        }
        let slide = element("settings-destination-transparent-slide", in: app)
        slide.click()
        XCTAssertTrue(slide.isSelected)
        _ = settings.open(navigation: "settings-nav-general", pane: "settings-general-pane")
        _ = settings.open(navigation: "settings-nav-style", pane: "settings-style-pane")
        XCTAssertTrue(element("settings-destination-transparent-slide", in: app).isSelected)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "style-defaults"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Deletion, default replacement and reload are unit-tested in `LibraryDeletionTests`;
    /// this proves the named confirmations keep Cancel as the safe default.
    @MainActor
    func testLibraryDeletionRequiresNamedConfirmation() {
        continueAfterFailure = false
        let app = launch(arguments: VitrineLaunchArguments.settings)
        defer { app.terminate() }
        let settings = SettingsRobot(testCase: self, app: app)
        assertExists(settings.generalPane, in: app, timeout: 8)
        settings.open(navigation: "settings-nav-library", pane: "settings-library-pane")
        assertExists(element("workspace-recipe-picker", in: app), in: app, timeout: 3)
        assertHittable(
            "add-workspace-recipe-button", in: app,
            "The workspace association action should be reachable")
        assertHittable(
            "export-workspace-recipe-button", in: app,
            "The portable recipe export action should be reachable")

        element("save-style-preset-button", in: app).click()
        let presetName = app.windows.firstMatch.sheets.textFields.firstMatch
        assertExists(presetName, in: app, timeout: 3)
        presetName.click()
        presetName.typeKey("a", modifierFlags: .command)
        presetName.typeText("Deletion example")
        app.windows.firstMatch.sheets.buttons["Save"].click()
        element("apply-style-preset-button", in: app).click()
        element("delete-style-preset-button", in: app).click()
        let presetSheet = app.windows.firstMatch.sheets.firstMatch
        XCTAssertTrue(presetSheet.waitForExistence(timeout: 3))
        XCTAssertTrue(
            presetSheet.staticTexts.matching(
                NSPredicate(
                    format: "value CONTAINS %@ OR label CONTAINS %@", "Deletion example",
                    "Deletion example")
            ).firstMatch.exists)
        // Return is deliberately the safe choice, not implicit deletion.
        app.typeKey(.return, modifierFlags: [])
        let presetPicker = element("style-preset-picker", in: app)
        XCTAssertEqual(presetPicker.value as? String, "Deletion example")
        element("delete-style-preset-button", in: app).click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(presetPicker.value as? String, "Deletion example")
        element("delete-style-preset-button", in: app).click()
        app.windows.firstMatch.sheets.buttons["Delete Preset"].click()
        XCTAssertFalse(element("delete-style-preset-button", in: app).isEnabled)
        presetPicker.click()
        XCTAssertTrue(presetPicker.menuItems.firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(presetPicker.menuItems["Deletion example"].exists)
        app.typeKey(.escape, modifierFlags: [])

        element("new-custom-theme-button", in: app).click()
        let themeName = element("custom-theme-name-field", in: app)
        assertExists(themeName, in: app, timeout: 3)
        themeName.click()
        themeName.typeKey("a", modifierFlags: .command)
        themeName.typeText("Theme deletion example")
        app.windows.firstMatch.sheets.buttons["Save"].click()
        element("delete-custom-theme-button", in: app).click()
        let themeSheet = app.windows.firstMatch.sheets.firstMatch
        XCTAssertTrue(themeSheet.waitForExistence(timeout: 3))
        XCTAssertTrue(
            themeSheet.staticTexts.matching(
                NSPredicate(
                    format: "value CONTAINS %@ OR label CONTAINS %@", "Theme deletion example",
                    "Theme deletion example")
            ).firstMatch.exists)
        themeSheet.buttons["Cancel"].click()
        XCTAssertEqual(
            element("custom-theme-picker", in: app).value as? String, "Theme deletion example")
        element("delete-custom-theme-button", in: app).click()
        app.windows.firstMatch.sheets.buttons["Delete Theme"].click()
        XCTAssertTrue(element("custom-theme-picker", in: app).waitForNonExistence(timeout: 3))
        settings.open(navigation: "settings-nav-style", pane: "settings-style-pane")
        XCTAssertTrue(app.buttons["One Dark"].isSelected)
    }

    @MainActor
    func testBrandKitPaneAndFreePlacementDragHandle() {
        continueAfterFailure = false
        let app = launch(
            arguments: ["--demo-brand-kit-free", "--open-settings"],
            environment: ["VITRINE_PRO_UNLOCK": "1"])
        defer { app.terminate() }

        // Brand Kit (PRO) is its own sidebar pane, but free placement is dragged on the
        // Style pane's live preview, which must expose a real drag target.
        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        element("settings-nav-brandKit", in: app).click()
        assertExists(element("settings-brandkit-pane", in: app), in: app, timeout: 3)
        assertExists(element("settings-brand-kit-controls", in: app), in: app, timeout: 3)
        element("settings-nav-style", in: app).click()
        assertExists(element("settings-style-pane", in: app), in: app, timeout: 3)
        assertHittable(
            "brand-kit-free-drag-handle", in: app,
            "Free Brand Kit placement should expose a reachable preview drag handle")
    }

    /// One license round trip: activation dismisses the paywall and unlocks Brand Kit,
    /// then deactivation relocks it in the same running app without a network. The
    /// partial-activation failure is unit-tested in `EntitlementsTests`.
    @MainActor
    func testLicenseActivationAndDeactivationUpdateProInPlace() {
        continueAfterFailure = false
        let app = launch(
            arguments: VitrineLaunchArguments.settings,
            environment: ["VITRINE_MANAGED_LICENSE_UI_TEST": "activation-success"])
        defer { app.terminate() }
        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        element("settings-nav-brandKit", in: app).click()
        let unlock = app.buttons["Unlock Vitrine PRO"]
        assertExists(unlock, in: app, timeout: 3)
        unlock.click()
        let field = app.secureTextFields["pro-license-field"]
        assertExists(field, in: app, timeout: 3)
        field.click()
        field.typeText("vitrine-ui-test-key")
        element("pro-activate-button", in: app).click()
        XCTAssertTrue(element("pro-paywall-sheet", in: app).waitForNonExistence(timeout: 3))
        assertExists(element("settings-brand-kit-controls", in: app), in: app, timeout: 3)

        element("settings-nav-about", in: app).click()
        let aboutPane = element("settings-about-pane", in: app)
        assertExists(aboutPane, in: app, timeout: 3)
        let licenseSection = element("license-management-section", in: app)
        assertExists(licenseSection, in: app, timeout: 3)
        assertExists(
            app.staticTexts["Vitrine PRO is active on this Mac."], in: app, timeout: 3)
        assertHittable(
            "deactivate-license-button",
            in: app,
            "An active managed license must expose its deactivation action")
        let activeAttachment = XCTAttachment(screenshot: aboutPane.screenshot())
        activeAttachment.name = "managed-license-active"
        activeAttachment.lifetime = .keepAlways
        add(activeAttachment)

        element("deactivate-license-button", in: app).click()
        // macOS mirrors confirmation actions into the Touch Bar accessibility tree.
        // Scope to the visible sheet so automation never chooses that non-clickable duplicate.
        let confirm = app.sheets.buttons["Deactivate This Mac"].firstMatch
        assertExists(confirm, in: app, timeout: 3)
        confirm.click()

        let success = app.staticTexts["Vitrine PRO was deactivated on this Mac."].firstMatch
        assertExists(success, in: app, timeout: 5)
        let resultSheet = app.sheets.firstMatch
        assertExists(resultSheet, in: app, timeout: 3)
        let resultAttachment = XCTAttachment(screenshot: resultSheet.screenshot())
        resultAttachment.name = "managed-license-deactivated"
        resultAttachment.lifetime = .keepAlways
        add(resultAttachment)

        let acknowledge = app.sheets.buttons["OK"].firstMatch
        assertExists(acknowledge, in: app, timeout: 3)
        acknowledge.click()
        XCTAssertTrue(
            licenseSection.waitForNonExistence(timeout: 3),
            "A deactivated managed license must disappear from About")

        element("settings-nav-brandKit", in: app).click()
        let brandKitPane = element("settings-brandkit-pane", in: app)
        assertExists(brandKitPane, in: app, timeout: 3)
        assertExists(element("settings-brand-kit-upsell", in: app), in: app, timeout: 3)
        XCTAssertTrue(
            element("settings-brand-kit-controls", in: app).waitForNonExistence(timeout: 2),
            "Deactivation must re-lock Brand Kit in the same running app")
        let relockedAttachment = XCTAttachment(screenshot: brandKitPane.screenshot())
        relockedAttachment.name = "managed-license-brand-kit-relocked"
        relockedAttachment.lifetime = .keepAlways
        add(relockedAttachment)
    }

    @MainActor
    func testGeneralAndInputPanesExposeTheirDefaults() {
        continueAfterFailure = false
        let app = launch(arguments: VitrineLaunchArguments.settings)
        defer { app.terminate() }

        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        assertExists(app.staticTexts["Global hotkey"], in: app, timeout: 3)
        assertExists(app.staticTexts["Hotkey runs"], in: app, timeout: 3)
        assertExists(element("launch-at-login-toggle", in: app), in: app)
        // The Input pane carries the editor's tidy-on-paste switch and the opt-in
        // loopback capture, which must start off.
        element("settings-nav-input", in: app).click()
        assertExists(element("settings-input-pane", in: app), in: app, timeout: 3)
        assertExists(element("reindent-on-paste-toggle", in: app), in: app, timeout: 3)
        let loopback = element("web-allow-loopback-toggle", in: app)
        assertExists(loopback, in: app, timeout: 3)
        XCTAssertEqual(loopback.value as? Int, 0, "Loopback capture must default to off")
    }

    /// Keyboard focus and arrow keys are covered with real AppKit events in
    /// `SegmentedPickerFocusTests`; this checks the selection semantics and the
    /// metadata controls behind the "Lines & header" segment.
    @MainActor
    func testStylePaneExposesAccessibleMetadataControls() {
        continueAfterFailure = false
        let app = launch(arguments: VitrineLaunchArguments.settings)
        defer { app.terminate() }

        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        element("settings-nav-style", in: app).click()
        assertExists(element("settings-style-pane", in: app), in: app, timeout: 3)
        let appearance = element("style-subtab-appearance", in: app)
        let lines = element("style-subtab-lines", in: app)
        let background = element("style-subtab-background", in: app)
        assertExists(appearance, in: app, timeout: 3)
        lines.click()
        XCTAssertTrue(lines.wait(for: \.isSelected, toEqual: true, timeout: 3))
        XCTAssertFalse(appearance.isSelected)
        assertExists(element("metadata-filename-field", in: app), in: app, timeout: 3)
        assertExists(element("metadata-title-field", in: app), in: app)
        assertExists(element("metadata-caption-field", in: app), in: app)
        assertExists(element("metadata-language-badge-toggle", in: app), in: app)
        background.click()
        XCTAssertTrue(background.wait(for: \.isSelected, toEqual: true, timeout: 3))
        XCTAssertFalse(lines.isSelected)
        appearance.click()
        XCTAssertTrue(appearance.wait(for: \.isSelected, toEqual: true, timeout: 3))
    }

    // MARK: - Web Snapshot

    @MainActor
    func testWebSignInAffordanceRequiresExplicitSessionOptIn() {
        continueAfterFailure = false
        let app = launch(arguments: VitrineLaunchArguments.webSnapshot)
        defer { app.terminate() }

        assertExists(element("web-snapshot-window", in: app), in: app, timeout: 8)
        let urlField = app.textFields["web-snapshot-url-field"]
        assertExists(urlField, in: app, timeout: 3)
        urlField.click()
        // Entering a URL must not load it. This test never captures or opens the
        // sign-in window, so it needs neither a website nor credentials.
        urlField.typeText("https://example.com")

        let unavailable = element("web-snapshot-url-unavailable-note", in: app)
        let hint = element("web-snapshot-sign-in-hint", in: app)
        let signIn = element("web-snapshot-sign-in-button", in: app)
        let requiresDirect =
            ProcessInfo.processInfo.environment["VITRINE_REQUIRE_DIRECT_WEB_SESSION"] == "1"
        if !requiresDirect {
            // The ordinary UI suite uses App Store-compatible entitlements. It must
            // not offer sign-in merely because the Debug binary was compiled with
            // VITRINE_DIRECT_DOWNLOAD; runtime capability is the signed entitlement.
            assertExists(unavailable, in: app, timeout: 3)
            XCTAssertFalse(hint.exists)
            XCTAssertFalse(signIn.exists)
            return
        }

        XCTAssertFalse(unavailable.exists, "The signed Direct lane lost network capability")
        assertExists(hint, in: app, timeout: 3)
        XCTAssertFalse(signIn.exists, "The default-off session must not offer sign-in")

        hittableElement("web-advanced-disclosure", in: app).click()
        let toggle = element("web-logged-in-session-toggle", in: app)
        assertExists(toggle, in: app, timeout: 3)
        XCTAssertEqual(toggle.value as? Int, 0, "Persistent sessions must default to off")

        toggle.click()
        assertExists(signIn, in: app, timeout: 3)
        XCTAssertTrue(signIn.label.contains("example.com"))
        XCTAssertFalse(hint.exists)

        toggle.click()
        assertExists(hint, in: app, timeout: 3)
        XCTAssertFalse(signIn.exists, "Turning off persistence must withdraw sign-in")
    }

    @MainActor
    func testWebSnapshotRendersAndCopiesMultipleLocalHTMLViewports() throws {
        continueAfterFailure = false
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let app = launch(arguments: VitrineLaunchArguments.deterministicWebSnapshot)
        defer {
            app.terminate()
            pasteboard.clearContents()
        }
        let web = WebSnapshotRobot(testCase: self, app: app)

        let window = web.window
        assertExists(window, in: app, timeout: 8)
        assertExists(web.inspector, in: app, timeout: 3)
        assertExists(web.previewStage, in: app, timeout: 3)

        let htmlMode = web.htmlMode
        assertExists(htmlMode, in: app, timeout: 3)
        htmlMode.click()

        // SwiftUI exposes both the placeholder StaticText and the editable TextView
        // with this identifier. Resolve the typed control so actions never face an
        // ambiguous any-element query.
        let editor = web.htmlEditor
        assertExists(editor, in: app, timeout: 3)
        editor.click()
        let html = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width">
            <style>
            *{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;
            background:#0b1020;color:#f8fafc;font-family:-apple-system}main{text-align:center;
            padding:48px}h1{margin:0 0 12px;font-size:64px}p{margin:0;color:#a7f3d0;font-size:24px}
            @media(max-width:600px){h1{font-size:38px}p{font-size:18px}}
            </style></head><body><main><h1>Vitrine Web Journey</h1><p>Rendered locally.</p>
            </main></body></html>
            """
        XCTAssertTrue(pasteboard.setString(html, forType: .string))
        editor.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(
            (editor.value as? String)?.contains("Vitrine Web Journey") == true,
            "The local HTML fixture must reach the editable source field")

        let social = web.viewport("openGraph")
        let desktop = web.viewport("desktop")
        let mobile = web.viewport("mobile")
        for chip in [social, desktop, mobile] {
            assertExists(chip, in: app, timeout: 3)
        }
        XCTAssertTrue(social.isSelected, "The default Social viewport must remain selected")
        desktop.click()
        mobile.click()
        XCTAssertTrue(desktop.isSelected, "Desktop must join the capture set")
        XCTAssertTrue(mobile.isSelected, "Mobile must join the capture set")

        assertHittable(
            "web-snapshot-capture-button", in: app,
            "Local HTML should enable the Web Snapshot render action")
        web.captureButton.click()

        let results = web.results
        assertExists(results, in: app, timeout: 20)
        for identifier in [
            "web-snapshot-result-board", "web-snapshot-result-openGraph",
            "web-snapshot-result-desktop", "web-snapshot-result-mobile",
        ] {
            assertHittable(
                identifier, in: app,
                "A successful multi-viewport render must expose result \(identifier)",
                timeout: 5)
        }
        XCTAssertTrue(
            element("web-snapshot-result-board", in: app).isSelected,
            "The responsive board must be the default multi-viewport result")

        for identifier in [
            "web-snapshot-export-all-button", "web-snapshot-save-button",
            "web-snapshot-share-button", "web-snapshot-copy-button",
        ] {
            assertHittable(
                identifier, in: app,
                "Rendered Web Snapshot action \(identifier) must be enabled",
                timeout: 5)
        }

        let mobileResult = web.result("mobile")
        mobileResult.click()
        let selectedDeadline = Date().addingTimeInterval(3)
        while !mobileResult.isSelected, Date() < selectedDeadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(mobileResult.isSelected, "Selecting Mobile must update the export target")

        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "web-snapshot-multi-viewport-render"
        attachment.lifetime = .keepAlways
        add(attachment)

        web.exportAction("copy").click()
        assertExists(element("capture-hud", in: app), in: app, timeout: 3)

        let copyDeadline = Date().addingTimeInterval(6)
        var copiedImage: NSBitmapImageRep?
        repeat {
            if let data = pasteboard.data(forType: .png) {
                copiedImage = NSBitmapImageRep(data: data)
            }
            if copiedImage != nil { break }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < copyDeadline

        let copied = try XCTUnwrap(copiedImage, "Copy image did not place a PNG on the pasteboard")
        XCTAssertEqual(copied.pixelsWide, 780)
        XCTAssertEqual(copied.pixelsHigh, 1688)
    }

    // MARK: - Social Card

    @MainActor
    func testSocialCardEditsTemplateAndCopiesRenderedPNG() throws {
        continueAfterFailure = false
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let app = launch(arguments: ["--skip-onboarding", "--open-social-card"])
        defer {
            app.terminate()
            pasteboard.clearContents()
        }

        let window = element("social-card-window", in: app)
        assertExists(window, in: app, timeout: 8)
        assertExists(element("social-card-inspector", in: app), in: app, timeout: 3)
        assertExists(element("social-card-preview-stage", in: app), in: app, timeout: 3)

        let copyButton = app.buttons["social-card-copy-button"]
        let saveButton = app.buttons["social-card-save-button"]
        let shareButton = app.buttons["social-card-share-button"]
        for button in [copyButton, saveButton, shareButton] {
            assertExists(button, in: app, timeout: 3)
            XCTAssertFalse(button.isEnabled, "An empty card must not enable image export")
        }

        let title = app.textFields["social-card-title-field"]
        let subtitle = app.textFields["social-card-subtitle-field"]
        assertExists(title, in: app, timeout: 3)
        assertExists(subtitle, in: app, timeout: 3)
        title.click()
        title.typeText("Ship reliable macOS visuals")
        subtitle.click()
        subtitle.typeText("Local, deterministic, and ready to share")

        // The shared inspector code field exposes a real AppKit TextView. Paste the
        // multiline fixture in one operation so keyboard-layout differences cannot
        // alter braces, punctuation, or indentation under automation.
        let excerpt = app.textViews["social-card-excerpt-editor"]
        assertExists(excerpt, in: app, timeout: 3)
        let code = """
            struct ReleaseGate {
                let platform = "macOS"
                let testsAreGreen = true
            }
            """
        XCTAssertTrue(pasteboard.setString(code, forType: .string))
        excerpt.click()
        excerpt.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(
            (excerpt.value as? String)?.contains("ReleaseGate") == true,
            "The code fixture must reach the Social Card excerpt editor")

        let standard = app.buttons["social-card-template-standard"]
        let codeFocus = app.buttons["social-card-template-codeFocus"]
        assertExists(standard, in: app, timeout: 3)
        assertExists(codeFocus, in: app, timeout: 3)
        XCTAssertTrue(standard.isSelected, "A fresh Social Card must start on Standard")
        codeFocus.click()
        XCTAssertTrue(codeFocus.isSelected, "Selecting Code focus must update the working card")

        for identifier in [
            "social-card-copy-button", "social-card-save-button", "social-card-share-button",
        ] {
            assertHittable(
                identifier, in: app,
                "A renderable Social Card must enable action \(identifier)", timeout: 5)
        }

        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "social-card-code-focus-render"
        attachment.lifetime = .keepAlways
        add(attachment)

        copyButton.click()
        assertExists(element("capture-hud", in: app), in: app, timeout: 3)

        let copyDeadline = Date().addingTimeInterval(6)
        var copiedImage: NSBitmapImageRep?
        repeat {
            if let data = pasteboard.data(forType: .png) {
                copiedImage = NSBitmapImageRep(data: data)
            }
            if copiedImage != nil { break }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < copyDeadline

        let copied = try XCTUnwrap(copiedImage, "Copy card did not place a PNG on the pasteboard")
        XCTAssertEqual(copied.pixelsWide, 2400)
        XCTAssertEqual(copied.pixelsHigh, 1260)
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

        menuBar.menuBarItems["Help"].click()
        let helpMenu = menuBar.menuBarItems["Help"].menus.firstMatch
        XCTAssertTrue(helpMenu.waitForExistence(timeout: 3))
        for title in ["Vitrine Help", "What's New"] {
            XCTAssertTrue(
                helpMenu.menuItems[title].exists, "Missing Help-menu command: \(title)")
        }
        menuBar.menuBarItems["Help"].click()
    }

    @MainActor
    func testRecentsCopiesSourceAndRendersWithDestinationPreset() throws {
        continueAfterFailure = false
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("sentinel", forType: .string))

        let app = launch(arguments: VitrineLaunchArguments.populatedRecent)
        defer {
            app.terminate()
            pasteboard.clearContents()
        }

        assertExists(element("recents-card", in: app), in: app, timeout: 8)
        assertHittable(
            "recents-preset-picker", in: app,
            "A recent capture should expose its actions menu")
        element("recents-preset-picker", in: app).click()
        chooseMenuItem("Copy Source", in: app)

        let sourceDeadline = Date().addingTimeInterval(3)
        while pasteboard.string(forType: .string) == "sentinel", Date() < sourceDeadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        let copied = pasteboard.string(forType: .string)
        XCTAssertTrue(copied?.contains("struct DestinationCard: View") == true)
        XCTAssertTrue(copied?.contains("Text(title)") == true)
        XCTAssertNil(pasteboard.data(forType: .png))

        element("recents-preset-picker", in: app).click()
        chooseMenuItem("OpenGraph 1200×630", in: app)

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
    func testRecentsCreatesAnEditableComparisonBoard() throws {
        continueAfterFailure = false
        try skipUnlessADisplayFitsTheEditor()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let app = launch(
            arguments: VitrineLaunchArguments.recents,
            environment: ["VITRINE_RECENTS_TEST_MAX_WIDTH": "560"])
        defer {
            app.terminate()
            pasteboard.clearContents()
        }

        let cards = app.descendants(matching: .any).matching(identifier: "recents-card")
        XCTAssertEqual(cards.count, 3)
        assertHittable(
            "recents-compare-button", in: app,
            "Recents should expose the explicit comparison selection mode")
        let search = element("recents-search-field", in: app)
        search.click()
        search.typeText("Rust")
        hittableElement("recents-compare-button", in: app).click()
        XCTAssertEqual(search.value as? String, "Rust")
        XCTAssertFalse(search.isEnabled)
        element("recents-compare-cancel", in: app).click()
        XCTAssertEqual(search.value as? String, "Rust")
        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        hittableElement("recents-compare-button", in: app).click()

        cards.element(boundBy: 0).click()
        cards.element(boundBy: 1).click()
        XCTAssertEqual(
            app.descendants(matching: .any).matching(
                identifier: "recents-comparison-selection"
            ).count, 2)

        assertHittable(
            "recents-create-comparison-button", in: app,
            "Two selected captures should enable board creation")
        element("recents-create-comparison-button", in: app).click()

        assertExists(element("comparison-board-window", in: app), in: app, timeout: 8)
        assertExists(element("comparison-board-preview-stage", in: app), in: app, timeout: 5)
        assertExists(element("comparison-board-inspector", in: app), in: app)
        assertHittable(
            "comparison-board-copy-button", in: app,
            "A valid board should expose its primary copy action")

        let firstLabel = element("comparison-board-label-0", in: app)
        assertExists(firstLabel, in: app)
        firstLabel.click()
        firstLabel.typeKey("a", modifierFlags: .command)
        firstLabel.typeText("Original")
        XCTAssertEqual(firstLabel.value as? String, "Original")

        element("comparison-board-copy-button", in: app).click()
        let copyDeadline = Date().addingTimeInterval(6)
        var copied: NSBitmapImageRep?
        repeat {
            if let data = pasteboard.data(forType: .png) {
                copied = NSBitmapImageRep(data: data)
            }
            if copied != nil { break }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < copyDeadline
        let board = try XCTUnwrap(copied, "Comparison board did not copy a PNG")
        XCTAssertGreaterThan(board.pixelsWide, 1_000)
        XCTAssertGreaterThan(board.pixelsHigh, 500)
    }

    @MainActor
    func testRecentsSearchesAndDeletesOneCapture() throws {
        continueAfterFailure = false
        let app = launch(arguments: VitrineLaunchArguments.recents)
        defer { app.terminate() }
        let recents = RecentsRobot(testCase: self, app: app)

        XCTAssertEqual(
            recents.cards.count, 3)
        let search = recents.searchField
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.click()
        search.typeText("Rust")
        XCTAssertEqual(
            recents.cards.count, 1)

        assertHittable(
            "recents-preset-picker", in: app,
            "The filtered recent should keep its actions menu")
        element("recents-preset-picker", in: app).click()
        chooseMenuItem("Delete Capture", in: app)
        let confirmation = app.sheets.firstMatch.buttons["Delete Capture"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.click()

        XCTAssertTrue(element("recents-no-search-results", in: app).waitForExistence(timeout: 3))
    }

    /// One journey through the gallery's organizing actions; the ordering and storage
    /// rules are unit-tested in `RecentsStoreTests` and `FeatureTests`. Clearing runs
    /// last because it removes captures.
    @MainActor
    func testRecentsPinFilterSortAndClearUnpinned() {
        continueAfterFailure = false
        let app = launch(
            arguments: VitrineLaunchArguments.recents,
            environment: ["VITRINE_RECENTS_TEST_MAX_WIDTH": "560"])
        defer { app.terminate() }
        let recents = RecentsRobot(testCase: self, app: app)
        let cards = recents.cards

        XCTAssertTrue(recents.gallery.waitForExistence(timeout: 8))
        XCTAssertEqual(cards.count, 3)
        // On a slow runner the adaptive grid's cards can exist a beat before their
        // labels reflect the settled layout.
        waitForLabel(of: cards.element(boundBy: 1), toContain: "Rust")
        XCTAssertTrue(cards.element(boundBy: 0).label.contains("Go"))
        XCTAssertEqual(recents.pinnedBadges.count, 1)

        // Pinned captures lead the gallery, so the leading card shows that a pin change
        // landed. The badge count is then read once instead of polled.
        recents.presetPickers.element(boundBy: 0).click()
        chooseMenuItem("Unpin Capture", in: app)
        waitForLabel(of: cards.element(boundBy: 0), toContain: "Rust")
        XCTAssertEqual(recents.pinnedBadges.count, 0)
        recents.presetPickers.element(boundBy: 2).click()
        chooseMenuItem("Pin Capture", in: app)
        waitForLabel(of: cards.element(boundBy: 0), toContain: "Go")
        XCTAssertEqual(recents.pinnedBadges.count, 1)

        assertHittable(
            "recents-pinned-filter", in: app, "Recents should expose the pinned-only filter")
        hittableElement("recents-pinned-filter", in: app).click()
        waitForCount(of: cards, toEqual: 1)
        XCTAssertTrue(cards.firstMatch.label.contains("Go"))
        XCTAssertTrue(element("recents-pinned-badge", in: app).exists)
        // The adaptive action bar can rebuild its compact branch after filtering;
        // resolve the toggle again instead of reusing the pre-update AX handle.
        hittableElement("recents-pinned-filter", in: app).click()
        waitForCount(of: cards, toEqual: 3)

        assertHittable("recents-sort-picker", in: app, "Recents should expose its sort picker")
        hittableElement("recents-sort-picker", in: app).click()
        chooseMenuItem("Oldest First", in: app)
        waitForLabel(of: cards.element(boundBy: 1), toContain: "Python")
        XCTAssertTrue(cards.element(boundBy: 0).label.contains("Go"))
        XCTAssertTrue(cards.element(boundBy: 2).label.contains("Rust"))

        assertHittable(
            "recents-clear-button", in: app, "Recents should expose capture cleanup actions")
        hittableElement("recents-clear-button", in: app).click()
        // The menu item intentionally disappears as soon as it presents the dialog, so
        // click its center: an element click would resolve the defunct item mid-click.
        chooseMenuItem("Clear Unpinned", in: app, clickingCenter: true)
        let confirmation = app.sheets.firstMatch.buttons["Clear Unpinned"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.click()
        waitForCount(of: cards, toEqual: 1)
        XCTAssertTrue(cards.firstMatch.label.contains("Go"))
        XCTAssertTrue(element("recents-pinned-badge", in: app).exists)
    }

    @MainActor
    func testMenuBarRendersClipboardWithDestinationPreset() throws {
        continueAfterFailure = false
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("let answer = 42", forType: .string))

        let app = launch(arguments: VitrineLaunchArguments.menuBar)
        defer {
            app.terminate()
            pasteboard.clearContents()
        }

        // Preserve an end-to-end check through the painted status item. Opening the
        // panel after launch also keeps the XCTest automation handshake ahead of AppKit.
        openMenuBarPanel(in: app)

        assertHittable(
            "menu-capture-preset-picker", in: app,
            "The destination preset picker should be reachable from the menu-bar panel")
        element("menu-capture-preset-picker", in: app).click()

        chooseMenuItem("OpenGraph 1200×630", in: app)

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

        let app = launch(arguments: VitrineLaunchArguments.menuBarRecents)
        defer {
            app.terminate()
            pasteboard.clearContents()
        }

        openMenuBarPanel(in: app)
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
        // The panel lists captures newest first, so the last demo capture leads.
        XCTAssertEqual(
            pasteboard.string(forType: .string), "fn main() { println!(\"Hello from Rust\"); }")
        XCTAssertNil(pasteboard.data(forType: .png))
    }

    @MainActor
    func testMenuBarSurpriseStyleUpdatesThemeWithoutClosingThePanel() throws {
        continueAfterFailure = false
        let app = launch(arguments: VitrineLaunchArguments.menuBar)
        defer { app.terminate() }

        let panel = openMenuBarPanel(in: app)
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

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            panel.waitForNonExistence(timeout: 3), "Escape should close the menu-bar panel")
    }

    @MainActor
    func testFirstRunShowsQuickStartWithPrivacyAndSampleCapture() {
        continueAfterFailure = false
        // A fresh defaults suite is a first run, so the quick-start appears on
        // launch with no extra hook.
        let app = launch(arguments: [])
        defer { app.terminate() }

        assertExists(element("welcome-window", in: app), in: app, timeout: 8)
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
        // Onboarding owns the first launch: What's New never pre-empts it.
        XCTAssertFalse(element("whats-new-window", in: app).exists)

        // Running the sample capture needs no clipboard setup and reports inline.
        // Poll for hittability first: the welcome window can still be settling into
        // place when the button already exists, so an immediate click flakes with
        // "is not hittable" on the hosted CI runner.
        revealWelcomeControl("welcome-sample-capture-button", in: app)
        element("welcome-sample-capture-button", in: app).click()
        assertExists(element("welcome-sample-status", in: app), in: app, timeout: 5)
    }

    @MainActor
    func testQuickStartKeepsPrimaryActionsReachableAtCompactHeight() {
        continueAfterFailure = false
        let app = launch(
            arguments: [],
            environment: [
                "VITRINE_WELCOME_TEST_MAX_HEIGHT": "520",
                "VITRINE_WELCOME_TEST_MAX_WIDTH": "560",
            ])
        defer { app.terminate() }

        let window = element("welcome-window", in: app)
        assertExists(window, in: app, timeout: 8)
        XCTAssertLessThanOrEqual(
            window.frame.height, 521,
            "The deterministic compact-height seam did not constrain the Welcome window")
        XCTAssertLessThanOrEqual(
            window.frame.width, 561,
            "The deterministic compact-width seam did not constrain the Welcome window")
        assertExists(app.scrollViews["welcome-view"], in: app, timeout: 3)

        revealWelcomeControl("welcome-get-started-button", in: app)
        element("welcome-get-started-button", in: app).click()
        XCTAssertTrue(
            window.waitForNonExistence(timeout: 3),
            "Get Started should dismiss Welcome after scrolling to the compact footer")
    }

    @MainActor
    func testForcedQuickStartCanBeSkippedToReachTheEditor() {
        continueAfterFailure = false
        // Force the quick-start open and also open the editor: skipping the
        // quick-start must not gate access to the rest of the app.
        let app = launch(arguments: ["--show-welcome", "--demo", "--open-editor"])
        defer { app.terminate() }

        assertExists(element("welcome-window", in: app), in: app, timeout: 8)
        revealWelcomeControl("welcome-skip-button", in: app)
        element("welcome-skip-button", in: app).click()

        // After skipping, the editor window is available. This launch deliberately
        // opens Welcome and the editor at
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
    func testHistoryRecoveryAndPurgeRequireExplicitConfirmation() {
        continueAfterFailure = false
        let app = launch(
            arguments: VitrineLaunchArguments.emptyRecents + ["--history-recovery-demo"])
        defer { app.terminate() }
        let recents = RecentsRobot(testCase: self, app: app)
        let recover = element("history-recover", in: app)
        assertExists(recover, in: app, timeout: 8)
        XCTAssertGreaterThan(recents.cards.count, 0)
        recover.click()
        let cancel = recents.window.sheets.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(recover.exists)
        recover.click()
        let confirmRecovery = recents.window.sheets.buttons["Recover Valid Captures"]
        assertExists(confirmRecovery, in: app, timeout: 3)
        confirmRecovery.click()
        XCTAssertFalse(recover.exists)
        XCTAssertGreaterThan(recents.cards.count, 0)
        let purge = element("history-purge", in: app)
        purge.click()
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertGreaterThan(recents.cards.count, 0)
        purge.click()
        let confirmPurge = recents.window.sheets.buttons["Delete All History"]
        assertExists(confirmPurge, in: app, timeout: 3)
        confirmPurge.click()
        XCTAssertEqual(recents.cards.count, 0)
    }

    @MainActor
    func testHistoryConsentEscapeNeverCreatesARecord() {
        continueAfterFailure = false
        let app = launch(
            arguments: VitrineLaunchArguments.emptyRecents + ["--history-consent-demo"])
        defer { app.terminate() }
        assertExists(element("history-consent-no-save", in: app), in: app, timeout: 8)
        app.typeKey(.escape, modifierFlags: [])
        let recents = RecentsRobot(testCase: self, app: app)
        assertExists(recents.gallery, in: app, timeout: 5)
        XCTAssertEqual(recents.cards.count, 0)
    }

    // MARK: - Localization smoke

    @MainActor
    func testSettingsPanesSurviveAccentedPseudolocale() {
        continueAfterFailure = false
        // The accented, lengthened pseudolocale (`en-XA`) is longer than any shipped
        // translation. If a Settings pane truncated or clipped under it, its controls
        // would no longer resolve, so each pane's key control must stay hittable.
        let app = launch(arguments: VitrineLaunchArguments.settings, locale: .accentedPseudo)
        defer { app.terminate() }

        assertExists(element("settings-general-pane", in: app), in: app, timeout: 8)
        XCTAssertTrue(
            element("reset-all-settings-button", in: app).isHittable,
            "General pane control is clipped or unreachable under en-XA")

        // The sidebar row titles pseudo-localize too, so rows are selected by their
        // stable `settings-nav-*` identifiers rather than by visible title.
        for identifier in [
            "settings-nav-general", "settings-nav-style", "settings-nav-output",
            "settings-nav-about",
        ] {
            assertHittable(identifier, in: app, "Sidebar row \(identifier) is clipped under en-XA")
        }
        for (navIdentifier, paneIdentifier, control) in [
            ("settings-nav-style", "settings-style-pane", "style-theme-picker"),
            ("settings-nav-library", "settings-library-pane", "style-preset-picker"),
            ("settings-nav-output", "settings-output-pane", "output-format-picker"),
            ("settings-nav-about", "settings-about-pane", "export-diagnostics-button"),
        ] {
            element(navIdentifier, in: app).click()
            let pane = element(paneIdentifier, in: app)
            assertExists(pane, in: app, timeout: 3)
            XCTAssertTrue(
                element(control, in: app).waitForExistence(timeout: 3),
                "Pane \(paneIdentifier) is missing \(control) under en-XA")
            XCTAssertTrue(
                element(control, in: app).isHittable,
                "Control \(control) is clipped or unreachable under en-XA")
            if paneIdentifier == "settings-style-pane" {
                // Typography sits below a deliberately scrollable preview, so scrolling
                // to it is expected; clipping is not.
                if !element("style-font-picker", in: app).isHittable { pane.swipeUp() }
                assertHittable(
                    "style-font-picker", in: app,
                    "The font picker must be reachable after scrolling under en-XA")
            }
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
        let app = launch(arguments: VitrineLaunchArguments.editor, locale: .rightToLeftPseudo)
        defer { app.terminate() }

        assertExists(element("editor-window", in: app), in: app, timeout: 8)
        for identifier in [
            "editor-toolbar", "editor-preview-stage", "editor-inspector", "copy-button",
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
        assertToolbarActionsReachable(
            ["save-button", "share-button"], from: "editor-actions-menu", in: app)
    }

    @MainActor
    private func waitForCount(
        of query: XCUIElementQuery, toEqual count: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(3)
        while query.count != count, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(query.count, count, file: file, line: line)
    }

    @MainActor
    private func launch(
        arguments: [String],
        locale: VitrineLocaleOverride = .english,
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        VitrineAppRobot(testCase: self, suitePrefix: "VitrineUITests").launch(
            arguments: arguments, locale: locale, environment: environment)
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
