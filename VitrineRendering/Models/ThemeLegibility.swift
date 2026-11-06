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
    nonisolated public struct Ink: Equatable, Identifiable, Sendable {
        public let id: String
        public let hex: String
        public let ratio: Double
        /// Fraction of the measured glyphs drawn in this color on this surface.
        public let share: Double
    }

    /// Everything a measurement reads, so nothing else can leave it stale, and a slider tick
    /// that can't change the result doesn't measure again. The font only finds the preview's
    /// cached tokens, since it can't change a color, so it never counts as a change.
    public struct Input: Equatable {
        private struct CacheKeyFont: Equatable {
            let font: NSFont
            static func == (_: Self, _: Self) -> Bool { true }
        }

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
        private let cacheKeyFont: CacheKeyFont
        var font: NSFont { cacheKeyFont.font }
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
            cacheKeyFont = CacheKeyFont(
                font: CodeFont.resolved(
                    family: config.fontName, size: config.fontSize, ligatures: config.fontLigatures)
            )
            let card = ThemeLegibility.cardColor(
                theme: config.theme, language: config.language, palette: config.terminalPalette)
            let isOpaque = (card?.alphaComponent ?? 0) >= 1
            backdrop = isOpaque ? nil : config.background
            showsShadow = !isOpaque && config.showShadow
        }
    }

    nonisolated static let illegibleRatio = 2.0
    nonisolated static let illegibleShare = 0.05
    nonisolated static let faintRatio = 3.0
    nonisolated static let faintShare = 0.5
    nonisolated static let majorityShare = 0.5
    nonisolated public static let threshold = Brand.Contrast.aaNormal
    static let maximumTerminalBytes = 64 * 1024
    /// Plaintext runs Highlight.js's auto-detection, which takes seconds on a large document.
    static let maximumAutoDetectedBytes = 8 * 1024

    /// Every measured color, lowest contrast first.
    public let inks: [Ink]

    /// The colors under the AA threshold.
    public var lowInks: [Ink] { inks.filter { $0.ratio < Self.threshold } }

    /// Whether enough of the text is hard to read. A few comments under AA stay quiet: most
    /// stock themes dim them on purpose.
    public var isWeak: Bool { Self.isWeak(inks) }

    nonisolated static func isWeak(_ inks: [Ink]) -> Bool {
        func share(under limit: Double) -> Double {
            inks.filter { $0.ratio < limit }.reduce(0) { $0 + $1.share }
        }
        return share(under: Self.illegibleRatio) >= Self.illegibleShare
            || share(under: Self.faintRatio) >= Self.faintShare
            || share(under: Self.threshold) > Self.majorityShare
    }

    /// Measures the input's text, or `nil` when it can't honestly report: an image capture, no
    /// measurable text, a terminal or auto-detected document too large to read cheaply, or a
    /// surface it doesn't know exactly.
    public static func measure(_ input: Input) -> ThemeLegibility? {
        guard isMeasurable(input),
            let card = cardColor(
                theme: input.theme, language: input.language, palette: input.terminalPalette),
            let surface = surface(under: card, input: input),
            let samples = samples(input, card: card)
        else { return nil }
        return ThemeLegibility(inks: samples.inks(on: surface))
    }

    /// The measured glyphs of one capture, which rate over any surface off the main actor.
    nonisolated public struct Samples: Sendable {
        struct Entry: Sendable {
            let key: String
            let color: NSColor
            let hex: String
            let band: NSColor?
            let runBackground: NSColor?
            let count: Int
        }

        let card: NSColor
        let entries: [Entry]

        /// Every ink over `surface`, the opaque color right under the text's row.
        func inks(on surface: NSColor) -> [Ink] {
            let total = entries.reduce(0) { $0 + $1.count }
            return entries.map { entry in
                var below =
                    entry.band.map { Brand.Contrast.composite($0, over: surface) } ?? surface
                if let own = entry.runBackground {
                    below = Brand.Contrast.composite(own, over: below)
                }
                let ratio = Brand.Contrast.ratio(
                    Color(nsColor: Brand.Contrast.composite(entry.color, over: below)),
                    on: Color(nsColor: below))
                return Ink(
                    id: entry.key, hex: entry.hex, ratio: ratio,
                    share: Double(entry.count) / Double(total))
            }
            .sorted { ($0.ratio, $0.id) < ($1.ratio, $1.id) }
        }

        /// Every ink over an opaque `backdrop` seen through the card.
        func inks(over backdrop: NSColor) -> [Ink] {
            inks(on: Brand.Contrast.composite(card, over: backdrop))
        }
    }

    /// The capture's glyphs whatever the canvas background, or `nil` when there is nothing
    /// `measure` could rate.
    static func samples(_ input: Input) -> Samples? {
        guard isMeasurable(input),
            let card = cardColor(
                theme: input.theme, language: input.language, palette: input.terminalPalette)
        else { return nil }
        return samples(input, card: card)
    }

    private static func isMeasurable(_ input: Input) -> Bool {
        guard !input.usesImageContent else { return false }
        if input.language == .terminal, input.code.utf8.count > maximumTerminalBytes {
            return false
        }
        return input.language != .plaintext || input.code.utf8.count <= maximumAutoDetectedBytes
    }

    private static func samples(_ input: Input, card: NSColor) -> Samples? {
        let counts = glyphCounts(in: text(of: input), input: input)
        guard counts.values.contains(where: { $0.count > 0 }) else { return nil }
        return Samples(
            card: card,
            entries: counts.map { key, count in
                Samples.Entry(
                    key: key, color: count.color, hex: count.hex, band: count.band,
                    runBackground: count.runBackground, count: count.count)
            })
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
    static func cardColor(
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
        input.language == .terminal
            ? ANSIRenderer.attributedString(
                input.code, font: input.font,
                palette: .resolved(for: input.theme, mode: input.terminalPalette),
                columns: input.terminalColumns)
            : HighlightManager.shared.attributedString(
                for: input.code, language: input.language, theme: input.theme, font: input.font)
    }

    private struct Count {
        let color: NSColor
        let hex: String
        let band: NSColor?
        let runBackground: NSColor?
        var count: Int
    }

    /// Non-whitespace glyphs per color and surface, skipping redacted rows, rows dimmed by focus,
    /// and runs with no color of their own, which take theirs from the environment. A theme or a
    /// terminal can paint a run's own background, which is then what its text sits on.
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
                    guard let color = attributes[.foregroundColor] as? NSColor,
                        let hex = hex(of: color)
                    else { return }
                    let runBackground = attributes[.backgroundColor] as? NSColor
                    let glyphs = (run.location..<(run.location + run.length))
                        .filter { string.character(at: $0) > 0x20 }.count
                    guard glyphs > 0 else { return }
                    let key = [color, surface, runBackground]
                        .map { $0.flatMap(Self.hex(of:)) ?? "" }.joined(separator: "/")
                    counts[
                        key,
                        default: Count(
                            color: color, hex: hex, band: surface, runBackground: runBackground,
                            count: 0)
                    ].count += glyphs
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
