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

        // Global hotkey (CS-002): consume the key-up event stream on the main actor
        // and dispatch to the user-chosen action.
        hotkeyTask = Task {
            for await _ in KeyboardShortcuts.events(.keyUp, for: .quickCapture) {
                handleHotkey()
            }
        }

        handleLaunchArguments()
    }

    /// Development launch hooks: `--demo` preloads sample code, `--open-editor` /
    /// `--open-settings` open a window on launch (handy for manual UI testing).
    private func handleLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
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
        if arguments.contains("--open-editor") { EditorWindowController.shared.show() }
        if arguments.contains("--open-settings") { SettingsWindowManager.shared.show() }

        if arguments.contains("--snapshot-loop") {
            Task {
                for tick in 0..<14 {
                    try? await Task.sleep(for: .milliseconds(1500))
                    Self.snapshotOpenWindows(tag: tick)
                }
                NSApp.terminate(nil)
            }
        }
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
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            let safe = (window.title.isEmpty ? "window" : window.title)
                .replacingOccurrences(of: " ", with: "-")
            try? png.write(to: dir.appendingPathComponent("ui-\(safe)-\(tag).png"))
        }
    }

    private func handleHotkey() {
        let action = AppSettings.shared.hotkeyAction
        Log.app.info("Global hotkey fired (\(action.rawValue, privacy: .public))")
        switch action {
        case .quickCapture:
            Notifier.notify(QuickCapture.run(settings: .shared))
        case .openEditor:
            EditorWindowController.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.notice("Vitrine terminating")
        hotkeyTask?.cancel()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
