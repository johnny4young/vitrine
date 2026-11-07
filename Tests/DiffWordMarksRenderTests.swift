import AppKit
import Foundation
import SwiftUI
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@Suite("Diff word marks rendering")
struct DiffWordMarksRenderTests {
    private static let patch = """
        @@ -1,3 +1,3 @@
         let first = "context"
        -let second = "the old value of this line"
        +let second = "the new value of this line"
         let third = "more context"
        """

    private func diffConfig(marks: Bool = true) -> SnapshotConfig {
        var config = SnapshotConfig(code: Self.patch, language: .diff)
        config.diffDecorations = true
        config.showLineNumbers = true
        config.diffWordMarks = marks
        return config
    }

    private func render(_ config: SnapshotConfig) throws -> CGImage {
        try #require(ExportManager.renderCGImage(config, scale: 1))
    }

    private func differingPixels(
        _ first: () throws -> CGImage, _ second: () throws -> CGImage
    ) throws -> Int {
        var differing = 0
        for _ in 1...RenderSettling.strictRenderAttempts {
            differing = try FontLigatureTests.compareRenderedPixels(first(), second())
                .differingPixels
            if differing == 0 { break }
            RenderSettling.settleFontCaches()
        }
        return differing
    }

    @Test func marksAreOffByDefaultAndApplyOnlyToDiffs() {
        #expect(!SnapshotConfig().diffWordMarks)
        #expect(SnapshotConfig(code: Self.patch, language: .diff).diffDocument == nil)
        #expect(diffConfig().diffDocument != nil)

        var plain = SnapshotConfig(code: Self.patch, language: .swift)
        plain.diffWordMarks = true
        #expect(!plain.diffUsesWordMarks)
        #expect(!plain.usesLineRows)
        var bare = SnapshotConfig(code: Self.patch, language: .diff)
        bare.diffWordMarks = true
        #expect(bare.usesLineRows)
    }

    @Test(arguments: [DiffViewMode.unified, .split])
    func marksTintTheChangedWordsDeterministically(_ view: DiffViewMode) throws {
        var on = diffConfig()
        on.diffView = view
        var off = on
        off.diffWordMarks = false
        let marked = try render(on)
        let plain = try render(off)
        #expect(marked.width == plain.width)
        #expect(marked.height == plain.height)
        #expect(try FontLigatureTests.compareRenderedPixels(marked, plain).differingPixels > 0)
        #expect(try differingPixels({ try render(on) }, { try render(on) }) == 0)
    }

    @Test func aDiffWithNothingToPairRendersAsBefore() throws {
        var on = diffConfig()
        on.code = "@@ -1,2 +1,3 @@\n one\n+added line\n two"
        var off = on
        off.diffWordMarks = false
        #expect(try differingPixels({ try render(on) }, { try render(off) }) == 0)
    }

    @Test func marksFollowWrappedRows() throws {
        let words = String(repeating: "word ", count: 24)
        var on = diffConfig()
        on.wrapColumns = 40
        on.code = "@@ -1 +1 @@\n-\(words)old tail\n+\(words)new tail"
        var off = on
        off.diffWordMarks = false
        let marked = try render(on)
        let plain = try render(off)
        #expect(marked.height == plain.height)
        #expect(try FontLigatureTests.compareRenderedPixels(marked, plain).differingPixels > 0)
    }

    @Test(arguments: [3...3, 4...4])
    func aRedactedLineShowsOnlyItsMaskAndItsPartnerNoMarks(_ redacted: ClosedRange<Int>) throws {
        var on = diffConfig()
        on.redactedLineRanges = [redacted]
        var off = on
        off.diffWordMarks = false
        #expect(try differingPixels({ try render(on) }, { try render(off) }) == 0)

        let rows = Self.patch.components(separatedBy: "\n")
        #expect(DiffDocument(source: Self.patch).wordMarks(lines: rows).count == 2)
        #expect(
            DiffDocument(source: Self.patch).wordMarks(lines: rows, redacting: [redacted]).isEmpty)
    }

    @Test func markingLeavesContextAndOutOfRangeSpansAlone() {
        let line = AttributedString(" context")
        #expect(CodeLinesView.marking(line, spans: [1..<4]) == line)
        let added = AttributedString("+short")
        #expect(CodeLinesView.marking(added, spans: [3..<40]) == added)
        #expect(CodeLinesView.marking(added, spans: [1..<3]) != added)
    }

    @Test func theSwitchRespectsABlurBox() {
        let settings = AppSettings(defaults: testDefaults())
        settings.config = diffConfig(marks: false)
        settings.style.annotations = [
            Annotation(kind: .blur, start: CGPoint(x: 0.1, y: 0.4), end: CGPoint(x: 0.5, y: 0.5))
        ]
        settings.diffWordMarksEnabled.wrappedValue = true
        #expect(!settings.style.diffWordMarks)
        settings.style.annotations = []
        settings.diffWordMarksEnabled.wrappedValue = true
        #expect(settings.diffWordMarksEnabled.wrappedValue)
    }

    @Test func linksOmitTheFlagUntilItIsOn() throws {
        func keys(_ config: SnapshotConfig) throws -> [String: Any] {
            try #require(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(SharedSnapshot(capturing: config)))
                    as? [String: Any])
        }
        #expect(try keys(diffConfig(marks: false))["diffWordMarks"] == nil)
        #expect(try keys(diffConfig())["diffWordMarks"] as? Bool == true)
    }
}
