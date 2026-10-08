import AppKit
import Highlightr
import SwiftUI
import VitrineDomain

/// Theme chrome colors derived from a theme's card background.
extension HighlightManager {
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
    func themeChrome(for theme: VitrineDomain.Theme) -> ThemeChrome {
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
    func backgroundNSColor(for theme: VitrineDomain.Theme) -> NSColor {
        if let palette = theme.palette {
            return NSColor(palette.background.color)
        }
        guard let highlightr, selectBuiltInTheme(theme) else {
            return NSColor(Color(hex: "#1E1E1E"))
        }
        return highlightr.theme.themeBackgroundColor ?? NSColor(Color(hex: "#1E1E1E"))
    }

    /// Selects a bundled stylesheet without allowing Highlightr's mutable engine
    /// state to leak across renders. Highlightr returns `false` for an unavailable
    /// stylesheet and otherwise leaves the previously selected theme active. A bad
    /// catalog entry must therefore move explicitly to One Dark rather than render
    /// with whichever theme happened to run immediately before it.
    func selectBuiltInTheme(_ theme: VitrineDomain.Theme) -> Bool {
        guard let highlightr else { return false }
        let requested = theme.hlJsTheme ?? Self.fallbackBuiltInThemeName
        if highlightr.setTheme(to: requested) { return true }
        return highlightr.setTheme(to: Self.fallbackBuiltInThemeName)
    }

    /// Whether `color` is dark enough that light overlays/text read best on it,
    /// using Rec. 601 relative luminance. Converts into a known RGB space first so
    /// a catalog/pattern color cannot trap on `.redComponent` access.
    func isDark(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return true }
        let luminance =
            0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance < 0.5
    }
}
