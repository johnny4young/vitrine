import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import Vitrine

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "VitrineLineNumberTests-\(UUID().uuidString)")!
}

// MARK: - Line-range parser

@Suite("LineHighlight parser")
struct LineHighlightParserTests {
    @Test func parsesASingleLine() {
        #expect(LineHighlight.parse("7") == [7...7])
    }

    @Test func parsesAHyphenatedRange() {
        #expect(LineHighlight.parse("7-9") == [7...9])
    }

    @Test func parsesMixedLinesAndRanges() {
        #expect(LineHighlight.parse("3, 7-9, 12") == [3...3, 7...9, 12...12])
    }

    @Test func toleratesWhitespaceAndNewlinesAndBlanks() {
        // Spaces around values and separators, stray commas, and newlines are all
        // forgiven (CS-021 / CS-050 spirit).
        #expect(LineHighlight.parse("  3 ,, 7 - 9 \n 12 ") == [3...3, 7...9, 12...12])
    }

    @Test func normalizesAReversedRange() {
        // "9-7" means the same selection as "7-9".
        #expect(LineHighlight.parse("9-7") == [7...9])
    }

    @Test func dropsZeroNegativeAndNonNumericFragments() {
        // Lines are 1-based, so 0 and negatives are meaningless; letters are junk.
        // Each bad fragment is skipped without failing the whole parse.
        #expect(LineHighlight.parse("0") == [])
        #expect(LineHighlight.parse("-4") == [])
        #expect(LineHighlight.parse("abc") == [])
        #expect(LineHighlight.parse("1-2-3") == [])
        #expect(LineHighlight.parse("5, oops, 8") == [5...5, 8...8])
    }

    @Test func emptyStringParsesToNoRanges() {
        #expect(LineHighlight.parse("") == [])
        #expect(LineHighlight.parse("   ") == [])
    }

    @Test func mergesOverlappingRanges() {
        #expect(LineHighlight.parse("3-5, 4-7") == [3...7])
    }

    @Test func mergesAdjacentRanges() {
        // Touching ranges collapse so the selection has one canonical shape.
        #expect(LineHighlight.parse("1-2, 3-3") == [1...3])
        #expect(LineHighlight.parse("1, 2, 3") == [1...3])
    }

    @Test func sortsOutOfOrderInput() {
        #expect(LineHighlight.parse("12, 3, 7-9") == [3...3, 7...9, 12...12])
    }

    @Test func containsChecksMembership() {
        let ranges = LineHighlight.parse("3, 7-9")
        #expect(LineHighlight.contains(ranges, line: 3))
        #expect(LineHighlight.contains(ranges, line: 8))
        #expect(!LineHighlight.contains(ranges, line: 4))
        #expect(!LineHighlight.contains(ranges, line: 10))
    }
}

@Suite("LineHighlight describe / round-trip")
struct LineHighlightDescribeTests {
    @Test func describesSingleLinesAndRanges() {
        #expect(LineHighlight.describe([3...3, 7...9, 12...12]) == "3, 7-9, 12")
    }

    @Test func describeNormalizesBeforePrinting() {
        // Unsorted, overlapping input still prints the canonical string.
        #expect(LineHighlight.describe([7...9, 3...3, 8...8]) == "3, 7-9")
    }

    @Test func describeOfEmptyIsEmptyString() {
        #expect(LineHighlight.describe([]) == "")
    }

    @Test func parseDescribeRoundTripsCanonicalForm() {
        for spec in ["3, 7-9, 12", "1-3", "5", "10, 20-22"] {
            let ranges = LineHighlight.parse(spec)
            #expect(LineHighlight.describe(ranges) == spec)
            // And describing then re-parsing is a fixed point.
            #expect(LineHighlight.parse(LineHighlight.describe(ranges)) == ranges)
        }
    }
}

// MARK: - Line splitter

@MainActor
@Suite("LineSplitter")
struct LineSplitterTests {
    @Test func keepsEveryLineIncludingBlankInteriorAndTrailing() {
        // "a\n\nb\n" is four rows: a, blank, b, trailing blank — so line numbering
        // matches what the editor shows.
        #expect(LineSplitter.lineCount(of: "a\n\nb\n") == 4)
        #expect(LineSplitter.plainLines(of: "a\n\nb\n").count == 4)
    }

    @Test func emptyTextIsASingleRow() {
        #expect(LineSplitter.lineCount(of: "") == 1)
    }

    @Test func singleLineIsOneRow() {
        #expect(LineSplitter.lineCount(of: "let x = 1") == 1)
    }

