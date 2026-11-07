import XCTest

/// The web sign-in opt-in. It lives apart from the smoke suite because the controlled
/// WebKit workflow also runs it in the Direct Download sandbox, and that workflow runs
/// only when a file it lists changes.
final class WebSignInUITests: XCTestCase {
    @MainActor
    func testWebSignInAffordanceRequiresExplicitSessionOptIn() {
        continueAfterFailure = false
        let app = VitrineAppRobot(testCase: self, suitePrefix: "web-sign-in").launch(
            arguments: VitrineLaunchArguments.webSnapshot)
        defer { app.terminate() }

        assertExists(element("web-snapshot-window", in: app), in: app, timeout: 8)
        let requiresDirect =
            ProcessInfo.processInfo.environment["VITRINE_REQUIRE_DIRECT_WEB_SESSION"] == "1"
        if !requiresDirect {
            // Without network access the window opens on HTML and explains why.
            assertExists(element("web-snapshot-html-editor", in: app), in: app, timeout: 3)
            assertExists(element("web-snapshot-url-badge", in: app), in: app, timeout: 3)
            hittableElement("web-snapshot-url-why-button", in: app).click()
            assertExists(
                element("web-snapshot-url-unavailable-note", in: app), in: app, timeout: 3)
            app.typeKey(.escape, modifierFlags: [])
            hittableElement("web-snapshot-mode-url", in: app).click()
        }
        let urlField = app.textFields["web-snapshot-url-field"]
        assertExists(urlField, in: app, timeout: 3)
        urlField.click()
        // Entering a URL must not load it. This test never captures or opens the
        // sign-in window, so it needs neither a website nor credentials.
        urlField.typeText("https://example.com")

        let hint = element("web-snapshot-sign-in-hint", in: app)
        let signIn = element("web-snapshot-sign-in-button", in: app)
        if !requiresDirect {
            // The ordinary UI suite uses App Store-compatible entitlements. It must
            // not offer sign-in merely because the Debug binary was compiled with
            // VITRINE_DIRECT_DOWNLOAD; runtime capability is the signed entitlement.
            XCTAssertFalse(hint.exists)
            XCTAssertFalse(signIn.exists)
            return
        }

        XCTAssertFalse(
            element("web-snapshot-url-badge", in: app).exists,
            "The signed Direct lane lost network capability")
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
