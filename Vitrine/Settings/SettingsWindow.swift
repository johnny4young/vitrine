import AppKit
import Settings

// NOTE: This file intentionally imports only AppKit + the `Settings` package and
// NOT SwiftUI, to avoid the name clash between SwiftUI's `Settings` scene and the
// package's `Settings` namespace. The SwiftUI pane views live in
// `SettingsPanes.swift`.

/// Owns and presents the preferences window, backed by the Settings package (CS-010).
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private lazy var windowController = SettingsWindowController(
        panes: [generalPane(), stylePane()],
        style: .toolbarItems,
        animated: true,
        hidesToolbarForSingleItem: true
    )

    private init() {}

    /// Shows the preferences window and brings the app forward.
    func show() {
        windowController.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func generalPane() -> SettingsPane {
        let pane = Settings.Pane(
            identifier: .general,
            title: "General",
            toolbarIcon: NSImage(
                systemSymbolName: "gearshape", accessibilityDescription: "General")!
        ) {
            GeneralSettingsView(settings: .shared)
        }
        return Settings.PaneHostingController(pane: pane)
    }

    private func stylePane() -> SettingsPane {
        let pane = Settings.Pane(
            identifier: .style,
            title: "Style",
            toolbarIcon: NSImage(
                systemSymbolName: "paintpalette", accessibilityDescription: "Style")!
        ) {
            StyleSettingsView(settings: .shared)
        }
        return Settings.PaneHostingController(pane: pane)
    }
}

extension Settings.PaneIdentifier {
    static let general = Self("general")
    static let style = Self("style")
}
