import AppKit
import SwiftUI

/// The menu-bar menu: quick-capture action, submenus (Recents ▸, Theme ▸),
/// preferences, about, and quit (CS-009).
struct MenuBarContent: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var recents: RecentsStore
    @EnvironmentObject private var feedback: CaptureFeedbackPresenter

    var body: some View {
        // Titles, SF Symbols, and shortcuts come from `VitrineCommand` so the
        // menu-bar menu and the application main menu (CS-032) never drift.
        commandButton(.newCapture) { QuickCapture.perform(settings: settings) }
        commandButton(.openEditor) { EditorWindowController.shared.show() }

        // Echo the last capture's outcome so the result stays reachable after the
        // transient HUD fades, and surface its recovery actions inline (CS-038).
        lastCaptureStatus

        Divider()

        recentsMenu
        themeMenu

        Divider()

        commandButton(.settings) { SettingsWindowManager.shared.show() }
        commandButton(.help) { SettingsWindowManager.shared.show() }
        commandButton(.about) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.aboutCredits])
        }

        Divider()

        Button("Quit Vitrine") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
        .accessibilityIdentifier("command-quit")
    }

    /// A menu-bar button driven by a `VitrineCommand`: shared title, SF Symbol,
    /// keyboard shortcut, and accessibility identifier (CS-032).
    @ViewBuilder
    private func commandButton(
        _ command: VitrineCommand, action: @escaping () -> Void
    )
        -> some View
    {
        let button = Button(action: action) {
            Label(command.title, systemImage: command.systemImageName)
        }
        .accessibilityIdentifier(command.accessibilityIdentifier)

        if let shortcut = command.swiftUIShortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    /// The last capture outcome as a disabled status line plus any inline recovery
    /// actions (CS-038). Hidden until a capture has run, so a clean launch shows no
    /// stale status. The status text itself is non-interactive; each recovery
    /// action is a real menu item routed back through the feedback presenter.
    @ViewBuilder private var lastCaptureStatus: some View {
        if let last = feedback.lastFeedback {
            Divider()
            Label("Last capture: \(last.message)", systemImage: last.systemImageName)
                .disabled(true)
                .accessibilityIdentifier("menu-last-capture-status")
            ForEach(last.actions, id: \.self) { action in
                Button(action.title) { feedback.run(action, settings: settings) }
                    .accessibilityIdentifier("menu-recovery-\(action.accessibilityToken)")
            }
        }
    }

    @ViewBuilder private var recentsMenu: some View {
        Menu("Recents") {
            // The visual gallery (CS-029) is a richer entry point to the same
            // history; the text list below keeps recents reachable in one click
            // for fast access without opening a window.
            Button("Recents Gallery…") { RecentsGalleryWindowController.shared.show() }
                .accessibilityIdentifier("menu-recents-gallery")

            Divider()

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
