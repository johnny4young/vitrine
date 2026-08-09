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

    /// Opens the real menu-bar panel only after XCUIAutomation has attached.
    ///
    /// Opening an `NSPopover` from a launch argument is too early for a UI test:
    /// Sequoia can inject XCTAutomationSupport after `applicationDidFinishLaunching`
    /// and abort the app with a private libdispatch main-queue assertion. The
    /// post-launch handoff is accepted only by the isolated UI-test process and avoids
    /// status-item frames that can be non-hittable across logical display spaces.
    @MainActor
    @discardableResult
    func openMenuBarPanel(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let panel = element("menubar-panel", in: app)
        let sourceProcessID = ProcessInfo.processInfo.processIdentifier
        guard
            let url = URL(
                string: "vitrine://automation-menu-panel?source-pid=\(sourceProcessID)")
        else {
            XCTFail("The static menu-panel automation URL is invalid", file: file, line: line)
            return panel
        }
        let target = NSAppleEventDescriptor(
            bundleIdentifier: "com.johnny4young.vitrine")
        let handoff = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass),
            eventID: AEEventID(kAEGetURL),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        handoff.setParam(
            NSAppleEventDescriptor(string: url.absoluteString),
            forKeyword: AEKeyword(keyDirectObject))
        do {
            _ = try handoff.sendEvent(
                options: NSAppleEventDescriptor.SendOptions.noReply,
                timeout: 1)
        } catch {
            XCTFail(
                "The post-launch menu-panel handoff could not be delivered: \(error)",
                file: file,
                line: line)
            return panel
        }
        // Address Vitrine's unique bundle identifier directly. Launch Services URL
        // dispatch is deliberately avoided because another development build or test
        // host can register the same custom scheme and become foreground instead.
        app.activate()

        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "The menu-bar panel did not open after the automation handshake",
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
