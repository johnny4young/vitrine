import AppKit
import Highlightr
import JavaScriptCore
import SwiftUI
import VitrineDomain

// MARK: - Custom theme rendering

/// Renders a custom (user-palette) theme by reusing Highlight.js for tokenization
/// and applying the user's palette colors.
///
/// ## Why a separate path
///
/// Highlightr can only load a theme from a stylesheet **bundled** with it; its CSS
/// parser has no public entry point for injecting a user stylesheet. Rather than
/// fork the dependency, this renderer loads the very same bundled `highlight.min.js`
/// into its own `JSContext`, asks it to tokenize the code into Highlight.js HTML
/// (so token classification is identical to the built-in themes), wraps that HTML
/// with the palette's synthesized stylesheet, and lets AppKit's HTML reader produce
/// the attributed string. The result paints real, per-token palette colors over the
/// palette's own background, and — because the palette is fixed sRGB — renders the
/// same pixels on any Mac, keeping exported screenshots deterministic.
///
/// If the engine cannot be loaded (an unexpected packaging problem), the renderer is
/// `nil` and the caller falls back to plain monospaced text.
final class CustomThemeRenderer {
    private let context: JSContext
    private let hljs: JSValue

    /// Loads the bundled Highlight.js engine into a fresh context, or fails if the
    /// resource cannot be found or evaluated.
    init?() {
        guard let context = JSContext(),
            let scriptURL = Self.highlightScriptURL,
            let script = try? String(contentsOf: scriptURL, encoding: .utf8)
        else { return nil }
        context.evaluateScript(script)
        guard let hljs = context.objectForKeyedSubscript("hljs"), !hljs.isUndefined else {
            return nil
        }
        self.context = context
        self.hljs = hljs
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
            let named = hljs.invokeMethod(
                "highlight", withArguments: [code, ["language": language.hljsName]]),
            !named.isUndefined
        {
            result = named
        } else {
            result = hljs.invokeMethod("highlightAuto", withArguments: [code])
        }
        return result?.objectForKeyedSubscript("value")?.toString()
    }

    /// Removes a single trailing newline if present, matching the built-in render,
    /// which does not append one.
    private func trimTrailingNewline(_ string: NSMutableAttributedString) {
        guard string.string.hasSuffix("\n") else { return }
        string.deleteCharacters(in: NSRange(location: string.length - 1, length: 1))
    }

    /// Locates the bundled `highlight.min.js` that ships inside Highlightr's resource
    /// bundle, searching the app's nested package bundle first and falling back to
    /// the main bundle (covering both the app and a unit-test host).
    private static var highlightScriptURL: URL? {
        let resource = "highlight.min"
        let ext = "js"
        // Highlightr's SwiftPM resources land in "Highlightr_Highlightr.bundle"
        // nested under the host's Resources.
        let nestedBundleNames = ["Highlightr_Highlightr", "Highlightr"]
        for base in [Bundle.main] {
            if let url = base.url(forResource: resource, withExtension: ext) { return url }
            for name in nestedBundleNames {
                if let nestedURL = base.url(forResource: name, withExtension: "bundle"),
                    let nested = Bundle(url: nestedURL),
                    let url = nested.url(forResource: resource, withExtension: ext)
                {
                    return url
                }
            }
        }
        return nil
    }
}
