import AppKit
import JavaScriptCore
import SwiftUI
import VitrineDomain

// MARK: - Custom theme rendering

/// Renders a custom (user-palette) theme by reusing Highlight.js for tokenization
/// and applying the user's palette colors.
///
/// ## Why a separate path
///
/// A palette is not a bundled stylesheet, so this renderer asks the shared
/// `HighlightJSEngine` to tokenize the code into Highlight.js HTML, wraps that HTML
/// with the palette's synthesized stylesheet, and lets AppKit's HTML reader produce
/// the attributed string. The result paints real, per-token palette colors over the
/// palette's own background, and — because the palette is fixed sRGB — renders the
/// same pixels on any Mac, keeping exported screenshots deterministic.
final class CustomThemeRenderer {
    private let engine: HighlightJSEngine

    init(engine: HighlightJSEngine) {
        self.engine = engine
    }

    /// Renders `code` with the user's `palette`, using `language` as the grammar
    /// hint (auto-detecting for plain text), and pins `font` so the result matches
    /// the built-in path's typography. Returns `nil` if tokenization fails so the
    /// caller can fall back to plain text.
    public func attributedString(
        for code: String, language: Language, palette: VitrineDomain.ThemePalette, font: NSFont
    ) -> NSAttributedString? {
        guard let body = highlightedHTML(code, language: language) else { return nil }
        let document =
            "<style>\(palette.highlightJSStylesheet)</style>"
            + "<pre><code class=\"hljs\">\(body)</code></pre>"
        guard let data = document.data(using: .utf8) else { return nil }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard
            let attributed = try? NSMutableAttributedString(
                data: data, options: options, documentAttributes: nil)
        else { return nil }

        // The HTML reader infers a proportional font and may leave a trailing
        // newline from the <pre>; pin the requested monospaced font over the whole
        // string and trim the stray newline so the output matches the built-in path.
        let full = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.font, value: font, range: full)
        trimTrailingNewline(attributed)
        return attributed
    }

    /// Tokenizes `code` into Highlight.js HTML (spans with `hljs-*` classes). Uses
    /// the named grammar when known and auto-detection otherwise, mirroring how
    /// Highlightr drives the engine so custom and built-in themes classify identically.
    private func highlightedHTML(_ code: String, language: Language) -> String? {
        let result: JSValue?
        if language != .plaintext,
            let named = engine.hljs.invokeMethod(
                "highlight", withArguments: [code, ["language": language.hljsName]]),
            !named.isUndefined
        {
            result = named
        } else {
            result = engine.hljs.invokeMethod("highlightAuto", withArguments: [code])
        }
        return result?.objectForKeyedSubscript("value")?.toString()
    }

    /// Removes a single trailing newline if present, matching the built-in render,
    /// which does not append one.
    private func trimTrailingNewline(_ string: NSMutableAttributedString) {
        guard string.string.hasSuffix("\n") else { return }
        string.deleteCharacters(in: NSRange(location: string.length - 1, length: 1))
    }
}
