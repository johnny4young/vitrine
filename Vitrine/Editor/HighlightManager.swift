import AppKit
import Highlightr
import SwiftUI

/// Wraps Highlightr (Highlight.js) to produce a syntax-highlighted
/// `NSAttributedString` and the theme's own background color (CS-003/006).
///
/// A single shared instance avoids re-creating the (heavy) JS context.
final class HighlightManager {
    static let shared = HighlightManager()

    private let highlightr = Highlightr()

    private init() {}

    /// Highlights `code` for `language`, using `theme`'s Highlight.js theme and
    /// the given `font`. Falls back to plain monospaced text if unavailable.
    func attributedString(
        for code: String,
        language: Language,
        theme: Theme,
        font: NSFont
    ) -> NSAttributedString {
        let fallback = NSAttributedString(
            string: code,
            attributes: [.font: font, .foregroundColor: NSColor.textColor]
        )
        guard let highlightr else { return fallback }

        highlightr.setTheme(to: theme.hlJsTheme)
        highlightr.theme.codeFont = font

        let languageHint = language == .plaintext ? nil : language.hljsName
        return highlightr.highlight(code, as: languageHint, fastRender: true) ?? fallback
    }

    /// The code-card background for a theme, taken from the Highlight.js theme
    /// itself — so a theme is purely a syntax theme, not a hand-picked color (CS-006).
    func backgroundColor(for theme: Theme) -> Color {
        guard let highlightr else { return Color(hex: "#1E1E1E") }
        highlightr.setTheme(to: theme.hlJsTheme)
        if let nsColor = highlightr.theme.themeBackgroundColor {
            return Color(nsColor: nsColor)
        }
        return Color(hex: "#1E1E1E")
    }
}
