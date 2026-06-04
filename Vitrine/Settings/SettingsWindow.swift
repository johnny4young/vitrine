import AppKit
import Settings

// NOTE: imports only AppKit + the `Settings` package (NOT SwiftUI) to avoid the
// name clash between SwiftUI's `Settings` scene and the package's `Settings`
// namespace. The SwiftUI pane views live in `SettingsPanes.swift`.

/// Owns and presents the preferences window, backed by the Settings package (CS-010).
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private lazy var windowController = SettingsWindowController(
        panes: [generalPane(), stylePane(), outputPane(), inputPane(), aboutPane()],
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

    private func icon(_ symbol: String, _ description: String) -> NSImage {
        NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            ?? NSImage(size: NSSize(width: 1, height: 1))
    }

    private func generalPane() -> SettingsPane {
        let pane = Settings.Pane(
            identifier: .general, title: "General", toolbarIcon: icon("gearshape", "General")
        ) {
            GeneralSettingsView(settings: .shared, presets: .shared)
        }
        return Settings.PaneHostingController(pane: pane)
    }

    private func stylePane() -> SettingsPane {
        let pane = Settings.Pane(
            identifier: .style, title: "Style", toolbarIcon: icon("paintpalette", "Style")
        ) {
            StyleSettingsView(settings: .shared, presets: .shared, themes: .shared)
        }
        return Settings.PaneHostingController(pane: pane)
    }

    private func outputPane() -> SettingsPane {
        let pane = Settings.Pane(
            identifier: .output, title: "Output",
            toolbarIcon: icon("square.and.arrow.up.on.square", "Output")
        ) {
            OutputSettingsView(settings: .shared)
        }
        return Settings.PaneHostingController(pane: pane)
    }

    private func inputPane() -> SettingsPane {
        let pane = Settings.Pane(
            identifier: .input, title: "Input", toolbarIcon: icon("doc.on.clipboard", "Input")
        ) {
            InputSettingsView(settings: .shared)
        }
        return Settings.PaneHostingController(pane: pane)
    }

    private func aboutPane() -> SettingsPane {
        let pane = Settings.Pane(
            identifier: .about, title: "About", toolbarIcon: icon("info.circle", "About")
        ) {
            AboutSettingsView(settings: .shared)
        }
        return Settings.PaneHostingController(pane: pane)
    }
}

extension Settings.PaneIdentifier {
    static let general = Self("general")
    static let style = Self("style")
    static let output = Self("output")
    static let input = Self("input")
    static let about = Self("about")
}