    @Test func attributedLinesPreserveTextAndCount() {
        var attributed = AttributedString("one\ntwo\n\nfour")
        attributed.foregroundColor = .red
        let lines = LineSplitter.attributedLines(of: attributed)
        #expect(lines.count == 4)
        #expect(String(lines[0].characters) == "one")
        #expect(String(lines[1].characters) == "two")
        #expect(String(lines[2].characters) == "")
        #expect(String(lines[3].characters) == "four")
    }

    @Test func attributedLinesDoNotLeakNewlinesIntoRows() {
        let lines = LineSplitter.attributedLines(of: AttributedString("a\nb"))
        #expect(lines.allSatisfy { !$0.characters.contains("\n") })
    }
}

/// The cached row split (analysis §2.A9): `HighlightManager.swiftUIAttributedLines`
/// must serve exactly the rows a fresh `LineSplitter.attributedLines` of the bridged
/// string would — the cache is a speed-up, never a behavior change.
@MainActor
@Suite("Cached row split (§2.A9)")
struct CachedRowSplitTests {
    private static func font() -> NSFont { .monospacedSystemFont(ofSize: 14, weight: .regular) }

    @Test func cachedLinesMatchADirectSplitAndTheRowCount() {
        let code = "func greet() {\n    print(\"hi\")\n}\n"
        let cached = HighlightManager.shared.swiftUIAttributedLines(
            for: code, language: .swift, theme: .oneDark, font: Self.font())
        let direct = LineSplitter.attributedLines(
            of: HighlightManager.shared.swiftUIAttributedString(
                for: code, language: .swift, theme: .oneDark, font: Self.font()))
        #expect(cached.map { String($0.characters) } == direct.map { String($0.characters) })
        // "a\nb\nc\n" splits into 4 rows (three lines + a trailing empty one).
        #expect(cached.count == LineSplitter.lineCount(of: code))
    }

    @Test func cachedLinesAreStableAcrossCalls() {
        let code = "let x = 1\nlet y = 2"
        let first = HighlightManager.shared.swiftUIAttributedLines(
            for: code, language: .swift, theme: .nord, font: Self.font())
        let second = HighlightManager.shared.swiftUIAttributedLines(
            for: code, language: .swift, theme: .nord, font: Self.font())
        #expect(first == second)
    }

    @Test func anEmptyDocumentStillYieldsOneRow() {
        // The gutter must never collapse to zero rows (a zero-height band).
        let lines = HighlightManager.shared.swiftUIAttributedLines(
            for: "", language: .swift, theme: .oneDark, font: Self.font())
        #expect(lines.count == 1)
    }

    @Test func aTerminalCaptureSplitsIntoCachedRows() {
        let ansi = "\u{1B}[32mok\u{1B}[0m\n\u{1B}[31mfail\u{1B}[0m"
        let lines = HighlightManager.shared.terminalAttributedLines(
            for: ansi, theme: .oneDark, font: Self.font(), columns: nil)
        #expect(lines.count == 2)
    }
}

// MARK: - Gutter geometry

@MainActor
@Suite("GutterMetrics")
struct GutterMetricsTests {
    private static func font(size: CGFloat = 14) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    @Test func reservesAtLeastTwoDigitColumnsForShortSnippets() {
        // A handful of lines must not produce a cramped one-digit gutter: the
        // column count floors at two so "1" through "9" still reserve the same
        // width a two-digit number would (CS-021).
        #expect(GutterMetrics(font: Self.font(), lineCount: 1).digitColumns == 2)
        #expect(GutterMetrics(font: Self.font(), lineCount: 9).digitColumns == 2)
        #expect(GutterMetrics(font: Self.font(), lineCount: 10).digitColumns == 2)
    }

    @Test func reservedColumnsGrowWithTheHighestLineNumber() {
        // The column count is sized to the digit count of the largest line number,
        // so a 100-line file reserves three columns and a 1000-line file four.
        #expect(GutterMetrics(font: Self.font(), lineCount: 99).digitColumns == 2)
        #expect(GutterMetrics(font: Self.font(), lineCount: 100).digitColumns == 3)
        #expect(GutterMetrics(font: Self.font(), lineCount: 999).digitColumns == 3)
        #expect(GutterMetrics(font: Self.font(), lineCount: 1000).digitColumns == 4)
    }

    @Test func emptyOrNonPositiveLineCountStillReservesTheTwoDigitFloor() {
        // A zero/negative line count (an empty document) must not under- or
        // over-reserve: it clamps to the same two-digit floor as a one-line file
        // rather than computing the width of "0" or trapping.
        #expect(GutterMetrics(font: Self.font(), lineCount: 0).digitColumns == 2)
        #expect(GutterMetrics(font: Self.font(), lineCount: -5).digitColumns == 2)
    }

