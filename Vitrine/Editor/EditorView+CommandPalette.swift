import SwiftUI

/// The editor's ⌘K command catalog (feature #56 / analysis §8.2).
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
                title: "Theme: \(theme.displayName)",
                group: "Theme",
                keywords: [theme.appearance == .dark ? "dark" : "light", "color", "syntax"],
                symbol: "paintpalette"
            ) { settings.selectTheme(theme) }
        }
    }

    /// The style toggles, each labeled for what a run would do next (the inverse of
    /// the current state), so the palette reads like a verb list.
    private var toggleCommands: [EditorCommand] {
        [
            toggle(
                id: "toggle.lineNumbers", noun: "line numbers", symbol: "list.number",
                isOn: settings.config.showLineNumbers,
                set: { settings.config.showLineNumbers = $0 }),
            toggle(
                id: "toggle.shadow", noun: "shadow", symbol: "shadow",
                isOn: settings.config.showShadow, set: { settings.config.showShadow = $0 }),
            toggle(
                id: "toggle.chrome", noun: "window controls", symbol: "macwindow",
                keywords: ["chrome", "traffic lights", "dots"],
                isOn: settings.config.showChrome, set: { settings.config.showChrome = $0 }),
            toggle(
                id: "toggle.wrap", noun: "line wrap", symbol: "text.wrap",
                keywords: ["soft wrap", "long lines"],
                isOn: settings.config.wrapsLongLines,
                set: { settings.config.wrapColumns = $0 ? SettingsDefaults.wrapColumns : nil }),
            toggle(
                id: "toggle.ligatures", noun: "font ligatures", symbol: "textformat",
                isOn: settings.config.fontLigatures,
                set: { settings.config.fontLigatures = $0 }),
        ]
    }

    /// Style actions that aren't simple toggles.
    private var styleCommands: [EditorCommand] {
        [
            EditorCommand(
                id: "style.surprise", title: "Surprise Me", group: "Style",
                keywords: ["random", "shuffle", "lucky", "theme"], symbol: "dice"
            ) { _ = settings.applySurpriseStyle() }
        ]
    }

    /// The export/copy actions the toolbar also offers, reachable by name.
    private var exportCommands: [EditorCommand] {
        [
            EditorCommand(
                id: "export.copy", title: "Copy image", group: "Export",
                keywords: ["png", "clipboard"], symbol: "doc.on.doc"
            ) { copyImage() },
            EditorCommand(
                id: "export.save", title: "Save to file…", group: "Export",
                keywords: ["png", "pdf", "heic", "disk"], symbol: "square.and.arrow.down"
            ) { saveImage() },
            EditorCommand(
                id: "export.markdown", title: "Copy as Markdown", group: "Export",
                keywords: ["md", "fenced", "readme"],
                symbol: "chevron.left.forwardslash.chevron.right"
            ) { copyMarkdown() },
        ]
    }

    /// Builds a toggle command whose title names the action a run performs — "Show
    /// line numbers" when off, "Hide line numbers" when on — so the label is always
    /// the verb, never the current value.
    private func toggle(
        id: String, noun: String, symbol: String, keywords: [String] = [],
        isOn: Bool, set: @escaping (Bool) -> Void
    ) -> EditorCommand {
        EditorCommand(
            id: id,
            title: isOn ? "Hide \(noun)" : "Show \(noun)",
            group: "Style",
            keywords: keywords + [noun, "toggle"],
            symbol: symbol
        ) { set(!isOn) }
    }
}
