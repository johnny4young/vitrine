import AppKit
import Highlightr

/// Wraps Highlightr (Highlight.js) to produce a syntax-highlighted
/// `NSAttributedString` for a snippet (CS-003).
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
}
