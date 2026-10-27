import XCTest

/// Real key capture in the shortcut recorders. Persistence across launches and the
/// no-re-enable policy are covered by `GlobalShortcutMigrationTests`.
final class ShortcutOptInUITests: XCTestCase {
    @MainActor
    func testSettingsRecorderOptsInReassignsAndClears() {
        continueAfterFailure = false
        let app = VitrineAppRobot(testCase: self, suitePrefix: "shortcut-opt-in").launch(
            arguments: VitrineLaunchArguments.settings)
        defer { app.terminate() }
        let recorder = element("settings-hotkey-recorder", in: app)
        XCTAssertTrue(recorder.waitForExistence(timeout: 8), app.debugDescription)
        expectValue("", in: recorder)
        retainScreenshot(app.windows.firstMatch, name: "Optional shortcut Settings")
        record("k", in: recorder, app: app)
        let first = recorder.value as? String ?? ""
        XCTAssertTrue(first.contains("K"), "Recorded shortcut missing: \(first)")

        record("j", in: recorder, app: app)
        let reassigned = recorder.value as? String ?? ""
        XCTAssertTrue(reassigned.contains("J"), "Reassignment missing: \(reassigned)")
        XCTAssertNotEqual(reassigned, first)

        recorder.click()
        app.typeKey(.delete, modifierFlags: [])
        expectValue("", in: recorder)
    }

    @MainActor
    func testReservedMenuShortcutPreservesExistingOptIn() {
        continueAfterFailure = false
        let app = VitrineAppRobot(testCase: self, suitePrefix: "shortcut-menu-conflict").launch(
            arguments: VitrineLaunchArguments.settings)
        defer { app.terminate() }
        let recorder = element("settings-hotkey-recorder", in: app)
        XCTAssertTrue(recorder.waitForExistence(timeout: 8), app.debugDescription)
        expectValue("", in: recorder)
        record("k", in: recorder, app: app)
        let assigned = recorder.value as? String ?? ""

        recorder.click()
        app.typeKey("s", modifierFlags: [.command, .shift])
        let alert = app.sheets.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3), app.debugDescription)
        let message = alert.staticTexts.allElementsBoundByIndex.map {
            ($0.value as? String) ?? $0.label
        }.joined(separator: " ")
        XCTAssertTrue(message.contains("Capture"), alert.debugDescription)
        retainScreenshot(alert, name: "Reserved menu shortcut")
        alert.buttons.firstMatch.click()
        expectValue(assigned, in: recorder)
    }

    @MainActor
    func testWelcomeOffersMenuCaptureBeforeOptionalShortcut() {
        continueAfterFailure = false
        let app = VitrineAppRobot(testCase: self, suitePrefix: "shortcut-welcome").launch(
            arguments: [])
        defer { app.terminate() }
        XCTAssertTrue(element("welcome-window", in: app).waitForExistence(timeout: 8))
        let privacy = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "Direct download")
        ).firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue((privacy.value as? String ?? "").contains("license"))
        let caption = app.staticTexts
            .matching(NSPredicate(format: "value CONTAINS %@", "use the menu bar")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 3), app.debugDescription)
        revealWelcomeControl("welcome-hotkey-recorder", in: app)
        let recorder = element("welcome-hotkey-recorder", in: app)
        XCTAssertTrue(recorder.exists, app.debugDescription)
        expectValue("", in: recorder)
        let help = element("welcome-hotkey-scope", in: app)
        XCTAssertTrue((help.value as? String ?? "").contains("Optional"))
        retainScreenshot(app.windows.firstMatch, name: "Optional shortcut Welcome")
        record("k", in: recorder, app: app)
        XCTAssertTrue(caption.waitForNonExistence(timeout: 3))
        recorder.click()
        app.typeKey(.delete, modifierFlags: [])
        expectValue("", in: recorder)
        XCTAssertTrue(caption.waitForExistence(timeout: 3))
    }

    @MainActor
    private func retainScreenshot(_ target: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: target.screenshot())
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
        // XCTest's waits never report in under a second; read once before waiting.
        if changed.evaluate(with: nil) { return }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 3),
            .completed)
    }

    @MainActor
    private func expectValue(_ value: String, in recorder: XCUIElement) {
        if recorder.value as? String == value { return }
        let predicate = NSPredicate(format: "value == %@", value)
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: predicate, object: recorder)], timeout: 3
            ),
            .completed, "Expected \(value.debugDescription); recorder: \(recorder.debugDescription)"
        )
    }
}
