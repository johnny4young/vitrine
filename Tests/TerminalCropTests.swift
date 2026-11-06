import AppKit
import Foundation
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

// Assembled at runtime so secret-shaped fixtures never trip push protection.
private let token = "gh" + "p_" + String(repeating: "x", count: 36)
private let placeholder = SnapshotConfig.redactedLinePlaceholder

@Suite("Terminal crop", .serialized)
@MainActor
struct TerminalCropTests {
    private let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    /// A screen-addressed capture whose cursor ends on row 2, column 8.
    private let grid = "\u{1B}[2J\u{1B}[1;1Hfirst\u{1B}[2;1Hsecond row text\u{1B}[2;8H"
    /// Rows in 16-color, 256-color and truecolor, with bold.
    private let colored =
        "\u{1B}[31mred\u{1B}[0m\n\u{1B}[1;38;5;208mbold orange\u{1B}[0m\n"
        + "\u{1B}[48;2;10;20;30mtruecolor\u{1B}[0m\nplain"

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

    private func reopened(_ link: SharedSnapshot) -> SnapshotConfig {
        var config = SnapshotConfig()
        link.apply(to: &config)
        return config
    }

    @Test func anEmptyCropRendersByteForByteAsBefore() throws {
        let plain = SnapshotConfig(code: colored, language: .terminal)
        #expect(try png(capture(colored)) == png(plain))
        #expect(capture(colored).sidecarText == plain.sidecarText)
        #expect(capture(colored).richClipboardText == plain.richClipboardText)
        #expect(
            ANSIRenderer.attributedString(colored, font: font, crop: TerminalCrop())
                == ANSIRenderer.attributedString(colored, font: font))
    }

    @Test func oneStrictSpanIsTheOnlyAcceptedText() {
        #expect(TerminalCrop.span("6-18") == 6...18)
        #expect(TerminalCrop.span(" 18 - 6 ") == 6...18)
        #expect(TerminalCrop.span("4") == 4...4)
        #expect(TerminalCrop.span("\(TerminalCrop.maximum)") != nil)
        for refused in [
            "", "3,4", "3, 7-9", "0-2", "-3", "1-2-3", "a-b", "\(TerminalCrop.maximum + 1)",
        ] {
            #expect(TerminalCrop.span(refused) == nil, "\(refused)")
        }
    }

    @Test func aWideCharacterCutByAnEdgeBecomesASpace() {
        // a = column 1, 中 = columns 2-3, b = column 4.
        #expect(cells("a中b", columns: 2...3) == "中")
        #expect(cells("a中b", columns: 3...4) == " b")
        #expect(cells("a中b", columns: 1...2) == "a ")
    }

    @Test func marksAndJoinersLeaveWithTheCharacterTheyAttach() {
        #expect(cells("e\u{301}x", columns: 2...2) == "x")
        #expect(cells("中\u{FE0F}x", columns: 2...3) == " x")
        // 👨 = columns 1-2, 👩 = columns 3-4: a joiner to a cut character is dropped too.
        #expect(cells("👨\u{200D}👩", columns: 1...2) == "👨")
        #expect(cells("👨\u{200D}👩", columns: 1...4) == "👨\u{200D}👩")
        #expect(cells("a\n\u{301}b", columns: 1...1) == "a\nb", "A row starts with no base")
    }

    @Test func aTabBecomesSpacesOnlyUnderAColumnCrop() {
        #expect(cells("a\tb", columns: 1...9) == "a" + String(repeating: " ", count: 7) + "b")
        #expect(capture("a\tb\nc", rows: 1...1).sidecarText == "a\tb")
    }

    @Test func rowsKeepTheirScreenNumbersForRedactionsAndTheGutter() throws {
        var config = capture("one\ntwo\nthree\nfour", rows: 2...3)
        config.redactedLineRanges = [3...3]
        #expect(config.sidecarText == "two\n" + placeholder)
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
        let expected = placeholder + "\nthr"
        #expect(config.sidecarText == expected)
        #expect(config.richClipboardText == expected)
        #expect(SharedSnapshot(capturing: config).code == expected)
        #expect(RichPasteboard.highlightedCode(for: config).string == expected)
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

    @Test func aCursorOutsideTheCropIsNotDrawn() throws {
        let bar = try #require(TerminalCursorStyle.bar.runs().first?.text)
        func drawsBar(_ crop: TerminalCrop) -> Bool {
            ANSIRenderer.attributedString(grid, font: font, cursor: .bar, crop: crop).string
                .contains(bar)
        }
        #expect(drawsBar(TerminalCrop(columns: 8...20)))
        #expect(!drawsBar(TerminalCrop(rows: 1...1)))
        #expect(!drawsBar(TerminalCrop(columns: 1...7)))
    }

    @Test func croppedOutCellsLeakThroughNoTextSurface() throws {
        let config = capture(
            "hidden-row\nkept row\nkept two\nhidden-tail", rows: 2...3, columns: 1...4)
        let package = DocumentationPackage(
            config: config, png: Data(),
            representations: Set(DocumentationRepresentation.allCases))
        let surfaces =
            [
                config.sidecarText, config.richClipboardText,
                SharedSnapshot(capturing: config).code,
                RichPasteboard.highlightedCode(for: config).string,
                MarkdownExport.document(for: config, imageSource: "image.png"),
                HTMLExport.document(for: config, imageSource: "image.png"),
            ] + package.files.values.map { String(decoding: $0, as: UTF8.self) }
        for text in surfaces {
            #expect(!text.contains("hidden"))
            #expect(!text.contains("row"))
        }
        let shown = SnapshotConfig(code: "kept\nkept", language: .terminal)
        #expect(
            AlternativeTextDrafter.draft(for: config) == AlternativeTextDrafter.draft(for: shown))
    }

    @Test func aCroppedShareLinkKeepsColorAndReopensTheSameImage() throws {
        for numbered in [false, true] {
            var config = capture(colored, rows: 2...3, columns: 1...8)
            config.showLineNumbers = numbered
            config.terminalCursor = .block
            let link = SharedSnapshot(capturing: config)
            #expect(!link.code.contains("plain") && !link.code.contains("red"))
            let opened = reopened(link)
            #expect(opened.terminalCrop.rows == (numbered ? 2...3 : nil))
            #expect(opened.terminalCursor == .hidden)
            config.terminalCursor = .hidden
            #expect(try png(opened) == png(config), "line numbers: \(numbered)")
        }
        let encoded = try JSONEncoder().encode(SharedSnapshot(capturing: capture("a")))
        #expect(!String(decoding: encoded, as: UTF8.self).contains("terminalCrop"))
    }

    @Test func blurAndSpotlightBoxesBlockACrop() {
        func box(_ kind: Annotation.Kind) -> Annotation {
            Annotation(kind: kind, start: CGPoint(x: 0.1, y: 0.3), end: CGPoint(x: 0.9, y: 0.5))
        }
        #expect(TerminalCrop.isBlocked(by: [box(.blur)]))
        #expect(TerminalCrop.isBlocked(by: [box(.arrow), box(.spotlight)]))
        #expect(!TerminalCrop.isBlocked(by: [box(.arrow), box(.text), box(.rectangle)]))
    }

    @Test func secretScansCountTheWholeScreenAndSkipCroppedRows() {
        let outside = capture("\(token)\nok\nok", rows: 2...3)
        #expect(ExportPreflight(outside, payload: .image).isClean)
        #expect(ExportPreflight(outside, payload: .transcript).isClean)
        let inside = capture("ok\nok\n\(token)", rows: 2...3)
        #expect(ExportPreflight(inside, payload: .image).redactableLines == [3])
        #expect(inside.uncroppedSidecarText == "ok\nok\n\(token)")
    }

    @Test func aNewCaptureClearsTheCrop() {
        let config = capture("one\ntwo", rows: 1...1)
        #expect(config.hasContentMarks)
        #expect(config.replacingContent(with: "new").terminalCrop.isEmpty)
        var swift = config
        swift.language = .swift
        #expect(swift.sidecarText == swift.code, "Only terminal text is cropped")
    }
}
