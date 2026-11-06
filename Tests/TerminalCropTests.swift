import AppKit
import Foundation
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

// Assembled at runtime so secret-shaped fixtures never trip push protection.
private let token = "gh" + "p_" + String(repeating: "x", count: 36)

@Suite("Terminal crop", .serialized)
@MainActor
struct TerminalCropTests {
    private let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    /// A screen-addressed capture whose cursor ends on row 2, column 8.
    private let grid = "\u{1B}[2J\u{1B}[1;1Hfirst\u{1B}[2;1Hsecond row text\u{1B}[2;8H"

    private func capture(
        _ code: String, rows: ClosedRange<Int>? = nil, columns: ClosedRange<Int>? = nil
    ) -> SnapshotConfig {
        var config = SnapshotConfig(code: code, language: .terminal)
        config.terminalCrop = TerminalCrop(rows: rows, columns: columns)
        return config
    }

    private func png(_ config: SnapshotConfig) throws -> Data {
        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        return try #require(ExportManager.pngData(from: image))
    }

    private func cells(_ text: String, columns: ClosedRange<Int>) -> String {
        TerminalCrop(columns: columns).apply(to: [ANSIRun(text: text, style: ANSIStyle())])
            .map(\.text).joined()
    }

    @Test func anEmptyCropRendersByteForByteAsBefore() throws {
        let stream = "\u{1B}[31mred\u{1B}[0m\nplain"
        let plain = SnapshotConfig(code: stream, language: .terminal)
        #expect(try png(capture(stream)) == png(plain))
        #expect(capture(stream).sidecarText == plain.sidecarText)
        #expect(capture(stream).richClipboardText == stream)
        #expect(
            ANSIRenderer.attributedString(stream, font: font, crop: TerminalCrop())
                == ANSIRenderer.attributedString(stream, font: font))
    }

    @Test func aWideCharacterCutByAnEdgeBecomesASpace() {
        // a = column 1, 中 = columns 2-3, b = column 4.
        #expect(cells("a中b", columns: 2...3) == "中")
        #expect(cells("a中b", columns: 3...4) == " b")
        #expect(cells("a中b", columns: 1...2) == "a ")
        #expect(cells("e\u{301}x", columns: 2...2) == "x", "A combining mark goes with its base")
    }

    @Test func aTabBecomesSpacesOnlyUnderAColumnCrop() {
        #expect(cells("a\tb", columns: 1...9) == "a       b")
        #expect(capture("a\tb\nc", rows: 1...1).sidecarText == "a\tb")
    }

    @Test func rowsKeepTheirScreenNumbersForRedactionsAndTheGutter() throws {
        var config = capture("one\ntwo\nthree\nfour", rows: 2...3)
        config.redactedLineRanges = [3...3]
        #expect(config.sidecarText == "two\n[redacted]")
        config.redactedLineRanges = [1...1]
        #expect(config.sidecarText == "two\nthree")

        var cropped = capture("a\nb\nc", rows: 2...3)
        cropped.showLineNumbers = true
        var numbered = SnapshotConfig(code: "b\nc", language: .terminal)
        numbered.showLineNumbers = true
        numbered.firstLineNumber = 2
        #expect(try png(cropped) == png(numbered))
    }

    @Test func aCropNeverExposesARedactedRowOrCutsItsPlaceholder() throws {
        func redacted(_ secret: String) -> SnapshotConfig {
            var config = capture("one\n\(secret)\nthree", rows: 2...3, columns: 1...3)
            config.redactedLineRanges = [2...2]
            return config
        }
        let config = redacted(token)
        #expect(config.sidecarText == "[redacted]\nthr")
        #expect(config.richClipboardText == "[redacted]\nthr")
        #expect(SharedSnapshot(capturing: config).code == "\n[redacted]\nthr")
        #expect(RichPasteboard.highlightedCode(for: config).string == "[redacted]\nthr")
        let sameLength = String(repeating: "y", count: token.count)
        #expect(try png(config) == png(redacted(sameLength)))
    }

    @Test func aCursorOnARedactedRowStaysHiddenUnderACrop() throws {
        func cursor(_ style: TerminalCursorStyle) -> SnapshotConfig {
            var config = capture(grid, rows: 2...2)
            config.redactedLineRanges = [2...2]
            config.terminalCursor = style
            return config
        }
        #expect(try png(cursor(.bar)) == png(cursor(.hidden)))
    }

    @Test func aCursorOutsideTheCropIsNotDrawn() {
        func drawsBar(_ crop: TerminalCrop) -> Bool {
            ANSIRenderer.attributedString(grid, font: font, cursor: .bar, crop: crop).string
                .contains("\u{258F}")
        }
        #expect(drawsBar(TerminalCrop(columns: 8...20)))
        #expect(!drawsBar(TerminalCrop(rows: 1...1)))
        #expect(!drawsBar(TerminalCrop(columns: 1...7)))
    }

    @Test func croppedOutCellsLeakThroughNoTextSurface() throws {
        let config = capture(
            "hidden-row\nkept row\nkept two\nhidden-tail", rows: 2...3, columns: 1...4)
        let surfaces = [
            config.sidecarText, config.richClipboardText,
            SharedSnapshot(capturing: config).code,
            RichPasteboard.highlightedCode(for: config).string,
        ]
        for text in surfaces {
            #expect(!text.contains("hidden"))
            #expect(!text.contains("row"))
        }
        let draft = try #require(AlternativeTextDrafter.draft(for: config))
        #expect(draft.text.contains("2"))
    }

    @Test func aShareLinkReopensTheSameImage() throws {
        var config = capture("a\nb\nc\nd", rows: 2...3)
        config.showLineNumbers = true
        config.terminalCursor = .block
        let link = SharedSnapshot(capturing: config)
        var reopened = SnapshotConfig()
        link.apply(to: &reopened)
        #expect(reopened.terminalCrop.rows == 2...3)
        #expect(reopened.terminalCursor == .hidden)
        config.terminalCursor = .hidden
        #expect(try png(reopened) == png(config))
        let encoded = try JSONEncoder().encode(SharedSnapshot(capturing: capture("a")))
        #expect(!String(decoding: encoded, as: UTF8.self).contains("terminalCrop"))
    }

    @Test func secretScansCountTheWholeScreenAndSkipCroppedRows() {
        let outside = capture("\(token)\nok\nok", rows: 2...3)
        #expect(ExportPreflight(outside, payload: .image).isClean)
        #expect(ExportPreflight(outside, payload: .transcript).isClean)
        let inside = capture("ok\nok\n\(token)", rows: 2...3)
        #expect(ExportPreflight(inside, payload: .image).redactableLines == [3])
        #expect(inside.uncroppedSidecarText.hasPrefix("ok\nok\n"))
    }

    @Test func aNewCaptureClearsTheCrop() {
        let config = capture("one\ntwo", rows: 1...1)
        #expect(config.hasContentMarks)
        #expect(config.replacingContent(with: "new").terminalCrop.isEmpty)
        var swift = config
        swift.language = .swift
        #expect(swift.sidecarText == "one\ntwo", "Only terminal text is cropped")
    }
}
