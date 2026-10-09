import SwiftUI
import VitrineDomain
import VitrineRendering

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

    /// One "Apply <theme>" command per built-in and custom theme, tagged with its
    /// appearance so "dark" / "light" surface the right ones.
    private var themeCommands: [EditorCommand] {
        themes.allThemes.map { theme in
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
                isOn: settings.style.showLineNumbers,
                set: { settings.style.showLineNumbers = $0 }),
            toggle(
                id: "toggle.shadow",
                offTitle: String(localized: "Show drop shadow"),
                onTitle: String(localized: "Hide drop shadow"),
                symbol: "shadow",
                isOn: settings.style.showShadow, set: { settings.style.showShadow = $0 }),
            toggle(
                id: "toggle.chrome",
                offTitle: String(localized: "Show window chrome"),
                onTitle: String(localized: "Hide window chrome"),
                symbol: "macwindow",
                keywords: ["chrome", "traffic lights", "dots"],
                isOn: settings.style.showChrome, set: { settings.style.showChrome = $0 }),
            toggle(
                id: "toggle.wrap",
                offTitle: String(localized: "Wrap long lines"),
                onTitle: String(localized: "Don't wrap long lines"),
                symbol: "text.wrap",
                keywords: ["soft wrap", "long lines"],
                isOn: settings.style.wrapsLongLines,
                set: { settings.style.wrapColumns = $0 ? SettingsDefaults.wrapColumns : nil }),
            toggle(
                id: "toggle.ligatures",
                offTitle: String(localized: "Enable font ligatures"),
                onTitle: String(localized: "Disable font ligatures"),
                symbol: "textformat",
                isOn: settings.style.fontLigatures,
                set: { settings.style.fontLigatures = $0 }),
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
    var exportCommands: [EditorCommand] {
        exportCommands(
            for: PaletteExport.available(
                hasRenderableContent: settings.hasRenderableContent,
                usesImageContent: settings.style.usesImageContent))
    }

    func exportCommands(for exports: [PaletteExport]) -> [EditorCommand] {
        let group = String(localized: "Export")
        return exports.map { export in
            switch export {
            case .copy:
                EditorCommand(
                    id: "export.copy", title: VitrineCommand.copyImage.title, group: group,
                    keywords: ["png", "clipboard"],
                    symbol: VitrineCommand.copyImage.systemImageName
                ) { copyImage() }
            case .save:
                EditorCommand(
                    id: "export.save", title: VitrineCommand.saveImage.title, group: group,
                    keywords: ["png", "pdf", "heic", "disk"], symbol: "square.and.arrow.down"
                ) { saveImage() }
            case .documentation:
                EditorCommand(
                    id: "export.documentation",
                    title: String(localized: "Export for Documentation"), group: group,
                    keywords: ["docs", "package", "markdown", "html"], symbol: "folder"
                ) { exportSheet = .documentationExport }
            case .markdown:
                EditorCommand(
                    id: "export.markdown", title: VitrineCommand.copyMarkdown.title, group: group,
                    keywords: ["md", "fenced", "readme"],
                    symbol: VitrineCommand.copyMarkdown.systemImageName
                ) { copyMarkdown() }
            }
        }
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

/// The palette's export rows. Like the toolbar, nothing is offered for an empty
/// editor and Markdown only for code.
enum PaletteExport: CaseIterable {
    case copy
    case save
    case documentation
    case markdown

    static func available(hasRenderableContent: Bool, usesImageContent: Bool) -> [PaletteExport] {
        guard hasRenderableContent else { return [] }
        return usesImageContent ? [.copy, .save, .documentation] : allCases
    }
}
