import SwiftUI

/// The editor's ⌘K command catalog.
///
/// Each command wraps an action the editor already exposes — applying a theme,
/// toggling a style, running an export — so the palette is a faster route to them,
/// never a second implementation. Built fresh each time the palette opens, so the
/// toggle labels reflect the current state ("Hide line numbers" when they're on).
extension EditorView {
    var commandPaletteCommands: [EditorCommand] {
        themeCommands + toggleCommands + styleCommands + exportCommands
    }

    /// One "Apply <theme>" command per built-in theme, tagged with its appearance so
    /// "dark" / "light" surface the right ones.
    private var themeCommands: [EditorCommand] {
        Theme.all.map { theme in
            EditorCommand(
                id: "theme.\(theme.id)",
                title: "\(String(localized: "Theme")): \(theme.displayName)",
                group: String(localized: "Theme"),
                keywords: [
                    theme.appearance == .dark
                        ? String(localized: "Dark") : String(localized: "Light"),
                    String(localized: "Color"), String(localized: "Syntax"),
                ],
                symbol: "paintpalette"
            ) { settings.selectTheme(theme) }
        }
    }

    /// The style toggles, each labeled for what a run would do next (the inverse of
    /// the current state), so the palette reads like a verb list.
    private var toggleCommands: [EditorCommand] {
        [
            toggle(
                id: "toggle.lineNumbers",
                offTitle: String(localized: "Show line numbers"),
                onTitle: String(localized: "Hide line numbers"),
                symbol: "list.number",
                keywords: [String(localized: "Line numbers")],
                isOn: settings.config.showLineNumbers,
                set: { settings.config.showLineNumbers = $0 }),
            toggle(
                id: "toggle.shadow",
                offTitle: String(localized: "Show shadow"),
                onTitle: String(localized: "Hide shadow"),
                symbol: "shadow",
                isOn: settings.config.showShadow, set: { settings.config.showShadow = $0 }),
            toggle(
                id: "toggle.chrome",
                offTitle: String(localized: "Show window controls"),
                onTitle: String(localized: "Hide window controls"),
                symbol: "macwindow",
                keywords: ["chrome", "traffic lights", "dots"],
                isOn: settings.config.showChrome, set: { settings.config.showChrome = $0 }),
            toggle(
                id: "toggle.wrap",
                offTitle: String(localized: "Show line wrap"),
                onTitle: String(localized: "Hide line wrap"),
                symbol: "text.wrap",
                keywords: ["soft wrap", "long lines"],
                isOn: settings.config.wrapsLongLines,
                set: { settings.config.wrapColumns = $0 ? SettingsDefaults.wrapColumns : nil }),
            toggle(
                id: "toggle.ligatures",
                offTitle: String(localized: "Enable font ligatures"),
                onTitle: String(localized: "Disable font ligatures"),
                symbol: "textformat",
                isOn: settings.config.fontLigatures,
                set: { settings.config.fontLigatures = $0 }),
        ]
    }

    /// Style actions that aren't simple toggles.
    private var styleCommands: [EditorCommand] {
        [
            EditorCommand(
                id: "style.surprise", title: String(localized: "Surprise Me"),
                group: String(localized: "Style"),
                keywords: ["random", "shuffle", "lucky", "theme"], symbol: "dice"
            ) { _ = settings.applySurpriseStyle() }
        ]
    }

    /// The export/copy actions the toolbar also offers, reachable by name.
    private var exportCommands: [EditorCommand] {
        [
            EditorCommand(
                id: "export.copy", title: VitrineCommand.copyImage.title,
                group: String(localized: "Export"),
                keywords: ["png", "clipboard"], symbol: "doc.on.doc"
            ) { copyImage() },
            EditorCommand(
                id: "export.save", title: VitrineCommand.saveImage.title,
                group: String(localized: "Export"),
                keywords: ["png", "pdf", "heic", "disk"], symbol: "square.and.arrow.down"
            ) { saveImage() },
            EditorCommand(
                id: "export.markdown", title: VitrineCommand.copyMarkdown.title,
                group: String(localized: "Export"),
                keywords: ["md", "fenced", "readme"],
                symbol: "chevron.left.forwardslash.chevron.right"
            ) { copyMarkdown() },
        ]
    }

    /// Builds a toggle command whose localized title names the next action.
    private func toggle(
        id: String, offTitle: String, onTitle: String, symbol: String,
        keywords: [String] = [],
        isOn: Bool, set: @escaping (Bool) -> Void
    ) -> EditorCommand {
        EditorCommand(
            id: id,
            title: isOn ? onTitle : offTitle,
            group: String(localized: "Style"),
            keywords: keywords + [String(localized: "Toggle")],
            symbol: symbol
        ) { set(!isOn) }
    }
}
