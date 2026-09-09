import SwiftUI

/// Vitrine — a menu-bar app that turns code into images.
///
/// The app lives entirely in the menu bar (`LSUIElement`, see Info.plist). The status
/// item and the panel it presents are owned by `StatusItemController` rather than vended
/// by a SwiftUI `MenuBarExtra` scene — see that type for the macOS 26 behaviour that made
/// the scene terminate this agent shortly after launch. The editor and preferences are
/// AppKit-hosted windows opened on demand (see `EditorWindowController` /
/// `SettingsWindowManager`).
@main
struct VitrineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar is owned by `StatusItemController` (installed by `AppDelegate`),
        // not by a `MenuBarExtra` scene — see that type for the macOS 26 behaviour that
        // made the SwiftUI scene terminate this agent shortly after launch.
        //
        // An `App` still needs a scene, and this one is inert on purpose: every window
        // Vitrine shows is AppKit-hosted (`EditorWindowController`,
        // `SettingsWindowManager`, …). ⌘, opens the real settings window, because the
        // designed AppKit main menu installed in `AppMenu` owns that shortcut and
        // `applicationWillUpdate(_:)` re-asserts the menu whenever SwiftUI displaces it.
        Settings {
            EmptyView()
        }
    }
}