    @Test func numberWidthIsTheDigitColumnsTimesOneDigitAdvance() {
        // The reserved column width is exactly N digit advances wide — the property
        // that lets every line number's units digit land in the same place.
        let metrics = GutterMetrics(font: Self.font(), lineCount: 100)
        #expect(metrics.digitColumns == 3)
        #expect(metrics.numberWidth == CGFloat(metrics.digitColumns) * metrics.digitWidth)
    }

    @Test func digitWidthIsMeasuredFromTheCodeFontSoItScalesWithSize() {
        // Width tracks the real digit advance of the passed font, so a larger font
        // yields a wider gutter column (the gutter is not a fixed guess, CS-021).
        let small = GutterMetrics(font: Self.font(size: 12), lineCount: 10)
        let large = GutterMetrics(font: Self.font(size: 24), lineCount: 10)
        #expect(small.digitWidth > 0)
        #expect(large.digitWidth > small.digitWidth)
    }
}

// MARK: - SnapshotConfig flags

@Suite("SnapshotConfig line numbers")
struct SnapshotConfigLineNumberTests {
    @Test func defaultsAreOffAndEmpty() {
        let config = SnapshotConfig()
        #expect(config.showLineNumbers == false)
        #expect(config.highlightedLineRanges.isEmpty)
        // The default render keeps the single-Text path (no regression).
        #expect(config.usesLineRows == false)
    }

    @Test func rowLayoutTurnsOnWithEitherFeature() {
        var withGutter = SnapshotConfig()
        withGutter.showLineNumbers = true
        #expect(withGutter.usesLineRows)

        var withHighlight = SnapshotConfig()
        withHighlight.highlightedLineRanges = [2...4]
        #expect(withHighlight.usesLineRows)
    }

    @Test func equatableReflectsTheNewFields() {
        var a = SnapshotConfig()
        var b = SnapshotConfig()
        #expect(a == b)
        a.showLineNumbers = true
        #expect(a != b)
        b.showLineNumbers = true
        #expect(a == b)
        a.highlightedLineRanges = [1...2]
        #expect(a != b)
    }
}

// MARK: - Persistence round-trip

@MainActor
@Suite("AppSettings line-number persistence")
struct AppSettingsLineNumberTests {
    @Test func lineNumberSettingsPersistAcrossInstances() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.config.showLineNumbers = true
        first.config.highlightedLineRanges = LineHighlight.parse("3, 7-9")

        let second = AppSettings(defaults: defaults)
        #expect(second.config.showLineNumbers == true)
        #expect(second.config.highlightedLineRanges == [3...3, 7...9])
    }

    @Test func highlightedRangesPersistInCanonicalForm() {
        // A messy entry is normalized on the way in and reloads identically.
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.config.highlightedLineRanges = LineHighlight.parse("9-7, 3, 4")

        let second = AppSettings(defaults: defaults)
        #expect(second.config.highlightedLineRanges == [3...4, 7...9])
    }

    @Test func garbagePersistedSpecResolvesToNoHighlight() {
        let defaults = freshDefaults()
        defaults.set("not, a, spec", forKey: "highlightedLines")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.config.highlightedLineRanges.isEmpty)
    }

    @Test func resetClearsLineNumberSettings() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.config.showLineNumbers = true
        settings.config.highlightedLineRanges = [2...5]

        settings.resetToDefaults()
        #expect(settings.config.showLineNumbers == false)
        #expect(settings.config.highlightedLineRanges.isEmpty)
    }
}

// MARK: - Rendered image dimensions

@MainActor
@Suite("Line-number render dimensions")
struct LineNumberRenderTests {
    // Lines are deliberately long so the card's content width clears its
    // `minWidth` floor — that way adding the gutter measurably widens the image
    // rather than being absorbed by the minimum-width clamp.
    private static let sample = """
        import SwiftUI

        struct DemonstrationView: View {
            var body: some View {
                Text("Hello, world — this is a deliberately wide line of code")
                    .font(.largeTitle.weight(.semibold))
            }
        }
        """

    @Test func enablingTheGutterWidensTheImage() throws {
        // The gutter adds a fixed-width column, so the same code renders wider with
        // line numbers on than off (CS-021 acceptance: the gutter shows in export).
        var plain = SnapshotConfig()
        plain.code = Self.sample

        var gutter = plain
        gutter.showLineNumbers = true

        let plainImage = try #require(ExportManager.renderCGImage(plain, scale: 1))
        let gutterImage = try #require(ExportManager.renderCGImage(gutter, scale: 1))
        #expect(gutterImage.width > plainImage.width)
    }

