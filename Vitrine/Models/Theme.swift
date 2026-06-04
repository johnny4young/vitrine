import Foundation

/// A code theme is purely a **Highlight.js syntax theme** (CS-006). The theme
/// controls only the syntax colors; the code-card background is taken from the
/// highlight theme's own background (see `HighlightManager.backgroundColor(for:)`),
/// and the canvas background (gradient/solid/transparent) is configured separately.
struct Theme: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// Highlight.js theme name passed to Highlightr (e.g. "atom-one-dark").
    let hlJsTheme: String

    static let oneDark = Theme(id: "one-dark", displayName: "One Dark", hlJsTheme: "atom-one-dark")
    static let github = Theme(id: "github", displayName: "GitHub", hlJsTheme: "github")
    static let nightOwl = Theme(id: "night-owl", displayName: "Night Owl", hlJsTheme: "night-owl")
    static let dracula = Theme(id: "dracula", displayName: "Dracula", hlJsTheme: "dracula")
    static let monokai = Theme(id: "monokai", displayName: "Monokai", hlJsTheme: "monokai")
    static let solarized = Theme(
        id: "solarized", displayName: "Solarized", hlJsTheme: "solarized-dark")

    /// All bundled themes, in menu order.
    static let all: [Theme] = [.oneDark, .github, .nightOwl, .dracula, .monokai, .solarized]

    /// Looks up a theme by id, falling back to One Dark.
    static func theme(withID id: String) -> Theme {
        all.first { $0.id == id } ?? .oneDark
    }
}
