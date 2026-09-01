import AppKit
import Highlightr
import JavaScriptCore
import SwiftUI
import VitrineDomain

/// Wraps Highlightr (Highlight.js) to produce a syntax-highlighted
/// `NSAttributedString` and the theme's own background color.
///
/// Built-in themes render on Highlightr's fast path with a bundled stylesheet. A
/// **custom** theme carries its own `VitrineDomain.ThemePalette` instead of a bundled
/// stylesheet name, so it is rendered through `CustomThemeRenderer`, which reuses
/// the same bundled Highlight.js engine for tokenization but paints the user's
/// palette colors. The built-in path is left untouched, so default output is
/// byte-for-byte unchanged.
///
/// A single shared instance avoids re-creating the (heavy) JS context.
public final class HighlightManager {
    public static let shared = HighlightManager()

    private let highlightr = Highlightr()
    /// Renders custom (user-palette) themes; created lazily so the extra JS context
    /// is only spun up once a custom theme is actually used.
    private lazy var customRenderer = CustomThemeRenderer()

    /// Per-built-in-theme cached chrome (background color + luminance), derived from the
    /// Highlight.js stylesheet. The four color accessors all need only this, so resolving
    /// it once per theme avoids re-running `setTheme` (a full CSS reparse) ~5× per canvas
    /// render — `body` re-runs on every keystroke. The cached value is identical to what the
    /// uncached path returns, so output is byte-for-byte unchanged. Only **built-in** themes
    /// are cached (the immutable stylesheet source is a stable key); a custom theme's palette can
    /// change under a stable id, so it resolves directly (and is cheap — no engine call).
    private struct ThemeChrome {
        let background: NSColor
        let isDark: Bool
    }
    private var builtInChrome: [VitrineDomain.Theme.Source: ThemeChrome] = [:]

    /// Cache key for highlighted code. `VitrineDomain.Theme.Source` captures the immutable stylesheet name for
    /// a built-in or the complete value-typed palette for a custom theme, so changing a palette
    /// under a stable user-facing id can never return stale colors.
    private struct HighlightKey: Hashable {
        let code: String
        let language: Language
        let themeSource: VitrineDomain.Theme.Source
        let font: NSFont
    }
    private var highlightCache = CostLimitedLRUCache<HighlightKey, NSAttributedString>(
        totalCostLimit: HighlightPolicy.perRepresentationCostLimit,
        countLimit: HighlightPolicy.countLimit)

    /// Cache of the **bridged** SwiftUI `AttributedString`. The
    /// `AttributedString(nsAttributedString)` bridge is an O(n) run/attribute
    /// walk, and the canvas re-derives it on every `body` pass (a keystroke or any
    /// inspector tweak). Custom and built-in themes share the value-safe key above.
    private var swiftUICache = CostLimitedLRUCache<HighlightKey, AttributedString>(
        totalCostLimit: HighlightPolicy.perRepresentationCostLimit,
        countLimit: HighlightPolicy.countLimit)

    /// Cache of the bridged terminal (ANSI) `AttributedString`. A terminal capture
    /// otherwise gets fully re-parsed and re-emulated on every `body` pass. Custom
    /// themes include their value-typed source in the key, so edits cannot return stale output.
    private struct TerminalKey: Hashable {
        let code: String
        let themeSource: VitrineDomain.Theme.Source
        let font: NSFont
        let columns: Int?
    }
    private var terminalCache = CostLimitedLRUCache<TerminalKey, AttributedString>(
        totalCostLimit: HighlightPolicy.perRepresentationCostLimit,
        countLimit: HighlightPolicy.countLimit)

    /// Cache of the row-split `[AttributedString]`. The gutter/diff
    /// layout slices the highlighted document into one `AttributedString` per line — a
    /// character-by-character index walk that rebuilt on every `body` pass. Cached on
    /// the same cheap keys as the bridge above (built-in, custom, and terminal), so a
    /// re-render that didn't change the code/theme/font reuses the split instead of
    /// re-walking. The value is identical to splitting the bridged string by hand.
    private var lineCache = CostLimitedLRUCache<HighlightKey, [AttributedString]>(
        totalCostLimit: HighlightPolicy.perRepresentationCostLimit,
        countLimit: HighlightPolicy.countLimit)
    private var terminalLineCache = CostLimitedLRUCache<TerminalKey, [AttributedString]>(
        totalCostLimit: HighlightPolicy.perRepresentationCostLimit,
        countLimit: HighlightPolicy.countLimit)