    @Test func highlightingDoesNotChangeImageWidth() throws {
        // A selected-line highlight is a background band only; it must not shift the
        // code or resize the card relative to the plain render.
        var plain = SnapshotConfig()
        plain.code = Self.sample

        var highlighted = plain
        highlighted.highlightedLineRanges = [3...5]

        let plainImage = try #require(ExportManager.renderCGImage(plain, scale: 1))
        let highlightedImage = try #require(ExportManager.renderCGImage(highlighted, scale: 1))
        #expect(highlightedImage.width == plainImage.width)
    }

    @Test func gutterAndHighlightTogetherRenderSuccessfully() throws {
        var config = SnapshotConfig()
        config.code = Self.sample
        config.showLineNumbers = true
        config.highlightedLineRanges = [1...1, 4...6]
        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    @Test func emptyCodeWithGutterRendersWithoutGlitch() throws {
        // Empty code must not collapse to a zero-size render (CS-021 acceptance).
        var config = SnapshotConfig()
        config.code = ""
        config.showLineNumbers = true
        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    @Test func singleLineCodeWithGutterRendersWithoutGlitch() throws {
        var config = SnapshotConfig()
        config.code = "let answer = 42"
        config.showLineNumbers = true
        config.highlightedLineRanges = [1...1]
        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    @Test func highlightRangeBeyondCodeRendersSafely() throws {
        // A range past the last line (e.g. left over after trimming code) simply
        // highlights nothing rather than crashing.
        var config = SnapshotConfig()
        config.code = "line one\nline two"
        config.highlightedLineRanges = [50...60]
        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    @Test func gutterRendersAcrossLightAndDarkThemes() throws {
        // The gutter and highlight must work in both light and dark themes (CS-021
        // acceptance); GitHub is a light theme, One Dark a dark one.
        for theme in [Theme.github, Theme.oneDark] {
            var config = SnapshotConfig()
            config.code = Self.sample
            config.theme = theme
            config.showLineNumbers = true
            config.highlightedLineRanges = [2...3]
            let image = try #require(ExportManager.renderCGImage(config, scale: 1))
            #expect(image.width > 0)
            #expect(image.height > 0)
        }
    }

    @Test func highlightWorksOverTransparentBackground() throws {
        // A highlight sits on the theme card, not the canvas background, so it is
        // still valid with a transparent canvas that carries a real alpha channel.
        var config = SnapshotConfig()
        config.code = Self.sample
        config.background = .transparent
        config.highlightedLineRanges = [2...3]
        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        let alpha = image.alphaInfo
        #expect(
            alpha == .premultipliedFirst || alpha == .premultipliedLast || alpha == .first
                || alpha == .last)
    }
}

// MARK: - Highlight color is theme-aware

@MainActor
@Suite("Line highlight color")
struct LineHighlightColorTests {
    @Test func highlightColorDiffersBetweenLightAndDarkThemes() {
        // A light theme deepens its row, a dark theme lifts it, so the band is
        // visible in both (CS-021 acceptance). Compared via fixed-sRGB components
        // because SwiftUI `Color.==` is unreliable across construction paths.
        let dark = RGBAColor(HighlightManager.shared.lineHighlightColor(for: .oneDark))
        let light = RGBAColor(HighlightManager.shared.lineHighlightColor(for: .github))
        #expect(dark != light)
    }

    @Test func highlightBandIsTranslucentInBothThemes() {
        // The band is a wash over the theme's own card, never an opaque fill, so it
        // tints the selected row instead of replacing it — and stays valid over a
        // transparent canvas (CS-021 / CS-024). A fully opaque band would regress
        // both. Guard the upper bound strictly so the band can never go solid.
        for theme in [Theme.oneDark, Theme.github] {
            let band = RGBAColor(HighlightManager.shared.lineHighlightColor(for: theme))
            #expect(band.opacity > 0)
            #expect(band.opacity < 1)
        }
    }

    @Test func darkThemeLiftsItsRowWhileLightThemeDeepensIt() {
        // The documented tint direction: a dark theme's band is a light (white)
        // wash that lifts the row; a light theme's band is a dark (black) wash that
        // deepens it. Pinning the direction — not just "they differ" — catches a
        // future swap that would make a selection vanish on one theme.
        let dark = RGBAColor(HighlightManager.shared.lineHighlightColor(for: .oneDark))
        let light = RGBAColor(HighlightManager.shared.lineHighlightColor(for: .github))
        let darkLuminance = dark.red + dark.green + dark.blue
        let lightLuminance = light.red + light.green + light.blue
        #expect(darkLuminance > lightLuminance)
    }

    @Test func gutterForegroundDiffersBetweenLightAndDarkThemes() {
        let dark = RGBAColor(HighlightManager.shared.gutterForegroundColor(for: .oneDark))
        let light = RGBAColor(HighlightManager.shared.gutterForegroundColor(for: .github))
        #expect(dark != light)
    }

    @Test func gutterForegroundIsOpaqueAndContrastsTheTheme() {
        // The gutter number color is the high-contrast base the row dims from: an
        // opaque near-white on a dark theme, an opaque near-black on a light theme
        // (CS-021). It must stay fully opaque so the per-row opacity dimming is the
        // only thing that fades it.
        let dark = RGBAColor(HighlightManager.shared.gutterForegroundColor(for: .oneDark))
        let light = RGBAColor(HighlightManager.shared.gutterForegroundColor(for: .github))
        #expect(dark.opacity == 1)
        #expect(light.opacity == 1)
        // Bright on dark, dim on light.
        #expect(dark.red + dark.green + dark.blue > light.red + light.green + light.blue)
    }
}

// MARK: - Highlight actually paints pixels

/// Proof that a selected-line highlight is *drawn*, not merely modeled (CS-021).
///
/// The dimension tests prove a highlight does not reflow the code, and the color
/// tests prove the band tint is theme-correct — but neither would fail if the
/// band were silently dropped on the render path (e.g. the color resolved to
/// clear, or `CodeLinesView` stopped drawing the background). This suite closes
/// that gap by rendering the same code with and without a highlight and asserting
/// the encoded pixels differ, while the canvas size stays identical.
@MainActor
@Suite("Line highlight render")
struct LineHighlightRenderTests {
    // Several rows so a highlight on a middle line lands on real card pixels.
    private static let sample = """
        import SwiftUI

        struct DemonstrationView: View {
            var body: some View {
                Text("Hello, world — this is a deliberately wide line of code")
                    .font(.largeTitle.weight(.semibold))
            }
        }
        """

    /// Renders `config`, PNG-encodes it, and returns the encoded bytes — the same
    /// trip a saved or copied image makes.
    private func pngBytes(_ config: SnapshotConfig) throws -> Data {
        let rendered = try #require(ExportManager.renderCGImage(config, scale: 1))
        return try #require(ExportManager.pngData(from: rendered))
    }

    @Test func highlightingALineChangesRenderedPixels() throws {
        // Same code, same size (asserted by the dimension suite), but the
        // highlighted render must differ byte-for-byte: the band is real paint.
        var plain = SnapshotConfig()
        plain.code = Self.sample

        var highlighted = plain
        highlighted.highlightedLineRanges = [4...4]

        let plainPNG = try pngBytes(plain)
        let highlightedPNG = try pngBytes(highlighted)
        #expect(plainPNG != highlightedPNG)
    }

    @Test func differentHighlightedLinesProduceDifferentRenders() throws {
        // Highlighting line 2 vs line 5 must paint the band in different places, so
        // the two renders are distinct — the highlight tracks the requested line,
        // not a fixed row.
        var base = SnapshotConfig()
        base.code = Self.sample

        var highlightEarly = base
        highlightEarly.highlightedLineRanges = [2...2]

        var highlightLate = base
        highlightLate.highlightedLineRanges = [5...5]

        let early = try pngBytes(highlightEarly)
        let late = try pngBytes(highlightLate)
        #expect(early != late)
    }

    @Test func anOutOfRangeHighlightPaintsNothing() throws {
        // A range entirely past the last line highlights no row, so it must paint no
        // band: it is the "nothing selected" case, not a stray fill. Both configs go
        // through the same row layout (gutter on) so the only possible pixel
        // difference is a band — and there must be none, leaving the renders equal.
        // This guards the boundary the dimension suite only checks for non-crashing.
        var noHighlight = SnapshotConfig()
        noHighlight.code = Self.sample
        noHighlight.showLineNumbers = true

        var beyond = noHighlight
        beyond.highlightedLineRanges = [50...60]

        let noHighlightPNG = try pngBytes(noHighlight)
        let beyondPNG = try pngBytes(beyond)
        #expect(noHighlightPNG == beyondPNG)

        // Sanity anchor: an *in-range* highlight on the same row layout does paint,
        // so the equality above is a real "nothing drawn", not two dead renders.
        var inRange = noHighlight
        inRange.highlightedLineRanges = [2...2]
        #expect(try pngBytes(inRange) != noHighlightPNG)
    }
}
