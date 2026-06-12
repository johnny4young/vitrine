import AppKit
import XCTest

extension XCTestCase {
    /// Brings the app genuinely frontmost so its main-menu bar realizes.
    ///
    /// Vitrine is normally an LSUIElement/accessory app; under synthetic activation
    /// its menu-bar items can exist in the accessibility tree with zero-sized frames.
    /// Menu-bar tests launch with `--standard-activation` and then click a real app
    /// window so macOS hands the menu bar to the test process.
    @MainActor
    func makeFrontmostForMenuBarAccess(
        _ app: XCUIApplication, clicking window: XCUIElement
    ) {
        app.activate()
        window.click()
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// Skips display-geometry-sensitive tests when no attached display can hold
    /// the editor at its minimum supported size.
    ///
    /// `EditorView`'s 940x520 root frame plus window chrome needs a small margin.
    /// Below that, control hittability cannot hold no matter what the app does, so
    /// the assertion would be testing the display, not the product.
    @MainActor
    func skipUnlessADisplayFitsTheEditor() throws {
        let required = CGSize(width: 960, height: 600)
        let visible = NSScreen.screens.map(\.visibleFrame)
        try XCTSkipUnless(
            visible.contains { $0.width >= required.width && $0.height >= required.height },
            "No display fits the editor's minimum "
                + "\(Int(required.width))x\(Int(required.height)) window "
                + "(visible frames: \(visible)); hittability cannot be asserted here.")
    }

    /// The first AX element carrying `identifier`, of any type — the shared
    /// lookup every smoke and tour assertion goes through.
    @MainActor
    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Every AX element carrying `identifier`, resolved fresh on each call.
    ///
    /// A single identifier can legitimately match nested elements: an AppKit toolbar
    /// item can wrap the SwiftUI button it hosts and both expose the same identifier.
    @MainActor
    private func matches(_ identifier: String, in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .allElementsBoundByIndex
    }

    /// Asserts some element carrying `identifier` becomes hittable, polling briefly.
    ///
    /// The control is reachable when any matching element is hittable. On failure it
    /// attaches screen, window, match geometry, and the full accessibility hierarchy.
    @MainActor
    func assertHittable(
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
}
