import AppKit
import SwiftUI

/// The menu-bar menu: quick-capture action, submenus (Recents ▸, Theme ▸),
/// preferences, about, and quit (CS-009).
struct MenuBarContent: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Capture from Clipboard") {
            QuickCapture.run(settings: settings)
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        Button("Open Editor…") {
            openWindow(id: WindowID.editor)
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Menu("Recents") {
            // TODO: CS-009 — list the last 10 captures, reopenable in the editor.
            Text("No recent captures")
        }

        Menu("Theme") {
            ForEach(Theme.all) { theme in
                Button {
                    settings.selectTheme(theme)
                } label: {
                    if settings.config.theme.id == theme.id {
                        Label(theme.displayName, systemImage: "checkmark")
                    } else {
                        Text(theme.displayName)
                    }
                }
            }
        }

        Divider()

        Button("Preferences…") {
            SettingsWindowManager.shared.show()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("About Vitrine") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        }

        Divider()

        Button("Quit Vitrine") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
