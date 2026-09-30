import XCTest

final class ShortcutOptInUITests: XCTestCase {
    @MainActor
    func testSettingsRecorderOptsInReassignsAndStaysDisabledAfterRelaunch() {
        continueAfterFailure = false
        for language in ["en", "es"] {
            let app = VitrineAppRobot(testCase: self, suitePrefix: "shortcut-opt-in").launch(
                arguments: VitrineLaunchArguments.settings
                    + ["-AppleLanguages", "(\(language))", "-AppleLocale", language])
            defer { app.terminate() }
            let recorder = element("settings-hotkey-recorder", in: app)
            XCTAssertTrue(recorder.waitForExistence(timeout: 8), app.debugDescription)
            expectValue("", in: recorder)
            retainScreenshot(app, name: "Optional shortcut Settings \(language)")
            record("k", in: recorder, app: app)
            let first = recorder.value as? String ?? ""
            XCTAssertTrue(first.contains("K"), "Recorded shortcut missing: \(first)")

            app.terminate()
            app.launch()
            app.activate()
            XCTAssertTrue(recorder.waitForExistence(timeout: 8), app.debugDescription)
            expectValue(first, in: recorder)
            record("j", in: recorder, app: app)
            let reassigned = recorder.value as? String ?? ""
            XCTAssertTrue(reassigned.contains("J"), "Reassignment missing: \(reassigned)")
            XCTAssertNotEqual(reassigned, first)

            recorder.click()
            app.typeKey(.delete, modifierFlags: [])
            expectValue("", in: recorder)
            app.terminate()
            app.launch()
            app.activate()
            XCTAssertTrue(recorder.waitForExistence(timeout: 8), app.debugDescription)
            expectValue("", in: recorder)
        }
    }

    @MainActor
    func testWelcomeOffersMenuCaptureBeforeOptionalShortcutInEnglishAndSpanish() {
        continueAfterFailure = false
        for language in ["en", "es"] {
            let app = VitrineAppRobot(testCase: self, suitePrefix: "shortcut-welcome").launch(
                arguments: ["-AppleLanguages", "(\(language))", "-AppleLocale", language])
            defer { app.terminate() }
            XCTAssertTrue(element("welcome-window", in: app).waitForExistence(timeout: 8))
            let fallback = language == "es" ? "usa la barra de menús" : "use the menu bar"
            let caption = app.staticTexts
                .matching(NSPredicate(format: "value CONTAINS %@", fallback)).firstMatch
            XCTAssertTrue(caption.waitForExistence(timeout: 3), app.debugDescription)
            revealWelcomeControl("welcome-hotkey-recorder", in: app)
            let recorder = element("welcome-hotkey-recorder", in: app)
            XCTAssertTrue(recorder.exists, app.debugDescription)
            expectValue("", in: recorder)
            let help = element("welcome-hotkey-scope", in: app)
            XCTAssertTrue(
                (help.value as? String ?? "").contains(language == "es" ? "Opcional" : "Optional"))
            retainScreenshot(app, name: "Optional shortcut Welcome \(language)")
            record("k", in: recorder, app: app)
            XCTAssertTrue(caption.waitForNonExistence(timeout: 3))
            recorder.click()
            app.typeKey(.delete, modifierFlags: [])
            expectValue("", in: recorder)
            XCTAssertTrue(caption.waitForExistence(timeout: 3))
        }
    }

    @MainActor
    private func retainScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func record(_ key: String, in recorder: XCUIElement, app: XCUIApplication) {
        recorder.click()
        app.typeKey(key, modifierFlags: [.control, .option, .command, .shift])
        let changed = NSPredicate { _, _ in
            (recorder.value as? String)?.contains(key.uppercased()) == true
        }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 3),
            .completed)
    }

    @MainActor
    private func expectValue(_ value: String, in recorder: XCUIElement) {
        let predicate = NSPredicate(format: "value == %@", value)
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: predicate, object: recorder)], timeout: 3
            ),
            .completed, "Expected \(value.debugDescription); recorder: \(recorder.debugDescription)"
        )
    }
}
