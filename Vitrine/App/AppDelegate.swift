import AppKit
import KeyboardShortcuts
import OSLog

/// App lifecycle: configures the agent app and listens for the global hotkey.
///
/// The whole module defaults to `@MainActor` isolation (see `project.yml`), so this
/// delegate and the task it starts run on the main actor without extra annotations.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyTask: Task<Void, Never>?

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

        // First-run surfaces on a normal launch (CS-035/CS-049): onboarding owns the
        // first launch; once it has been seen, What's New surfaces on a version
        // upgrade — never both. Skipped when a dev launch hook already opened a window
        // so the manual/UI-test surfaces above are not pre-empted or stacked over.
        if !handleLaunchArguments() {
            if !WelcomeWindowController.shared.presentIfFirstRun() {
                WhatsNewWindowController.shared.presentIfNewVersion()
            }
        }
    }

    /// Development launch hooks (manual UI testing + the screenshot/UI-smoke tours);
    /// none of these run on a normal user launch. `--demo` preloads sample code;
    /// `--open-editor` / `--open-settings` / `--open-recents` open a window;
    /// `--show-help` / `--show-welcome` force those windows open past their gates;
    /// `--seen-old-version` seeds an older last-seen version and then presents What's
    /// New through its real version gate; `--skip-onboarding` just marks the
    /// quick-start as seen; the multi-window hooks (`--open-second-editor`,
    /// `--force-offscreen-editor`) drive the CS-053 UI smoke tests.
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
        if arguments.contains("--open-editor") {
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.notice("Vitrine terminating")
        hotkeyTask?.cancel()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
