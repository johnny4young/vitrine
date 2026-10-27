import AppKit
import Foundation
import XCTest

final class DocumentationExportUITests: XCTestCase {
    @MainActor
    func testDocumentationPackageInBothAppearancesAndWindowSizes() throws {
        continueAfterFailure = false
        let states = [
            (state: "en-light-minimum", dark: false, viewport: "minimum"),
            (state: "en-dark-1280", dark: true, viewport: "1280x800"),
        ]
        let visible = try XCTUnwrap(NSScreen.main).visibleFrame.size
        XCTAssertGreaterThanOrEqual(
            visible.width, 1280, "Required documentation UI lane needs a qualified display")
        XCTAssertGreaterThanOrEqual(
            visible.height, 800, "Required documentation UI lane needs a qualified display")
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "vitrine-documentation-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let pasteboard = NSPasteboard.general
        defer {
            try? FileManager.default.removeItem(at: parent)
            pasteboard.clearContents()
        }
        for request in states {
            let state = request.state
            var segmentStarted = ProcessInfo.processInfo.systemUptime
            func recordSegment(_ phase: String) {
                let now = ProcessInfo.processInfo.systemUptime
                print(
                    "DOCUMENTATION_UI_SEGMENT state=\(state) phase=\(phase) "
                        + "seconds=\(now - segmentStarted)")
                segmentStarted = now
            }
            let robot = VitrineAppRobot(testCase: self, suitePrefix: "documentation-export")
            let app = robot.launch(
                arguments: VitrineLaunchArguments.editor + [
                    request.dark ? "--appearance-dark" : "--appearance-light"
                ],
                environment: ["VITRINE_UI_TEST_EDITOR_VIEWPORT": request.viewport])
            recordSegment("launch")
            defer { app.terminate() }
            let window = element("editor-window", in: app)
            XCTAssertTrue(window.waitForExistence(timeout: 8), app.debugDescription)
            let geometry = NSPredicate { _, _ in
                let frame = window.frame
                if request.viewport == "minimum" {
                    return abs(frame.width - 940) <= 2 && frame.height >= 520
                        && frame.height < 600
                }
                return abs(frame.width - 1280) <= 2 && abs(frame.height - 800) <= 2
            }
            if !geometry.evaluate(with: nil) {
                XCTAssertEqual(
                    XCTWaiter.wait(
                        for: [XCTNSPredicateExpectation(predicate: geometry, object: nil)],
                        timeout: 5), .completed,
                    "Requested viewport was ignored or clipped: \(window.frame)")
            }
            let output = element("inspector-disclosure-output", in: app)
            XCTAssertTrue(output.waitForExistence(timeout: 8), app.debugDescription)
            reveal("inspector-disclosure-output", in: app)
            output.click()
            recordSegment("navigation")
            let description = element("alternative-text-field", in: app)
            XCTAssertTrue(description.waitForExistence(timeout: 3), app.debugDescription)
            reveal("alternative-text-field", in: app)
            description.click()
            description.typeText("Documentation example")
            let descriptionAccepted = NSPredicate { _, _ in
                (description.value as? String) == "Documentation example"
            }
            if !descriptionAccepted.evaluate(with: nil) {
                XCTAssertEqual(
                    XCTWaiter.wait(
                        for: [
                            XCTNSPredicateExpectation(predicate: descriptionAccepted, object: nil)
                        ], timeout: 3), .completed,
                    "The description must be entered in its own field")
            }
            recordSegment("description")
            // Cancelling writes nothing and keeps the editor; the reopened sheet exports.
            let written = try FileManager.default.contentsOfDirectory(atPath: parent.path)
            openPackageSheet(in: app)
            let cancel = element("documentation-cancel", in: app)
            cancel.click()
            XCTAssertTrue(cancel.waitForNonExistence(timeout: 3))
            XCTAssertTrue(window.exists)
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: parent.path), written)
            openPackageSheet(in: app)
            let folder = element("documentation-folder-name", in: app)
            XCTAssertTrue(folder.waitForExistence(timeout: 3))
            let name = "package-\(state)"
            folder.click()
            app.typeKey("a", modifierFlags: [.command])
            folder.typeText(name)
            element("documentation-html", in: app).click()
            element("documentation-text", in: app).click()
            let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
            recordSegment("package-setup")
            element("documentation-export", in: app).click()
            app.typeKey("g", modifierFlags: [.command, .shift])
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString(parent.path, forType: .string))
            app.typeKey("v", modifierFlags: [.command])
            app.typeKey(.return, modifierFlags: [])
            let panel = app.dialogs["open-panel"]
            // Check current readiness before starting a polling wait; `||`
            // short-circuits, so delayed readiness keeps the same bounded waits.
            XCTAssertTrue(
                panel.exists || panel.waitForExistence(timeout: 5), app.debugDescription)
            // AppKit exposes this button's localized AXTitle, not an AXLabel.
            // Its in-dialog identifier excludes the Touch Bar duplicate.
            let choose = panel.buttons["OKButton"]
            XCTAssertTrue(
                choose.exists || choose.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(
                choose.isHittable
                    || choose.wait(for: \.isHittable, toEqual: true, timeout: 5),
                app.debugDescription)
            recordSegment("panel")
            choose.click()
            XCTAssertTrue(
                element("documentation-cancel", in: app).waitForNonExistence(timeout: 10),
                app.debugDescription)
            recordSegment("export")
            let directory = parent.appendingPathComponent(name)
            XCTAssertEqual(
                Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)),
                ["image.png", "README.md", "index.html", "source.txt"])
            let markdown = try String(
                contentsOf: directory.appendingPathComponent("README.md"), encoding: .utf8)
            XCTAssertTrue(markdown.hasPrefix("![Documentation example](image.png)\n"), markdown)
            let html = try String(
                contentsOf: directory.appendingPathComponent("index.html"), encoding: .utf8)
            XCTAssertTrue(html.contains("alt=\"Documentation example\""), html)
            let source = try String(
                contentsOf: directory.appendingPathComponent("source.txt"), encoding: .utf8)
            XCTAssertFalse(source.contains("Documentation example"), source)
            recordSegment("validation")
            app.terminate()
            recordSegment("termination")
        }
    }

    @MainActor
    private func openPackageSheet(in app: XCUIApplication) {
        let options = element("copy-options-menu", in: app)
        XCTAssertTrue(options.wait(for: \.isHittable, toEqual: true, timeout: 3))
        options.click()
        let action = element("documentation-action", in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 3), app.debugDescription)
        action.click()
        XCTAssertTrue(
            element("documentation-cancel", in: app).waitForExistence(timeout: 3),
            app.debugDescription)
    }

    @MainActor
    private func reveal(_ identifier: String, in app: XCUIApplication) {
        if waitForHittableElement(identifier, in: app, timeout: 1) { return }
        let inspector = element("editor-inspector", in: app)
        XCTAssertTrue(inspector.waitForExistence(timeout: 3))
        for _ in 0..<5 {
            inspector.swipeUp()
            if waitForHittableElement(identifier, in: app, timeout: 0.75) { return }
        }
        assertHittable(identifier, in: app, "Documentation control is not reachable")
    }
}
