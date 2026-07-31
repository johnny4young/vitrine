import AppKit

/// Handles explicit development and UI-automation launch arguments.
///
/// Keeping these non-production entry points outside `AppDelegate` leaves the delegate
/// focused on process lifecycle while still resolving every seeded setting and store from
/// the same environment as the running app.
final class AppLaunchArgumentHandler {
    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
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
    /// `--force-offscreen-editor`) drive UI smoke tests; `--demo-brand-kit-free`
    /// seeds a PRO Brand Kit watermark in free-placement mode for UI smoke tests.
    ///
    /// - Returns: whether a hook opened a window, so the normal first-run surfaces
    ///   (`presentIfFirstRun` / `presentIfNewVersion`) are not stacked on top of one.
    func handle(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        let settings = environment.appSettings
        var didOpenWindow = false
        if arguments.contains("--skip-onboarding") {
            settings.hasSeenWelcome = true
        }
        // Run as a regular app (Dock icon, owns the menu bar when active) so the
        // screenshot tour can realize and open the main menus; an accessory app's
        // menu-bar items stay zero-sized under synthetic activation.
        if arguments.contains("--standard-activation") {
            NSApp.setActivationPolicy(.regular)
        }
        // Pin the app to one appearance regardless of the system setting, so
        // visual checks can capture light and dark deterministically.
        if arguments.contains("--appearance-dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        if arguments.contains("--appearance-light") {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        if arguments.contains("--demo") {
            settings.config.code = """
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
            var demo = settings.config
            demo.code =
                #"<!doctype html><main class="card"><h1>Vitrine</h1><p>Local by design.</p><img src="preview.png"></main>"#
            demo.language = .html
            settings.config = demo
        }
        if arguments.contains("--demo-sql-format") {
            var demo = settings.config
            demo.code =
                "SELECT u.id,u.email,COUNT(o.id) AS orders FROM users u LEFT JOIN orders o ON o.user_id=u.id WHERE u.active=TRUE GROUP BY u.id,u.email ORDER BY orders DESC;"
            demo.language = .sql
            settings.config = demo
        }
        if arguments.contains("--demo-recent") {
            environment.recents.add(
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
            for capture in captures { environment.recents.add(capture) }
            environment.recents.updatePinned(id: captures[0].id, isPinned: true)
        }
        // A richer demo that exercises the window title, diff bands, and line numbers
        // at once — for screenshots / visual QA of the editor's newer styling.
        if arguments.contains("--demo-showcase") {
            var demo = settings.config
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
            settings.config = demo
            EditorWindowController.shared.show()
            didOpenWindow = true
        }
        if arguments.contains("--demo-brand-kit-free") {
            let store = environment.brandKit
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
            // The editor reads this same argument in its own `.task` and opens the
            // palette when it appears — robust to the window's bring-up timing (a
            // one-shot notification posted here could arrive before the editor
            // subscribed, which flaked on the slow CI runner).
            EditorWindowController.shared.show()
            didOpenWindow = true
        }
        if arguments.contains("--demo-beautify-image") {
            // Load the app icon as a foreground image so the editor opens in image mode
            // (the "beautify any image" panel), for the image-panel UI smoke tests.
            if let data = NSApp.applicationIconImage.tiffRepresentation,
                let reference = try? BackgroundImageStore.foregroundContainer.importImage(
                    data: data, preferredExtension: "tiff")
            {
                settings.config.foregroundImage = reference
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
            WelcomeWindowController.shared.show(settings: settings)
            didOpenWindow = true
        }
        if arguments.contains("--seen-old-version") {
            settings.hasSeenWelcome = true
            settings.lastSeenWhatsNewVersion = "0.0.1"
            WhatsNewWindowController.shared.presentIfNewVersion(settings: settings)
            didOpenWindow = true
        }

        // Open two independent editor windows so the multi-window UI smoke can
        // assert both exist and that closing one leaves the other.
        if arguments.contains("--open-second-editor") {
            EditorWindowController.shared.show()
            EditorWindowController.shared.openNewWindow()
            didOpenWindow = true
        }

        // Open the editor and force it off-screen so the off-screen-recovery UI smoke
        // can verify the window is pulled back onto a visible display.
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
}