    private init() {}

    /// Pays the syntax highlighter's one-time cold start ahead of the user's first
    /// capture.
    ///
    /// `Highlightr` creates its JavaScriptCore engine and parses the theme CSS lazily
    /// on the first `highlight` call — a cost real enough that `PerformanceTests`
    /// discards a warm-up pass. A user whose very first interaction is the ⇧⌘S quick
    /// capture would otherwise eat that cold start inside the gesture the product sells
    /// as "instant". Running one tiny highlight in a low-priority task after launch
    /// moves the cost off that path. Idempotent and cheap on a warm engine (a cache
    /// hit), so a redundant call is harmless. Never throws — a missing engine (the
    /// fallback path) just no-ops.
    public func prewarm() {
        let font = CodeFont.resolved(family: CodeFont.default, size: 14, ligatures: false)
        _ = attributedString(for: "let x = 0", language: .swift, theme: .oneDark, font: font)
    }

    /// Highlights `code` for `language`, using `theme` and the given `font`. Falls
    /// back to plain monospaced text if highlighting is unavailable. Built-in themes
    /// use Highlightr; custom themes use `CustomThemeRenderer` with their palette.
    public func attributedString(
        for code: String,
        language: Language,
        theme: VitrineDomain.Theme,
        font: NSFont
    ) -> NSAttributedString {
        guard HighlightPolicy.mode(for: code, language: language) == .full else {
            return plainText(code, theme: theme, font: font)
        }

        let shouldCache = HighlightPolicy.shouldCache(code)
        let key = HighlightKey(
            code: code, language: language, themeSource: theme.source, font: font)
        if shouldCache, let cached = highlightCache.value(forKey: key) { return cached }

        if let palette = theme.palette {
            let fallback = plainText(code, theme: theme, font: font)
            let result =
                customRenderer?.attributedString(
                    for: code, language: language, palette: palette, font: font) ?? fallback
            Self.cache(
                result, forKey: key, code: code, representation: .attributedString,
                in: &highlightCache)
            return result
        }

        guard let highlightr else { return plainText(code, theme: theme, font: font) }
        highlightr.setTheme(
            to: theme.hlJsTheme ?? VitrineDomain.Theme.oneDark.hlJsTheme ?? "atom-one-dark")
        highlightr.theme.codeFont = font
        let languageHint = language == .plaintext ? nil : language.hljsName
        let highlighted =
            highlightr.highlight(code, as: languageHint, fastRender: true)
            ?? plainText(code, theme: theme, font: font)
        Self.cache(
            highlighted, forKey: key, code: code, representation: .attributedString,
            in: &highlightCache)
        return highlighted
    }

    /// Highlights `code` and returns it as a SwiftUI `AttributedString`, caching the
    /// `NSAttributedString`→`AttributedString` bridge for cacheable documents so the canvas does
    /// not repeat the O(n) bridge on every `body` pass. The value is identical to bridging
    /// `attributedString(for:…)` by hand.
    public func swiftUIAttributedString(
        for code: String, language: Language, theme: VitrineDomain.Theme, font: NSFont
    ) -> AttributedString {
        let ns = attributedString(for: code, language: language, theme: theme, font: font)
        guard HighlightPolicy.shouldCache(code) else { return AttributedString(ns) }
        let key = HighlightKey(
            code: code, language: language, themeSource: theme.source, font: font)
        if let cached = swiftUICache.value(forKey: key) { return cached }
        let bridged = AttributedString(ns)
        Self.cache(
            bridged, forKey: key, code: code, representation: .swiftUIAttributedString,
            in: &swiftUICache)
        return bridged
    }

