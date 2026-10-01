import AppKit
import Foundation
import XCTest

final class DocumentationExportUITests: XCTestCase {
    @MainActor
    func testDocumentationPackageInBothLocalesAppearancesAndWindowSizes() throws {
        continueAfterFailure = false
        let sizes = [CGSize(width: 940, height: 520), CGSize(width: 1280, height: 800)]
        let visible = try XCTUnwrap(NSScreen.main).visibleFrame.size
        XCTAssertGreaterThanOrEqual(
            visible.width, 1280, "Required documentation UI lane needs a qualified display")
        XCTAssertGreaterThanOrEqual(
            visible.height, 800, "Required documentation UI lane needs a qualified display")
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "vitrine-documentation-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        for language in ["en", "es"] {
            for dark in [false, true] {
                for size in sizes {
                    let robot = VitrineAppRobot(testCase: self, suitePrefix: "documentation-export")
                    let app = robot.launch(
                        arguments: VitrineLaunchArguments.editor + [
                            "-AppleLanguages", "(\(language))", "-AppleLocale", language,
                            dark ? "--appearance-dark" : "--appearance-light",
                        ],
                        environment: [
                            "VITRINE_UI_TEST_EDITOR_VIEWPORT":
                                "\(Int(size.width))x\(Int(size.height))"
                        ])
                    defer { app.terminate() }
                    let output = element("inspector-disclosure-output", in: app)
                    XCTAssertTrue(output.waitForExistence(timeout: 8), app.debugDescription)
                    reveal("inspector-disclosure-output", in: app)
                    output.click()
                    let description = element("alternative-text-field", in: app)
                    XCTAssertTrue(description.waitForExistence(timeout: 3), app.debugDescription)
                    reveal("alternative-text-field", in: app)
                    description.click()
                    description.typeText("Documentation example")
                    app.typeKey("k", modifierFlags: [.command])
                    let search = element("command-palette-field", in: app)
                    XCTAssertTrue(search.waitForExistence(timeout: 3))
                    search.typeText("docs")
                    let action = element("command-palette-command-export.documentation", in: app)
                    XCTAssertTrue(action.waitForExistence(timeout: 3), app.debugDescription)
                    action.click()
                    let folder = element("documentation-folder-name", in: app)
                    XCTAssertTrue(folder.waitForExistence(timeout: 3))
                    let name = "package-\(language)-\(dark)-\(Int(size.width))"
                    folder.click()
                    app.typeKey("a", modifierFlags: [.command])
                    folder.typeText(name)
                    element("documentation-html", in: app).click()
                    element("documentation-text", in: app).click()
                    let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                    screenshot.name = name
                    screenshot.lifetime = .keepAlways
                    add(screenshot)
                    element("documentation-export", in: app).click()
                    app.typeKey("g", modifierFlags: [.command, .shift])
                    app.typeText(parent.path)
                    app.typeKey(.return, modifierFlags: [])
                    let choose = app.buttons[language == "es" ? "Exportar aquí" : "Export Here"]
                        .firstMatch
                    XCTAssertTrue(choose.waitForExistence(timeout: 5), app.debugDescription)
                    choose.click()
                    XCTAssertTrue(
                        element("documentation-cancel", in: app).waitForNonExistence(timeout: 10),
                        app.debugDescription)
                    let directory = parent.appendingPathComponent(name)
                    XCTAssertEqual(
                        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)),
                        ["image.png", "README.md", "index.html", "source.txt"])
                    let markdown = try String(
                        contentsOf: directory.appendingPathComponent("README.md"), encoding: .utf8)
                    XCTAssertTrue(markdown.contains("Documentation example"))
                    XCTAssertTrue(markdown.contains("](image.png)"))
                    app.terminate()
                }
            }
        }
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

    @MainActor
    func testCancelPackageSheetWritesNothingAndKeepsEditor() throws {
        let app = VitrineAppRobot(testCase: self, suitePrefix: "documentation-cancel").launch(
            arguments: VitrineLaunchArguments.editor + ["--open-command-palette"])
        defer { app.terminate() }
        let search = element("command-palette-field", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.typeText("docs")
        element("command-palette-command-export.documentation", in: app).click()
        let cancel = element("documentation-cancel", in: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 3))
        XCTAssertTrue(element("editor-window", in: app).exists)
    }
}
