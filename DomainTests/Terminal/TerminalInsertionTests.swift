import Testing

@testable import VitrineDomain

@Suite("Terminal wide-character insertion")
struct TerminalInsertionTests {
    private let esc = "\u{1B}"

    @Test(arguments: ["你", "🚀"], [1, 2])
    func insertionBeforeWideHeadPreservesBothCells(glyph: String, count: Int) {
        var screen = TerminalScreen(columns: 8, rows: 2)
        screen.feed("\(glyph)Z\(esc)[1G\(esc)[\(count)@")

        #expect(text(screen) == String(repeating: " ", count: count) + glyph + "Z")
        #expect(screen.rows[0][count].content == .grapheme(glyph))
        #expect(screen.rows[0][count + 1].content == .continuation)
        #expect(screen.cursorCol == 0)
        #expect(!screen.pendingWrap)
    }

    @Test(arguments: ["你", "🚀"])
    func insertionBeforeWideHeadInTheMiddlePreservesThePrefix(_ glyph: String) {
        var screen = TerminalScreen(columns: 8, rows: 2)
        screen.feed("AB\(glyph)Z\(esc)[3G\(esc)[@")
        #expect(text(screen) == "AB \(glyph)Z")
        #expect(screen.cursorCol == 2)
    }

    @Test(arguments: ["你", "🚀"])
    func insertionInsideContinuationStillClearsTheSplitGlyph(_ glyph: String) {
        var screen = TerminalScreen(columns: 8, rows: 2)
        screen.feed("\(glyph)Z\(esc)[2G\(esc)[@")
        #expect(text(screen) == "   Z")
        #expect(!screen.rows[0].contains { $0.content == .continuation })
    }

    @Test(arguments: ["你", "🚀"])
    func aWideGlyphThatStillFitsAtTheMarginSurvives(_ glyph: String) {
        var screen = TerminalScreen(columns: 4, rows: 2)
        screen.feed("A\(glyph)B\(esc)[2G\(esc)[@")
        #expect(text(screen) == "A \(glyph)")
        #expect(screen.rows[0][2].content == .grapheme(glyph))
        #expect(screen.rows[0][3].content == .continuation)
        #expect(screen.rows[0].count == 4)
    }

    @Test(arguments: ["你", "🚀"])
    func aWideGlyphTruncatedAtTheMarginLeavesNoOrphan(_ glyph: String) {
        var screen = TerminalScreen(columns: 4, rows: 2)
        screen.feed("A\(glyph)B\(esc)[2G\(esc)[2@")
        #expect(text(screen) == "A")
        #expect(screen.rows[0].count == 4)
        #expect(screen.rows[0].dropFirst().allSatisfy { $0.content == .grapheme(" ") })
    }

    @Test(arguments: ["你", "🚀"])
    func aWideGlyphTruncatedAtTheMarginErasesWithThePenBackground(_ glyph: String) {
        // The orphaned head must erase like the inserted cells, not punch an unstyled
        // hole into a colored line.
        var screen = TerminalScreen(columns: 4, rows: 2)
        screen.feed("A\(glyph)B\(esc)[2G\(esc)[42m\(esc)[2@")
        let green = TerminalCell(content: .grapheme(" "), style: ANSIStyle(background: .indexed(2)))
        #expect(screen.rows[0].count == 4)
        #expect(screen.rows[0][0].content == .grapheme("A"))
        #expect(Array(screen.rows[0].dropFirst()) == [green, green, green])
    }

    @Test(arguments: ["你", "🚀"], [7, 8, 99])
    func aCountReachingTheMarginPushesTheWholeGlyphOff(glyph: String, count: Int) {
        var screen = TerminalScreen(columns: 8, rows: 2)
        screen.feed("\(glyph)Z\(esc)[1G\(esc)[\(count)@")
        #expect(text(screen) == "")
        #expect(screen.rows[0].count == 8)
        #expect(screen.rows[0].allSatisfy { $0 == .blank })
        #expect(screen.cursorCol == 0)
    }

    @Test func insertionPreservesGlyphStyleAndUsesTheOrdinaryBlankPolicy() {
        let setup = "\(esc)[31;44m"
        let insert = "\(esc)[0m\(esc)[42m\(esc)[1G\(esc)[@"
        var wide = TerminalScreen(columns: 8, rows: 2)
        wide.feed("\(setup)你Z\(insert)")
        var ordinary = TerminalScreen(columns: 8, rows: 2)
        ordinary.feed("\(setup)ABZ\(insert)")

        // Wide insertion must share ordinary insertion's fill policy, including BCE
        // when supported, while the moved glyph retains its original attributes.
        #expect(wide.rows[0][0] == ordinary.rows[0][0])
        #expect(wide.rows[0][1].content == .grapheme("你"))
        #expect(wide.rows[0][2].content == .continuation)
        let glyphStyle = ANSIStyle(foreground: .indexed(1), background: .indexed(4))
        #expect(wide.rows[0][1].style == glyphStyle)
        #expect(wide.rows[0][2].style == glyphStyle)
        #expect(wide.style == ANSIStyle(background: .indexed(2)))
        #expect(text(ordinary) == " ABZ")
    }

    @Test(arguments: ["", "A"])
    func insertionPastTheWrittenTailPadsTheCursorCell(_ prefix: String) {
        var screen = TerminalScreen(columns: 8, rows: 2)
        screen.feed("\(prefix)\(esc)[7G\(esc)[@")
        #expect(text(screen) == prefix)
        #expect(screen.cursorCol == 6)
        #expect(screen.rows[0].count == 8)
        #expect(screen.rows[0][6].content == .grapheme(" "))
    }

    private func text(_ screen: TerminalScreen) -> String {
        screen.runs().map(\.text).joined()
    }
}
