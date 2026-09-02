import AppKit
import Foundation
import SwiftUI
import Testing
import VitrineDomain

@testable import VitrineRendering

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

    @Test func unicodeContentCountsOnlyLineFeeds() {
        #expect(LineSplitter.lineCount(of: "🧪 café\n日本語\n") == 3)
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

/// The cached row split from `HighlightManager.swiftUIAttributedLines`
/// must serve exactly the rows a fresh `LineSplitter.attributedLines` of the bridged
/// string would — the cache is a speed-up, never a behavior change.
@MainActor
@Suite("Cached row split")
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
        // width a two-digit number would.
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
        // yields a wider gutter column (the gutter is not a fixed guess).
        let small = GutterMetrics(font: Self.font(size: 12), lineCount: 10)
        let large = GutterMetrics(font: Self.font(size: 24), lineCount: 10)
        #expect(small.digitWidth > 0)
        #expect(large.digitWidth > small.digitWidth)
    }
}