    /// Renders terminal (ANSI) `code` as a SwiftUI `AttributedString` in `theme`'s palette,
    /// caching the parse-emulate-and-bridge result for cacheable captures. The
    /// value is identical to bridging `ANSIRenderer.attributedString(…)` by hand.
    public func terminalAttributedString(
        for code: String, theme: VitrineDomain.Theme, font: NSFont, columns: Int?
    ) -> AttributedString {
        let palette = ANSIPalette.forTheme(theme)
        let render = {
            AttributedString(
                ANSIRenderer.attributedString(
                    code, font: font, palette: palette, columns: columns))
        }
        let key = TerminalKey(
            code: code, themeSource: theme.source, font: font, columns: columns)
        guard HighlightPolicy.shouldCache(code) else { return render() }
        if let cached = terminalCache.value(forKey: key) { return cached }
        let bridged = render()
        Self.cache(
            bridged, forKey: key, code: code, representation: .terminalAttributedString,
            in: &terminalCache)
        return bridged
    }

    /// The highlighted code, split into one `AttributedString` per line and cached for
    /// the gutter/diff row layout. Serves the same rows a fresh
    /// `LineSplitter.attributedLines` of `swiftUIAttributedString(…)` would — the empty
    /// document still yields a single (empty) row so the layout never collapses.
    public func swiftUIAttributedLines(
        for code: String, language: Language, theme: VitrineDomain.Theme, font: NSFont
    ) -> [AttributedString] {
        let bridged = swiftUIAttributedString(
            for: code, language: language, theme: theme, font: font)
        guard HighlightPolicy.shouldCache(code) else { return Self.splitRows(bridged) }
        let key = HighlightKey(
            code: code, language: language, themeSource: theme.source, font: font)
        if let cached = lineCache.value(forKey: key) { return cached }
        let lines = Self.splitRows(bridged)
        Self.cache(
            lines, forKey: key, code: code, representation: .attributedLines,
            in: &lineCache)
        return lines
    }

    /// The terminal (ANSI) render, split into rows and cached — the terminal
    /// analogue of `swiftUIAttributedLines`, for a terminal capture shown with a gutter.
    public func terminalAttributedLines(
        for code: String, theme: VitrineDomain.Theme, font: NSFont, columns: Int?
    ) -> [AttributedString] {
        let bridged = terminalAttributedString(
            for: code, theme: theme, font: font, columns: columns)
        let key = TerminalKey(
            code: code, themeSource: theme.source, font: font, columns: columns)
        guard HighlightPolicy.shouldCache(code) else { return Self.splitRows(bridged) }
        if let cached = terminalLineCache.value(forKey: key) { return cached }
        let lines = Self.splitRows(bridged)
        Self.cache(
            lines, forKey: key, code: code, representation: .terminalAttributedLines,
            in: &terminalLineCache)
        return lines
    }

    /// Splits `attributed` into row lines, guarding the empty document to a single
    /// empty row so the gutter/highlight always has something to align to.
    private static func splitRows(_ attributed: AttributedString) -> [AttributedString] {
        let split = LineSplitter.attributedLines(of: attributed)
        return split.isEmpty ? [AttributedString()] : split
    }

    /// A legible, one-run fallback for documents too large to tokenize interactively or for an
    /// unavailable highlighting engine. Custom themes provide their exact foreground; built-ins
    /// derive a neutral foreground from the actual stylesheet background.
    private func plainText(
        _ code: String, theme: VitrineDomain.Theme, font: NSFont
    ) -> NSAttributedString {
        let foreground: NSColor
        if let palette = theme.palette {
            foreground = NSColor(palette.foreground.color)
        } else {
            foreground =
                themeChrome(for: theme).isDark
                ? NSColor(white: 0.92, alpha: 1)
                : NSColor(white: 0.12, alpha: 1)
        }
        return NSAttributedString(
            string: code, attributes: [.font: font, .foregroundColor: foreground])
    }

    /// Test-only observability without exposing cache contents or coupling behavior to identity.
    public var cachedEntryCountForTesting: Int {
        highlightCache.metrics.count + swiftUICache.metrics.count + terminalCache.metrics.count
            + lineCache.metrics.count + terminalLineCache.metrics.count
    }

    public func resetCachesForTesting() {
        highlightCache.removeAll()
        swiftUICache.removeAll()
        terminalCache.removeAll()
        lineCache.removeAll()
        terminalLineCache.removeAll()
    }

