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

    /// Skips a first-run quick-start interaction when no attached display is tall
    /// enough to hold the welcome window without overhanging.
    ///
    /// The quick-start is a fixed, non-scrolling surface; on a display shorter than
    /// the window its bottom controls (Skip / sample capture) fall off the screen and
    /// can never be hittable, so a click assertion there would be testing the display,
    /// not the product. The window's own size is read at runtime (rather than
    /// hard-coding a height) and compared against the tallest display's visible frame,
    /// mirroring `skipUnlessADisplayFitsTheEditor`. The hosted CI runner's display
    /// height varies between allocations, which is what made these tests flake.
    ///
    /// (That the window overhangs small displays at all is a real product gap, tracked
    /// separately — the fix is to let the welcome window fit/scroll on short screens.)
    @MainActor
    func skipUnlessADisplayFitsTheWelcomeWindow(_ app: XCUIApplication) throws {
        let window = app.windows["welcome-window"]
        guard window.waitForExistence(timeout: 8) else { return }
        let windowHeight = window.frame.height
        let tallest = NSScreen.screens.map(\.visibleFrame.height).max() ?? 0
        try XCTSkipUnless(
            tallest >= windowHeight,
            "No display is tall enough (\(Int(tallest))pt) to hold the welcome window "
                + "(\(Int(windowHeight))pt) without overhanging; its bottom controls "
                + "cannot be hittable here.")
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

    /// Returns whether some element carrying `identifier` becomes hittable.
    ///
    /// A single identifier can legitimately match nested AppKit/SwiftUI elements, so
    /// the control is reachable when any matching element is hittable.
    @MainActor
    func waitForHittableElement(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 3
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if matches(identifier, in: app).contains(where: { $0.isHittable }) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }

    /// Reveals a toolbar action that may be direct at wide widths or nested in a
    /// compact overflow menu, then returns the freshly resolved accessibility element.
    @MainActor
    @discardableResult
    func revealToolbarAction(
        _ identifier: String,
        from menuIdentifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        if !waitForHittableElement(identifier, in: app, timeout: 0.5) {
            assertHittable(
                menuIdentifier,
                in: app,
                "Compact toolbar menu \(menuIdentifier) is not reachable",
                file: file,
                line: line)
            element(menuIdentifier, in: app).click()
        }

        assertHittable(
            identifier,
            in: app,
            "Toolbar action \(identifier) is not reachable",
            file: file,
            line: line)
        return element(identifier, in: app)
    }

    /// Verifies a group of actions without selecting one. Compact menus stay open
    /// while every item is checked, whereas wide toolbars need no special handling.
    @MainActor
    func assertToolbarActionsReachable(
        _ identifiers: [String],
        from menuIdentifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if identifiers.contains(where: {
            !waitForHittableElement($0, in: app, timeout: 0.5)
        }) {
            assertHittable(
                menuIdentifier,
                in: app,
                "Compact toolbar menu \(menuIdentifier) is not reachable",
                file: file,
                line: line)
            element(menuIdentifier, in: app).click()
        }

        for identifier in identifiers {
            assertHittable(
                identifier,
                in: app,
                "Toolbar action \(identifier) is not reachable",
                file: file,
                line: line)
        }
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
        if waitForHittableElement(identifier, in: app, timeout: timeout) { return }

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
