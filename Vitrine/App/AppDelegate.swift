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
