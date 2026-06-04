import AppKit
import Highlightr
import JavaScriptCore
import SwiftUI

/// Wraps Highlightr (Highlight.js) to produce a syntax-highlighted
/// `NSAttributedString` and the theme's own background color (CS-003/006).
///
/// Built-in themes render on Highlightr's fast path with a bundled stylesheet. A
/// **custom** theme (CS-031) carries its own `ThemePalette` instead of a bundled
/// stylesheet name, so it is rendered through `CustomThemeRenderer`, which reuses
/// the same bundled Highlight.js engine for tokenization but paints the user's
/// palette colors. The built-in path is left untouched, so default output is
/// byte-for-byte unchanged.
///
/// A single shared instance avoids re-creating the (heavy) JS context.
final class HighlightManager {
    static let shared = HighlightManager()

    private let highlightr = Highlightr()
    /// Renders custom (user-palette) themes; created lazily so the extra JS context
    /// is only spun up once a custom theme is actually used.
    private lazy var customRenderer = CustomThemeRenderer()

    private init() {}

    /// Highlights `code` for `language`, using `theme` and the given `font`. Falls
    /// back to plain monospaced text if highlighting is unavailable.
    ///
    /// A built-in theme uses Highlightr directly; a custom theme (CS-031) is
    /// rendered by `CustomThemeRenderer` from its palette, with the same plain-text
    /// fallback so an unavailable engine never crashes the render.
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

        if let palette = theme.palette {
            return customRenderer?.attributedString(
                for: code, language: language, palette: palette, font: font) ?? fallback
        }

        guard let highlightr else { return fallback }
        highlightr.setTheme(to: theme.hlJsTheme ?? Theme.oneDark.hlJsTheme ?? "atom-one-dark")
        highlightr.theme.codeFont = font

        let languageHint = language == .plaintext ? nil : language.hljsName
        return highlightr.highlight(code, as: languageHint, fastRender: true) ?? fallback
    }

    /// The Highlight.js language identifiers the bundled engine recognizes, or
    /// `nil` if the engine is unavailable (CS-052).
    ///
    /// This is the registration list `highlight(_:as:)` matches an id against
    /// before falling back to auto-detection, so it is the authoritative check that
    /// an advertised language is actually supported rather than silently
    /// plain-texted. Aliases (e.g. TOML → `ini`) are resolved by the engine but are
    /// not listed here, so callers compare against the resolving id.
    func supportedLanguageNames() -> [String]? {
        highlightr?.supportedLanguages()
    }

    /// The code-card background for a theme (CS-006/031).
    ///
    /// For a built-in theme this is taken from the Highlight.js stylesheet itself —
    /// so a built-in stays a pure syntax theme, not a hand-picked color. For a custom
    /// theme it is the palette's own `background`, resolved with no engine round-trip
    /// so it is fully deterministic.
    func backgroundColor(for theme: Theme) -> Color {
        Color(nsColor: backgroundNSColor(for: theme))
    }

    /// A neutral foreground color for gutter line numbers that stays legible on a
    /// theme's own card background (CS-021).
    ///
    /// Highlight.js themes expose only a background color, not a default text
    /// color, so the gutter color is derived from the background's luminance:
    /// near-white on a dark theme, near-black on a light theme. Callers dim it
    /// further so the numbers read as chrome beside the code.
    func gutterForegroundColor(for theme: Theme) -> Color {
        isDark(backgroundNSColor(for: theme)) ? .white : .black
    }

    /// The band color drawn behind a highlighted (selected) code row (CS-021).
    ///
    /// The tint is luminance-aware so a selected line is visible in both light and
    /// dark themes: a translucent white wash lifts a dark theme's row, a
    /// translucent black wash deepens a light theme's row. Because the band sits on
    /// the theme's opaque card background — not the canvas background — it stays
    /// correct even when the canvas background is transparent (CS-024).
    func lineHighlightColor(for theme: Theme) -> Color {
        let background = backgroundNSColor(for: theme)
        return isDark(background)
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.07)
    }

    /// The fill color for a metadata badge/chip drawn in the header, tinted so it
    /// reads as a subtle pill on the theme's own card background (CS-022).
    ///
    /// Like the line-highlight band, the tint is luminance-aware (a translucent
    /// white wash on a dark theme, a translucent black wash on a light theme) and
    /// sits on the opaque card background, so it stays legible even when the canvas
    /// background is transparent (CS-024).
    func metadataBadgeColor(for theme: Theme) -> Color {
        let background = backgroundNSColor(for: theme)
        return isDark(background)
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.06)
    }

    /// The theme's background as an `NSColor`.
    ///
    /// A custom theme (CS-031) resolves straight to its palette background — no
    /// engine call, so it is deterministic. A built-in theme reads its background
    /// from the bundled stylesheet, with a documented dark fallback if Highlightr
    /// cannot supply one.
    private func backgroundNSColor(for theme: Theme) -> NSColor {
        if let palette = theme.palette {
            return NSColor(palette.background.color)
        }
        guard let highlightr else { return NSColor(Color(hex: "#1E1E1E")) }
        highlightr.setTheme(to: theme.hlJsTheme ?? Theme.oneDark.hlJsTheme ?? "atom-one-dark")
        return highlightr.theme.themeBackgroundColor ?? NSColor(Color(hex: "#1E1E1E"))
    }

    /// Whether `color` is dark enough that light overlays/text read best on it,
    /// using Rec. 601 relative luminance. Converts into a known RGB space first so
    /// a catalog/pattern color cannot trap on `.redComponent` access.
    private func isDark(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return true }
        let luminance =
            0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance < 0.5
    }
}

// MARK: - Custom theme rendering (CS-031)

/// Renders a custom (user-palette) theme by reusing Highlight.js for tokenization
/// and applying the user's palette colors (CS-031).
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
/// same pixels on any Mac, keeping exported screenshots deterministic (CS-031).
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
    func attributedString(
        for code: String, language: Language, palette: ThemePalette, font: NSFont
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
