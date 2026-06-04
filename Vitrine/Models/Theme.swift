import SwiftUI

/// A code theme: display metadata plus the Highlight.js theme name and the
/// background color drawn behind the code (CS-006).
struct Theme: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// Highlight.js theme name passed to Highlightr (e.g. "atom-one-dark").
    let hlJsTheme: String
    /// Background behind the code card.
    let background: Color

    static let oneDark = Theme(
        id: "one-dark", displayName: "One Dark",
        hlJsTheme: "atom-one-dark", background: Color(hex: "#282C34"))
    static let github = Theme(
        id: "github", displayName: "GitHub",
        hlJsTheme: "github", background: Color(hex: "#FFFFFF"))
    static let nightOwl = Theme(
        id: "night-owl", displayName: "Night Owl",
        hlJsTheme: "night-owl", background: Color(hex: "#011627"))
    static let dracula = Theme(
        id: "dracula", displayName: "Dracula",
        hlJsTheme: "dracula", background: Color(hex: "#282A36"))
    static let monokai = Theme(
        id: "monokai", displayName: "Monokai",
        hlJsTheme: "monokai", background: Color(hex: "#272822"))
    static let solarized = Theme(
        id: "solarized", displayName: "Solarized",
        hlJsTheme: "solarized-dark", background: Color(hex: "#002B36"))

    /// All bundled themes, in menu order.
    static let all: [Theme] = [.oneDark, .github, .nightOwl, .dracula, .monokai, .solarized]

    /// Looks up a theme by id, falling back to One Dark.
    static func theme(withID id: String) -> Theme {
        all.first { $0.id == id } ?? .oneDark
    }
}
