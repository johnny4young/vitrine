import SwiftUI

/// Window scene identifiers.
enum WindowID {
    static let editor = "editor"
}

/// Vitrine — a menu-bar app that turns code into images (CS-001).
///
/// The app lives entirely in the menu bar (`LSUIElement`, see Info.plist). The
/// `MenuBarExtra` provides the native menu with submenus; a separate `Window`
/// hosts the editor with live preview.
@main
struct VitrineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Vitrine", systemImage: "camera.viewfinder") {
            MenuBarContent()
                .environmentObject(AppSettings.shared)
        }
        .menuBarExtraStyle(.menu)

        Window("Vitrine Editor", id: WindowID.editor) {
            EditorView()
                .environmentObject(AppSettings.shared)
        }
        .windowResizability(.contentSize)
    }
}
