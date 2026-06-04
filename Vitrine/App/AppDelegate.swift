import AppKit
import KeyboardShortcuts

/// App lifecycle: configures the agent app and listens for the global hotkey.
///
/// The whole module defaults to `@MainActor` isolation (see `project.yml`), so this
/// delegate and the task it starts run on the main actor without extra annotations.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }

    private func handleHotkey() {
        switch AppSettings.shared.hotkeyAction {
        case .quickCapture:
            Notifier.notify(QuickCapture.run(settings: .shared))
        case .openEditor:
            EditorWindowController.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyTask?.cancel()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
