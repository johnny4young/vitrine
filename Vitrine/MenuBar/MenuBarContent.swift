import AppKit
import SwiftUI

/// The menu-bar menu: quick-capture action, submenus (Recents ▸, Theme ▸),
/// preferences, about, and quit (CS-009).
struct MenuBarContent: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var recents: RecentsStore

    var body: some View {
        Button("New Capture from Clipboard") {
            Notifier.notify(QuickCapture.run(settings: settings))
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        Button("Open Editor…") {
            EditorWindowController.shared.show()
        }

        Divider()

        recentsMenu
        themeMenu

        Divider()

        Button("Preferences…") {
            SettingsWindowManager.shared.show()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("About Vitrine") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.aboutCredits])
        }

        Divider()

        Button("Quit Vitrine") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    @ViewBuilder private var recentsMenu: some View {
        Menu("Recents") {
            if recents.captures.isEmpty {
                Text("No recent captures")
            } else {
                ForEach(recents.captures) { capture in
                    Button(capture.menuTitle) { reopen(capture) }
                }
                Divider()
                Button("Clear Recents") { recents.clear() }
            }
        }
    }

    @ViewBuilder private var themeMenu: some View {
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
    }

    /// Branded credits for the standard About panel, so the system "About
    /// Vitrine" surface echoes the Settings About pane's identity copy instead
    /// of drifting to bare system text (CS-036). The panel supplies the app
    /// icon, name, and version; these credits add the matching tagline and
    /// license line.
    private static var aboutCredits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor(Brand.Palette.textSecondary.color),
            .paragraphStyle: paragraph,
        ]
        return NSAttributedString(
            string:
                "Turn code into beautiful images, from your menu bar.\n© 2026 johnny4young · MIT",
            attributes: attributes)
    }

    /// Loads a recent capture into the editor and shows it.
    private func reopen(_ capture: Capture) {
        settings.config.code = capture.code
        settings.config.language = capture.language
        settings.config.theme = capture.theme
        EditorWindowController.shared.show()
    }
}
