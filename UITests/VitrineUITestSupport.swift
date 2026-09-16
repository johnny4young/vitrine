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

    /// Resolves the actionable node when AppKit gives a wrapper and its control
    /// the same accessibility identifier.
    ///
    /// Keep `element(_:in:)` lazy: eagerly enumerating every match can outlive a
    /// transient HUD. Use this targeted lookup only for stable controls that need
    /// wrapper disambiguation.
    @MainActor
    func hittableElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        matches(identifier, in: app).first(where: { $0.isHittable })
            ?? element(identifier, in: app)
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

    /// Chooses `title` from the menu open in `app`, and confirms the menu took the click.
    ///
    /// AppKit closes a menu before it sends the chosen item's action, so while the item is
    /// still on screen nothing has been chosen and no wait for the effect can pass. A loaded
    /// runner can drop the click: a CI screen recording showed the Recents actions menu still
    /// open, the item highlighted under the pointer, for the rest of the test. The item is
    /// then clicked once more, as a person would. That cannot choose it twice, because the
    /// first click never reached the action.
    ///
    /// `clickingCenter` clicks the middle of the item instead of the element. An item whose
    /// action presents a dialog disappears during the click, and an element click resolves
    /// the item again while it synthesizes the event, then fails on the defunct element.
    @MainActor
    func chooseMenuItem(
        _ title: String,
        in app: XCUIApplication,
        clickingCenter: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let item = app.menuItems[title]
        guard item.waitForExistence(timeout: 3) else {
            XCTFail("The open menu has no \"\(title)\" item", file: file, line: line)
            return
        }
        choose(item, titled: title, clickingCenter: clickingCenter, file: file, line: line)
    }

    /// Chooses `item`, already found in the open menu, and confirms the menu took the click
    /// the same way ``chooseMenuItem(_:in:clickingCenter:file:line:)`` does.
    ///
    /// For a test that looks at the open menu before choosing, such as a tour capture of the
    /// highlighted item: it finds the item, captures, then chooses it here.
    @MainActor
    func chooseMenuItem(
        _ item: XCUIElement,
        clickingCenter: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard item.waitForExistence(timeout: 3) else {
            XCTFail("The menu item to choose is not in the open menu", file: file, line: line)
            return
        }
        choose(item, titled: item.title, clickingCenter: clickingCenter, file: file, line: line)
    }

    @MainActor
    private func choose(
        _ item: XCUIElement,
        titled title: String,
        clickingCenter: Bool,
        file: StaticString,
        line: UInt
    ) {
        func click() {
            if clickingCenter {
                item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            } else {
                item.click()
            }
        }
        click()
        if menuClosed(after: item) { return }
        XCTContext.runActivity(named: "The menu is still open; click \"\(title)\" again") { _ in
            click()
        }
        if menuClosed(after: item) { return }
        XCTFail("The menu stayed open after two clicks on \"\(title)\"", file: file, line: line)
    }

    /// Whether the menu holding `item` has closed. A single query answers once it has;
    /// XCTest's own wait never reports sooner than a second, so it runs only while the item
    /// is still there.
    @MainActor
    private func menuClosed(after item: XCUIElement) -> Bool {
        !item.exists || item.waitForNonExistence(timeout: 2)
    }

    /// Waits for `element`'s accessibility label to contain `text`, and says what it read
    /// instead when it never does.
    @MainActor
    func waitForLabel(
        of element: XCUIElement,
        toContain text: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if element.label.contains(text) { return }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        if XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed { return }
        XCTFail(
            "Expected a label containing \"\(text)\" within \(timeout)s; it reads \"\(element.label)\"",
            file: file, line: line)
    }

    /// Opens the real menu-bar panel only after XCUIAutomation has attached.
    ///
    /// Opening an `NSPopover` from a launch argument is too early for a UI test:
    /// Sequoia can inject XCTAutomationSupport after `applicationDidFinishLaunching`
    /// and abort the app with a private libdispatch main-queue assertion. Clicking the
    /// in-process status item exercises the production interaction after the automation
    /// handshake. On multi-display hosts, XCTest can expose the item at a valid negative
    /// coordinate yet refuse to click it; explicitly opted-in tests then ask the same app
    /// process to open the panel at its deterministic on-screen automation anchor.
    @MainActor
    @discardableResult
    func openMenuBarPanel(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let panel = element("menubar-panel", in: app)
        if waitForHittableElement("menubar-status-item", in: app, timeout: 8) {
            hittableElement("menubar-status-item", in: app).click()
        } else if let token = MenuBarTestControl.token(in: app.launchArguments) {
            DistributedNotificationCenter.default().postNotificationName(
                MenuBarTestControl.notificationName,
                object: token,
                userInfo: nil,
                options: [.deliverImmediately])
        } else {
            assertHittable(
                "menubar-status-item", in: app,
                "The in-process menu-bar item is not reachable and the fallback is disabled",
                timeout: 0, file: file, line: line)
        }

        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "The menu-bar panel did not open after the post-launch interaction",
            file: file,
            line: line)
        return panel
    }

    /// Reveals a Welcome control that may sit below the fold on a compact display.
    /// Tall windows expose it immediately; on short windows this helper advances the
    /// adaptive scroll surface until the control is usable.
    @MainActor
    func revealWelcomeControl(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if waitForHittableElement(identifier, in: app, timeout: 1) { return }

        let scrollView = app.scrollViews["welcome-view"]
        if scrollView.waitForExistence(timeout: 2) {
            for _ in 0..<5 {
                scrollView.swipeUp()
                if waitForHittableElement(identifier, in: app, timeout: 0.75) { return }
            }
        }

        assertHittable(
            identifier,
            in: app,
            "Welcome control \(identifier) is not reachable after scrolling",
            file: file,
            line: line)
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
        return hittableElement(identifier, in: app)
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
        let automationSize = XCUIScreen.main.screenshot().image.size
        let geometry =
            (["matches for '\(identifier)': \(found.count)"] + found + windows + screens)
            .joined(separator: "\n") + "\nautomation screen size=\(automationSize)"
        let attachment = XCTAttachment(string: geometry + "\n\n" + app.debugDescription)
        attachment.name = "Hittability diagnostics"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail(message, file: file, line: line)
    }
}
