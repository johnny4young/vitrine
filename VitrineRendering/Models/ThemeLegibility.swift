import AppKit
import SwiftUI
import VitrineDomain

/// Measured WCAG contrast of a capture's visible code text against what it is drawn on.
///
/// Code sits on the theme's card, so an opaque card makes the canvas background irrelevant.
/// Only a translucent card lets it through, and then a ratio is reported only over a surface
/// that is known exactly, because a gradient or an image varies under the text.
public struct ThemeLegibility: Equatable {
    /// One text color on one surface in the capture.
    public struct Ink: Equatable, Identifiable {
        public let id: String
        public let hex: String
        public let ratio: Double
        /// Fraction of the measured glyphs drawn in this color on this surface.
        public let share: Double
    }

    /// Everything a measurement reads, so nothing else can leave it stale, and a slider tick
    /// that can't change the result doesn't measure again.
    public struct Input: Equatable {
        let code: String
        let language: Language
        let theme: Theme
        let terminalPalette: TerminalPaletteMode
        let terminalColumns: Int?
        let redactedLineRanges: [ClosedRange<Int>]
        let highlightedLineRanges: [ClosedRange<Int>]
        let focusHighlightedLines: Bool
        let diffDecorations: Bool
        let usesLineRows: Bool
        let usesImageContent: Bool
        let isLargeText: Bool
        /// `nil` and `false` under an opaque card, which hides both.
        let backdrop: VitrineDomain.BackgroundStyle?
        let showsShadow: Bool

        public init(_ config: SnapshotConfig) {
            code = config.code
            language = config.language
            theme = config.theme
            terminalPalette = config.terminalPalette
            terminalColumns = config.terminalColumns
            redactedLineRanges = config.redactedLineRanges
            highlightedLineRanges = config.highlightedLineRanges
            focusHighlightedLines = config.focusHighlightedLines
            diffDecorations = config.diffDecorations
            usesLineRows = config.usesLineRows
            usesImageContent = config.usesImageContent
            isLargeText = config.fontSize >= ThemeLegibility.largeTextSize
            let card = ThemeLegibility.cardColor(
                theme: config.theme, language: config.language, palette: config.terminalPalette)
            let isOpaque = (card?.alphaComponent ?? 0) >= 1
            backdrop = isOpaque ? nil : config.background
            showsShadow = !isOpaque && config.showShadow
        }
    }

    static let illegibleRatio = 2.0
    static let illegibleShare = 0.05
    static let faintRatio = 3.0
    static let faintShare = 0.25
    static let majorityShare = 0.5
    static let largeTextSize = 18.0
    static let maximumTerminalBytes = 64 * 1024

    /// Every measured color, lowest contrast first.
    public let inks: [Ink]
    /// The AA threshold for this capture's font size.
    public let threshold: Double

    /// The colors under the AA threshold.
    public var lowInks: [Ink] { inks.filter { $0.ratio < threshold } }

    /// Whether enough of the text is hard to read. A few comments under AA stay quiet: most
    /// stock themes dim them on purpose.
    public var isWeak: Bool {
        func share(under limit: Double) -> Double {
            inks.filter { $0.ratio < limit }.reduce(0) { $0 + $1.share }
        }
        return share(under: Self.illegibleRatio) >= Self.illegibleShare
            || share(under: min(Self.faintRatio, threshold)) >= Self.faintShare
            || share(under: threshold) > Self.majorityShare
    }

    /// Measures the input's text, or `nil` when it can't honestly report: an image capture, no
    /// measurable text, an oversized terminal, or a surface it doesn't know exactly.
    public static func measure(_ input: Input) -> ThemeLegibility? {
        guard !input.usesImageContent else { return nil }
        if input.language == .terminal, input.code.utf8.count > maximumTerminalBytes { return nil }
        guard
            let card = cardColor(
                theme: input.theme, language: input.language, palette: input.terminalPalette),
            let surface = surface(under: card, input: input)
        else { return nil }

        let counts = glyphCounts(in: text(of: input), input: input)
        let total = counts.values.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }

        let inks = counts.map { key, entry in
            let below = entry.band.map { Brand.Contrast.composite($0, over: surface) } ?? surface
            let ratio = Brand.Contrast.ratio(
                Color(nsColor: Brand.Contrast.composite(entry.color, over: below)),
                on: Color(nsColor: below))
            return Ink(
                id: key, hex: entry.hex, ratio: ratio, share: Double(entry.count) / Double(total))
        }
        return ThemeLegibility(
            inks: inks.sorted { ($0.ratio, $0.id) < ($1.ratio, $1.id) },
            threshold: input.isLargeText ? Brand.Contrast.aaLarge : Brand.Contrast.aaNormal)
    }

    /// A stock theme to offer instead, only when the same measurement says it reads.
    public static func betterTheme(for config: SnapshotConfig) -> Theme? {
        let candidate: Theme = config.theme.appearance == .light ? .github : .githubDark
        guard candidate.id != config.theme.id else { return nil }
        var alternative = config
        alternative.theme = candidate
        guard let report = measure(Input(alternative)), !report.isWeak else { return nil }
        return candidate
    }

    /// The card fill the canvas draws, in sRGB.
    fileprivate static func cardColor(
        theme: Theme, language: Language, palette: TerminalPaletteMode
    ) -> NSColor? {
        (language == .terminal
            ? ANSIPalette.resolved(for: theme, mode: palette).defaultBackground
            : HighlightManager.shared.themeChrome(for: theme).background)
            .usingColorSpace(.sRGB)
    }

    /// What the text's row sits on, or `nil` when it isn't known. Through a translucent card
    /// that takes an opaque solid and no shadow, which would also show through.
    private static func surface(under card: NSColor, input: Input) -> NSColor? {
        guard card.alphaComponent < 1 else { return card }
        guard case .solid(let color)? = input.backdrop, !input.showsShadow,
            let solid = NSColor(color.color).usingColorSpace(.sRGB), solid.alphaComponent >= 1
        else { return nil }
        return Brand.Contrast.composite(card, over: solid)
    }

    private static func text(of input: Input) -> NSAttributedString {
        // Only the colors matter here, so a font change doesn't measure again.
        let font = CodeFont.resolved(
            family: SettingsDefaults.fontName, size: SettingsDefaults.fontSize, ligatures: false)
        return input.language == .terminal
            ? ANSIRenderer.attributedString(
                input.code, font: font,
                palette: .resolved(for: input.theme, mode: input.terminalPalette),
                columns: input.terminalColumns)
            : HighlightManager.shared.attributedString(
                for: input.code, language: input.language, theme: input.theme, font: font)
    }

    private struct Count {
        let color: NSColor
        let hex: String
        let band: NSColor?
        var count: Int
    }

    /// Non-whitespace glyphs per color and surface, skipping what can't be read as text on the
    /// card: redacted rows, rows dimmed by focus, terminal runs with their own background, and
    /// runs with no color of their own, which take theirs from the environment.
    private static func glyphCounts(
        in text: NSAttributedString, input: Input
    ) -> [String: Count] {
        let redactions = LineHighlight.normalize(input.redactedLineRanges)
        let highlights = LineHighlight.normalize(input.highlightedLineRanges)
        let highlightBand = NSColor(HighlightManager.shared.lineHighlightColor(for: input.theme))
        let string = text.string as NSString
        // Past this size a document is one plain run, so its shares don't change.
        let limit = min(string.length, HighlightPolicy.maximumHighlightedByteCount)
        var counts: [String: Count] = [:]
        var line = 1
        var location = 0
        while location < limit {
            let newline = string.range(
                of: "\n", range: NSRange(location: location, length: limit - location))
            let end = newline.location == NSNotFound ? limit : newline.location
            let isHighlighted = LineHighlight.contains(highlights, line: line)
            let isDimmed = input.usesLineRows && input.focusHighlightedLines && !isHighlighted
            if !isDimmed, !LineHighlight.contains(redactions, line: line) {
                let first =
                    end > location
                    ? string.substring(with: NSRange(location: location, length: 1)).first : nil
                let band =
                    input.diffDecorations
                    ? CodeLinesView.diffBand(firstCharacter: first).map { NSColor($0) } : nil
                let surface = band ?? (isHighlighted ? highlightBand : nil)
                text.enumerateAttributes(
                    in: NSRange(location: location, length: end - location)
                ) { attributes, run, _ in
                    guard input.language != .terminal || attributes[.backgroundColor] == nil,
                        let color = attributes[.foregroundColor] as? NSColor,
                        let hex = hex(of: color)
                    else { return }
                    let glyphs = (run.location..<(run.location + run.length))
                        .filter { string.character(at: $0) > 0x20 }.count
                    guard glyphs > 0 else { return }
                    let key = "\(hex)/\(surface.flatMap(Self.hex(of:)) ?? "")"
                    counts[key, default: Count(color: color, hex: hex, band: surface, count: 0)]
                        .count += glyphs
                }
            }
            line += 1
            location = end + 1
        }
        return counts
    }

    private static func hex(of color: NSColor) -> String? {
        guard let sRGB = color.usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X%02X", Int((sRGB.redComponent * 255).rounded()),
            Int((sRGB.greenComponent * 255).rounded()), Int((sRGB.blueComponent * 255).rounded()),
            Int((sRGB.alphaComponent * 255).rounded()))
    }
}