    /// Retains a derived value only for screenshot-sized source. Every representation has an
    /// independent cost budget and deterministic LRU eviction; medium/large documents bypass it.
    private static func cache<Key: Hashable, Value>(
        _ value: Value, forKey key: Key, code: String,
        representation: HighlightPolicy.Representation,
        in cache: inout CostLimitedLRUCache<Key, Value>
    ) {
        guard HighlightPolicy.shouldCache(code) else { return }
        cache.insert(
            value, forKey: key,
            cost: HighlightPolicy.cacheCost(for: code, representation: representation))
    }

    /// The Highlight.js language identifiers the bundled engine recognizes, or
    /// `nil` if the engine is unavailable.
    ///
    /// This is the registration list `highlight(_:as:)` matches an id against
    /// before falling back to auto-detection, so it is the authoritative check that
    /// an advertised language is actually supported rather than silently
    /// plain-texted. Aliases (e.g. TOML → `ini`) are resolved by the engine but are
    /// not listed here, so callers compare against the resolving id.
    public func supportedLanguageNames() -> [String]? {
        highlightr?.supportedLanguages()
    }

    /// The code-card background for a theme.
    ///
    /// For a built-in theme this is taken from the Highlight.js stylesheet itself —
    /// so a built-in stays a pure syntax theme, not a hand-picked color. For a custom
    /// theme it is the palette's own `background`, resolved with no engine round-trip
    /// so it is fully deterministic.
    public func backgroundColor(for theme: VitrineDomain.Theme) -> Color {
        Color(nsColor: themeChrome(for: theme).background)
    }

    /// A neutral foreground color for gutter line numbers that stays legible on a
    /// theme's own card background.
    ///
    /// Highlight.js themes expose only a background color, not a default text
    /// color, so the gutter color is derived from the background's luminance:
    /// near-white on a dark theme, near-black on a light theme. Callers dim it
    /// further so the numbers read as chrome beside the code.
    public func gutterForegroundColor(for theme: VitrineDomain.Theme) -> Color {
        themeChrome(for: theme).isDark ? .white : .black
    }

    /// The band color drawn behind a highlighted (selected) code row.
    ///
    /// The tint is luminance-aware so a selected line is visible in both light and
    /// dark themes: a translucent white wash lifts a dark theme's row, a
    /// translucent black wash deepens a light theme's row. Because the band sits on
    /// the theme's opaque card background — not the canvas background — it stays
    /// correct even when the canvas background is transparent.
    public func lineHighlightColor(for theme: VitrineDomain.Theme) -> Color {
        themeChrome(for: theme).isDark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.07)
    }

    /// The fill color for a metadata badge/chip drawn in the header, tinted so it
    /// reads as a subtle pill on the theme's own card background.
    ///
    /// Like the line-highlight band, the tint is luminance-aware (a translucent
    /// white wash on a dark theme, a translucent black wash on a light theme) and
    /// sits on the opaque card background, so it stays legible even when the canvas
    /// background is transparent.
    public func metadataBadgeColor(for theme: VitrineDomain.Theme) -> Color {
        themeChrome(for: theme).isDark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.06)
    }

    /// The theme's chrome (background + luminance), served from `builtInChrome` for a
    /// built-in theme and resolved directly for a custom one (its palette can change under
    /// a stable id, and resolving it is cheap — no engine call).
    private func themeChrome(for theme: VitrineDomain.Theme) -> ThemeChrome {
        if theme.palette != nil {
            let background = backgroundNSColor(for: theme)
            return ThemeChrome(background: background, isDark: isDark(background))
        }
        if let cached = builtInChrome[theme.source] { return cached }
        let background = backgroundNSColor(for: theme)
        let chrome = ThemeChrome(background: background, isDark: isDark(background))
        builtInChrome[theme.source] = chrome
        return chrome
    }

    /// The theme's background as an `NSColor`.
    ///
    /// A custom theme resolves straight to its palette background — no
    /// engine call, so it is deterministic. A built-in theme reads its background
    /// from the bundled stylesheet, with a documented dark fallback if Highlightr
    /// cannot supply one.
    private func backgroundNSColor(for theme: VitrineDomain.Theme) -> NSColor {
        if let palette = theme.palette {
            return NSColor(palette.background.color)
        }
        guard let highlightr else { return NSColor(Color(hex: "#1E1E1E")) }
        highlightr.setTheme(
            to: theme.hlJsTheme ?? VitrineDomain.Theme.oneDark.hlJsTheme ?? "atom-one-dark")
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
