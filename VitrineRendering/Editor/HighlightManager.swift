import AppKit
import Highlightr
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

    static let fallbackBuiltInThemeName =
        VitrineDomain.Theme.oneDark.hlJsTheme ?? "atom-one-dark"

    let highlightr = Highlightr()
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
    struct ThemeChrome {
        let background: NSColor
        let isDark: Bool
    }
    var builtInChrome: [VitrineDomain.Theme.Source: ThemeChrome] = [:]

    /// Cache key for highlighted code. `VitrineDomain.Theme.Source` captures the immutable stylesheet name for
    /// a built-in or the complete value-typed palette for a custom theme, so changing a palette
    /// under a stable user-facing id can never return stale colors.
    ///
    /// `code` is declared last so the synthesized equality compares it last. The caches scan
    /// their recency list by equality, and the entries for one document differ only in font or
    /// theme; comparing those first rejects a non-matching entry without comparing the text.
    private struct HighlightKey: Hashable {
        let language: Language
        let themeSource: VitrineDomain.Theme.Source
        let font: NSFont
        let code: String
    }
    /// The most recent derived value for one document, kept for input the LRU caches
    /// deliberately refuse.
    ///
    /// A document between the cacheable size and the highlighting ceiling is highlighted
    /// twice per settle today: the editor asks for the attributed string, then the preview
    /// asks for the bridged one, whose first step is to highlight the same text again. On a
    /// 90 KB document that is 138 ms followed by 170 ms — a 308 ms settle against a 250 ms
    /// quiet window, so typing never catches up.
    ///
    /// Retaining every such document is what the size limit exists to prevent, but
    /// retaining exactly the **last** one costs a single document's memory regardless of
    /// how large the input band is, and that is the one every consumer in a settle asks
    /// for. A different document replaces it immediately.
    private struct LastDerived<Key: Hashable, Value> {
        private var entry: (key: Key, value: Value)?

        /// Reported through `cachedEntryCountForTesting` like any other retained value:
        /// a slot holding a document is a cache, whatever its size.
        var count: Int { entry == nil ? 0 : 1 }

        func value(forKey key: Key) -> Value? {
            guard let entry, entry.key == key else { return nil }
            return entry.value
        }

        mutating func store(_ value: Value, forKey key: Key) { entry = (key, value) }
        mutating func removeAll() { entry = nil }
    }

    private var lastHighlight = LastDerived<HighlightKey, NSAttributedString>()
    private var lastSwiftUI = LastDerived<HighlightKey, AttributedString>()
    private var lastLines = LastDerived<HighlightKey, [AttributedString]>()
    private var lastTerminal = LastDerived<TerminalKey, AttributedString>()
    private var lastTerminalLines = LastDerived<TerminalKey, [AttributedString]>()

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
        let themeSource: VitrineDomain.Theme.Source
        let font: NSFont
        let columns: Int?
        // Last, for the same reason as `HighlightKey.code`.
        let code: String
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
            language: language, themeSource: theme.source, font: font, code: code)
        if shouldCache, let cached = highlightCache.value(forKey: key) { return cached }
        if !shouldCache, let recent = lastHighlight.value(forKey: key) { return recent }

        if let palette = theme.palette {
            let fallback = plainText(code, theme: theme, font: font)
            let result =
                customRenderer?.attributedString(
                    for: code, language: language, palette: palette, font: font) ?? fallback
            Self.cache(
                result, forKey: key, code: code, representation: .attributedString,
                in: &highlightCache)
            if !shouldCache { lastHighlight.store(result, forKey: key) }
            return result
        }

        guard let highlightr, selectBuiltInTheme(theme) else {
            return plainText(code, theme: theme, font: font)
        }
        highlightr.theme.codeFont = font
        let languageHint = language == .plaintext ? nil : language.hljsName
        let highlighted =
            highlightr.highlight(code, as: languageHint, fastRender: true)
            ?? plainText(code, theme: theme, font: font)
        Self.cache(
            highlighted, forKey: key, code: code, representation: .attributedString,
            in: &highlightCache)
        if !shouldCache { lastHighlight.store(highlighted, forKey: key) }
        return highlighted
    }

    /// Highlights `code` and returns it as a SwiftUI `AttributedString`, caching the
    /// `NSAttributedString`→`AttributedString` bridge for cacheable documents so the canvas does
    /// not repeat the O(n) bridge on every `body` pass. The value is identical to bridging
    /// `attributedString(for:…)` by hand.
    public func swiftUIAttributedString(
        for code: String, language: Language, theme: VitrineDomain.Theme, font: NSFont
    ) -> AttributedString {
        let key = HighlightKey(
            language: language, themeSource: theme.source, font: font, code: code)
        guard HighlightPolicy.shouldCache(code) else {
            if let recent = lastSwiftUI.value(forKey: key) { return recent }
            let bridged = AttributedString(
                attributedString(for: code, language: language, theme: theme, font: font))
            // Only a fully highlighted result is worth keeping: the plain-text fallback
            // above the highlighting ceiling is cheap to rebuild, and retaining it would
            // hold a multi-megabyte document for no gain.
            if HighlightPolicy.mode(for: code, language: language) == .full {
                lastSwiftUI.store(bridged, forKey: key)
            }
            return bridged
        }
        let ns = attributedString(for: code, language: language, theme: theme, font: font)
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
            themeSource: theme.source, font: font, columns: columns, code: code)
        guard HighlightPolicy.shouldCache(code) else {
            if let recent = lastTerminal.value(forKey: key) { return recent }
            let rendered = render()
            lastTerminal.store(rendered, forKey: key)
            return rendered
        }
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
        let key = HighlightKey(
            language: language, themeSource: theme.source, font: font, code: code)
        guard HighlightPolicy.shouldCache(code) else {
            if let recent = lastLines.value(forKey: key) { return recent }
            let rows = Self.splitRows(bridged)
            if HighlightPolicy.mode(for: code, language: language) == .full {
                lastLines.store(rows, forKey: key)
            }
            return rows
        }
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
            themeSource: theme.source, font: font, columns: columns, code: code)
        guard HighlightPolicy.shouldCache(code) else {
            if let recent = lastTerminalLines.value(forKey: key) { return recent }
            let rows = Self.splitRows(bridged)
            lastTerminalLines.store(rows, forKey: key)
            return rows
        }
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
            + lastHighlight.count + lastSwiftUI.count + lastLines.count
            + lastTerminal.count + lastTerminalLines.count
    }

    public func resetCachesForTesting() {
        highlightCache.removeAll()
        swiftUICache.removeAll()
        terminalCache.removeAll()
        lineCache.removeAll()
        terminalLineCache.removeAll()
        lastHighlight.removeAll()
        lastSwiftUI.removeAll()
        lastLines.removeAll()
        lastTerminal.removeAll()
        lastTerminalLines.removeAll()
        builtInChrome.removeAll()
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

    /// The Highlight.js stylesheet names bundled with the engine, or `nil` if the
    /// engine is unavailable. This is the authoritative contract for built-in
    /// themes: `setTheme(to:)` otherwise fails without replacing the current theme.
    public func supportedThemeNames() -> [String]? {
        highlightr?.availableThemes()
    }
}
