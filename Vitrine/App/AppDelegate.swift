import AppKit
import CoreServices
import KeyboardShortcuts
import OSLog

/// App lifecycle: configures the agent app and listens for the global hotkey.
///
/// The whole module defaults to `@MainActor` isolation (see `project.yml`), so this
/// delegate and the task it starts run on the main actor without extra annotations.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyTask: Task<Void, Never>?

    /// Whether the menu-bar icon's hover tooltip has been installed yet, so the
    /// idempotent installer in `applicationWillUpdate(_:)` stops searching once
    /// it has found the status-bar button.
    private var didInstallMenuBarTooltip = false

    /// Remaining attempts to locate the status-bar button before the installer gives
    /// up. `applicationWillUpdate(_:)` fires on every event-loop pass, so without a
    /// bound a failure to find the button (e.g. a future SwiftUI hosting change) would
    /// re-run a full window-tree DFS forever, per event. The button appears within the
    /// first few update passes on a normal launch; the tooltip is cosmetic, so
    /// exhausting the budget quietly drops it rather than taxing every event.
    private var menuBarTooltipAttemptsRemaining = 240

    /// Enforce a single running instance. A menu-bar agent must never stack a second
    /// status item, but launching the same bundle id from a different path — several
    /// Xcode DerivedData copies, or `open`-ing more than one built `.app` — starts a
    /// second process with the same identifier. If another Vitrine is already running
    /// when this one launches, hand activation back to it and exit *before* the SwiftUI
    /// scene installs a duplicate `MenuBarExtra` icon. UI tests are unaffected:
    /// `XCUIApplication.launch()` terminates any prior instance before launching, so no
    /// other instance is ever present here under test.
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Handle `vitrine://edit` handoffs from the CLI (`--edit`). Register before the
        // single-instance guard and the SwiftUI scene so a URL that *cold-launches* the
        // app is still delivered once the AppleEvent queue drains. When an instance is
        // already running, the OS routes the open to it instead of spawning a new one.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))

        // Never enforce single-instance under tests. The *unit*-test host launches this
        // app to host XCTest (`XCTestConfigurationFilePath` is set) even while a developer
        // instance is open; exiting here aborts the run with "test runner exited before
        // establishing connection". The *UI*-test host instead sets
        // `VITRINE_USER_DEFAULTS_SUITE` (also used for test isolation). Either signal
        // means "do not enforce".
        guard Self.shouldEnforceSingleInstance(ProcessInfo.processInfo.environment) else { return }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != .current }
        if let existing = others.first {
            existing.activate()
            exit(0)
        }
    }

    /// Whether to enforce the single-instance guard for a launch with this environment.
    /// Returns `false` under tests — the unit-test host sets `XCTestConfigurationFilePath`
    /// and the UI-test host sets `VITRINE_USER_DEFAULTS_SUITE` — so a test run is never
    /// killed by a developer instance that happens to be open. Pure + injectable so the
    /// rule is unit-testable.
    static func shouldEnforceSingleInstance(_ environment: [String: String]) -> Bool {
        environment["VITRINE_USER_DEFAULTS_SUITE"] == nil
            && environment["XCTestConfigurationFilePath"] == nil
    }

    /// GetURL AppleEvent entry point: pulls the `vitrine://…` string out of the event
    /// and routes it to `openHandoff`.
    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?
                .stringValue,
            let url = URL(string: urlString)
        else { return }
        openHandoff(url)
    }

    /// Seeds the editor from a `vitrine://edit` handoff (the CLI's `--edit`): reads the
    /// staged content and optional language hint, then loads it into the primary editor
    /// — replacing that window's document like quick capture and the Open-Code App Intent
    /// do (CS-027/034), seeded on the user's current style. A no-op for any other URL or
    /// an empty payload, so a stray open can never blank the editor.
    func openHandoff(_ url: URL) {
        guard let handoff = EditorHandoff.consume(url: url) else { return }
        var config = AppSettings.shared.config
        config.code = handoff.content
        if let language = handoff.language { config.language = language }
        EditorWindowController.shared.loadIntoPrimary(config)
        NSApp.activate(ignoringOtherApps: true)
        Log.app.notice("Opened a CLI --edit handoff in the editor")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("Vitrine launched")
        // Agent app — no Dock icon (also declared via LSUIElement in Info.plist).
        NSApp.setActivationPolicy(.accessory)

        // Install the application main menu (CS-032). An agent app with only a
        // `MenuBarExtra` scene gets no designed menu bar from SwiftUI; assigning one
        // here gives the editor and settings windows a complete, keyboard-accessible
        // menu bar (App ▸, File ▸, Edit ▸, View ▸, Window ▸, Help ▸). SwiftUI's scene
        // bring-up overwrites this menu with its own default after this method
        // returns, so `applicationWillUpdate(_:)` below re-asserts it.
        AppMenu.install()

        // Global hotkey (CS-002): consume the key-up event stream on the main actor
        // and dispatch to the user-chosen action.
        hotkeyTask = Task {
            for await _ in KeyboardShortcuts.events(.keyUp, for: .quickCapture) {
                handleHotkey()
            }
        }

        // Resolve the PRO entitlement at launch and — on the App Store build — observe
        // out-of-band StoreKit updates, so a refund or a purchase made on another device
        // re-locks/unlocks PRO without a relaunch (CS-089).
        Entitlements.shared.startLiveUpdates()

        // First-run surfaces on a normal launch (CS-035/CS-049): onboarding owns the
        // first launch; once it has been seen, What's New surfaces on a version
        // upgrade — never both. Skipped when a dev launch hook already opened a window
        // so the manual/UI-test surfaces above are not pre-empted or stacked over.
        if !handleLaunchArguments() {
            if !WelcomeWindowController.shared.presentIfFirstRun() {
                WhatsNewWindowController.shared.presentIfNewVersion()
            }
        }

        // Pay the syntax highlighter's one-time cold start now, off the render path, so
        // a user whose first interaction is a ⇧⌘S quick capture doesn't eat the
        // JavaScriptCore + theme-CSS warm-up inside the "instant" gesture. Low priority
        // so it never contends with the menu bar coming up or a hotkey already firing.
        Task(priority: .utility) { HighlightManager.shared.prewarm() }
    }

    /// Development launch hooks (manual UI testing + the screenshot/UI-smoke tours);
    /// none of these run on a normal user launch. `--demo` preloads sample code;
    /// `--demo-html-format` preloads compact markup for the Format Code smoke test;
    /// `--demo-sql-format` does the same for a compact query;
    /// `--demo-recent` seeds one local capture; `--demo-recents` seeds a varied set;
    /// `--open-editor` / `--open-settings` / `--open-recents` open a window;
    /// `--show-help` / `--show-welcome` force those windows open past their gates;
    /// `--seen-old-version` seeds an older last-seen version and then presents What's
    /// New through its real version gate; `--skip-onboarding` just marks the
    /// quick-start as seen; the multi-window hooks (`--open-second-editor`,
    /// `--force-offscreen-editor`) drive the CS-053 UI smoke tests; `--demo-brand-kit-free`
    /// seeds a PRO Brand Kit watermark in free-placement mode for UI smoke tests.
    ///
    /// - Returns: whether a hook opened a window, so the normal first-run surfaces
    ///   (`presentIfFirstRun` / `presentIfNewVersion`) are not stacked on top of one.
    private func handleLaunchArguments() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        var didOpenWindow = false
        if arguments.contains("--skip-onboarding") {
            AppSettings.shared.hasSeenWelcome = true
        }
        // Run as a regular app (Dock icon, owns the menu bar when active) so the
        // screenshot tour can realize and open the main menus; an accessory app's
        // menu-bar items stay zero-sized under synthetic activation.
        if arguments.contains("--standard-activation") {
            NSApp.setActivationPolicy(.regular)
        }
        // Pin the app to one appearance regardless of the system setting, so
        // design audits can capture light and dark deterministically.
        if arguments.contains("--appearance-dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        if arguments.contains("--appearance-light") {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        if arguments.contains("--demo") {
            AppSettings.shared.config.code = """
                import SwiftUI

                struct CounterView: View {
                    @State private var count = 0

                    var body: some View {
                        Button("Tapped \\(count) times") {
                            count += 1
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                """
        }
        if arguments.contains("--demo-html-format") {
            var demo = AppSettings.shared.config
            demo.code =
                #"<!doctype html><main class="card"><h1>Vitrine</h1><p>Local by design.</p><img src="preview.png"></main>"#
            demo.language = .html
            AppSettings.shared.config = demo
        }
        if arguments.contains("--demo-sql-format") {
            var demo = AppSettings.shared.config
            demo.code =
                "SELECT u.id,u.email,COUNT(o.id) AS orders FROM users u LEFT JOIN orders o ON o.user_id=u.id WHERE u.active=TRUE GROUP BY u.id,u.email ORDER BY orders DESC;"
            demo.language = .sql
            AppSettings.shared.config = demo
        }
        if arguments.contains("--demo-recent") {
            RecentsStore.shared.add(
                Capture(
                    code: """
                        struct DestinationCard: View {
                            let title: String

                            var body: some View {
                                Text(title)
                                    .font(.title.bold())
                            }
                        }
                        """,
                    languageID: Language.swift.rawValue,
                    themeID: Theme.dracula.id))
        }
        if arguments.contains("--demo-recents") {
            let captures = [
                Capture(
                    code: "func greet(name string) string { return \"Hello, \" + name }",
                    languageID: Language.go.rawValue,
                    themeID: Theme.github.id),
                Capture(
                    code:
                        "def fibonacci(n):\n    return n if n < 2 else fibonacci(n - 1) + fibonacci(n - 2)",
                    languageID: Language.python.rawValue,
                    themeID: Theme.oneDark.id),
                Capture(
                    code: "fn main() { println!(\"Hello from Rust\"); }",
                    languageID: Language.rust.rawValue,
                    themeID: Theme.dracula.id),
            ]
            for capture in captures { RecentsStore.shared.add(capture) }
            RecentsStore.shared.updatePinned(id: captures[0].id, isPinned: true)
        }
        // A richer demo that exercises the window title, diff bands, and line numbers
        // at once — for screenshots / visual QA of the editor's newer styling.
        if arguments.contains("--demo-showcase") {
            var demo = AppSettings.shared.config
            demo.code = """
                @@ -1,4 +1,5 @@
                 func greet(_ name: String) -> String {
                -    return "Hello, " + name
                +    let trimmed = name.trimmingCharacters(in: .whitespaces)
                +    return "Hello, \\(trimmed)!"
                 }
                """
            demo.language = .diff
            demo.windowTitle = "Greeter.swift"
            demo.diffDecorations = true
            demo.showLineNumbers = true
            demo.cornerRadius = 16
            AppSettings.shared.config = demo
            EditorWindowController.shared.show()
            didOpenWindow = true
        }
        if arguments.contains("--demo-brand-kit-free") {
            let store = BrandKitStore.shared
            store.isEnabled = true
            store.brandKit = BrandKit(
                handle: "@vitrine", project: "demo", placement: .free,
                freePosition: CGPoint(x: 0.72, y: 0.78))
        }
        if arguments.contains("--open-editor") {
            EditorWindowController.shared.show()
            didOpenWindow = true
        }
        if arguments.contains("--open-command-palette") {
            EditorWindowController.shared.show()
            didOpenWindow = true
            // Let the editor window finish coming up, then ask it to open the palette.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                NotificationCenter.default.post(name: .vitrineOpenCommandPalette, object: nil)
            }
        }
        if arguments.contains("--demo-beautify-image") {
            // Load the app icon as a foreground image so the editor opens in image mode
            // (the "beautify any image" panel), for the image-panel UI smoke tests.
            if let data = NSApp.applicationIconImage.tiffRepresentation,
                let reference = try? BackgroundImageStore.foregroundContainer.importImage(
                    data: data, preferredExtension: "tiff")
            {
                AppSettings.shared.config.foregroundImage = reference
            }
            EditorWindowController.shared.show()
            didOpenWindow = true
        }
        if arguments.contains("--open-settings") {
            SettingsWindowManager.shared.show()
            didOpenWindow = true
        }
        if arguments.contains("--open-recents") {
            RecentsGalleryWindowController.shared.show()
            didOpenWindow = true
        }
        if arguments.contains("--open-social-card") {
            SocialCardWindowController.shared.show()
            didOpenWindow = true
        }
        if arguments.contains("--open-web-snapshot") {
            WebSnapshotPresenter.show()
            didOpenWindow = true
        }
        if arguments.contains("--show-about") {
            AboutPanel.present()
            didOpenWindow = true
        }
        if arguments.contains("--show-help") {
            HelpWindowController.shared.show()
            didOpenWindow = true
        }
        if arguments.contains("--show-welcome") {
            WelcomeWindowController.shared.show()
            didOpenWindow = true
        }
        if arguments.contains("--seen-old-version") {
            AppSettings.shared.hasSeenWelcome = true
            AppSettings.shared.lastSeenWhatsNewVersion = "0.0.1"
            WhatsNewWindowController.shared.presentIfNewVersion()
            didOpenWindow = true
        }

        // Open two independent editor windows so the multi-window UI smoke (CS-053) can
        // assert both exist and that closing one leaves the other.
        if arguments.contains("--open-second-editor") {
            EditorWindowController.shared.show()
            EditorWindowController.shared.openNewWindow()
            didOpenWindow = true
        }

        // Open the editor and force it off-screen so the off-screen-recovery UI smoke
        // (CS-053) can verify the window is pulled back onto a visible display.
        if arguments.contains("--force-offscreen-editor") {
            EditorWindowController.shared.show()
            EditorWindowController.shared.moveKeyEditorOffScreenForTesting()
            didOpenWindow = true
        }

        if arguments.contains("--snapshot-loop") {
            Task {
                for tick in 0..<14 {
                    try? await Task.sleep(for: .milliseconds(1500))
                    Self.snapshotOpenWindows(tag: tick)
                }
                NSApp.terminate(nil)
            }
        }

        return didOpenWindow
    }

    /// Dev/CI helper: periodically snapshots every open window's content view via
    /// `cacheDisplay` (the app draws itself — no screen-recording permission needed),
    /// so a UI can be captured while it is being driven (e.g. by AppleScript).
    private static func snapshotOpenWindows(tag: Int) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vitrine-ui", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for window in NSApp.windows {
            guard window.isVisible, let view = window.contentView, view.bounds.width > 40,
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = flattenedPNG(rep, over: window) else { continue }
            let safe = (window.title.isEmpty ? "window" : window.title)
                .replacingOccurrences(of: " ", with: "-")
            try? png.write(to: dir.appendingPathComponent("ui-\(safe)-\(tag).png"))
        }
    }

    /// Flattens a `cacheDisplay` capture over the window's background color.
    ///
    /// Material chrome (the editor's preset strip and inspector) is composited by
    /// the window server, so a raw `cacheDisplay` bitmap leaves those regions
    /// semi-transparent — image viewers then show an alpha checkerboard that the
    /// live window never has. Filling the window background underneath (resolved
    /// in the window's own appearance) yields an opaque PNG matching the on-screen
    /// look, minus the blur — still without Screen Recording permission, which
    /// this helper deliberately avoids.
    private static func flattenedPNG(_ rep: NSBitmapImageRep, over window: NSWindow) -> Data? {
        guard
            let canvas = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: rep.pixelsWide,
                pixelsHigh: rep.pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0),
            let graphics = NSGraphicsContext(bitmapImageRep: canvas)
        else { return nil }

        let pixelRect = NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            pixelRect.fill()
            // Explicit source-over: `NSImageRep.draw(in:)` composites with .copy,
            // which would replace the just-filled background — alpha included —
            // and leave the capture translucent again.
            rep.draw(
                in: pixelRect, from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: false, hints: nil)
        }
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return canvas.representation(using: .png, properties: [:])
    }

    private func handleHotkey() {
        let action = AppSettings.shared.hotkeyAction
        Log.app.info("Global hotkey fired (\(action.rawValue, privacy: .public))")
        switch action {
        case .quickCapture:
            QuickCapture.perform(settings: .shared)
        case .openEditor:
            EditorWindowController.shared.show()
        }
    }

    /// SwiftUI's `MenuBarExtra` scene bring-up installs its default main menu shortly
    /// after `applicationDidFinishLaunching` — by replacing the installed menu's items
    /// in place — wiping the designed menu installed above (File and Edit vanish from
    /// the menu bar, and main-menu key equivalents like ⌘E and ⌘S go dead). Re-assert
    /// the AppKit menu whenever it has been taken over; the pointer checks inside keep
    /// this effectively free on this hot every-event path.
    func applicationWillUpdate(_ notification: Notification) {
        AppMenu.reinstallIfDisplaced()
        ensureMenuBarTooltip()
    }

    /// Give the menu-bar icon a hover tooltip ("Vitrine"). SwiftUI's `MenuBarExtra`
    /// owns the `NSStatusItem` and exposes no API for its tooltip, so reach the
    /// underlying status-bar button through the window hierarchy and set it directly.
    /// Driven from `applicationWillUpdate(_:)` because the status item is created
    /// during SwiftUI's scene bring-up, after `applicationDidFinishLaunching`; the
    /// flag makes it a no-op once the button has been found, so this hot path stays
    /// cheap.
    private func ensureMenuBarTooltip() {
        guard !didInstallMenuBarTooltip, menuBarTooltipAttemptsRemaining > 0 else { return }
        menuBarTooltipAttemptsRemaining -= 1
        for window in NSApp.windows {
            guard let button = Self.firstStatusBarButton(in: window.contentView) else { continue }
            // "Vitrine" is the verbatim brand wordmark, like the other brand strings
            // that bypass the String Catalog (CS-047).
            button.toolTip = "Vitrine"
            didInstallMenuBarTooltip = true
            return
        }
    }

    /// Depth-first search for the `NSStatusBarButton` in a view subtree (the status
    /// item's button is hosted inside the status-bar window's content view).
    private static func firstStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let found = firstStatusBarButton(in: subview) { return found }
        }
        return nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.notice("Vitrine terminating")
        hotkeyTask?.cancel()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
