import SwiftUI

/// Vitrine — a menu-bar app that turns code into images (CS-001).
///
/// The app lives entirely in the menu bar (`LSUIElement`, see Info.plist). The
/// `MenuBarExtra` provides the native menu with submenus; the editor and
/// preferences are AppKit-hosted windows opened on demand (see
/// `EditorWindowController` / `SettingsWindowManager`).
@main
struct VitrineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Vitrine", systemImage: "camera.viewfinder") {
            MenuBarContent()
                .environmentObject(AppSettings.shared)
                .environmentObject(RecentsStore.shared)
        }
        .menuBarExtraStyle(.menu)
    }
}
