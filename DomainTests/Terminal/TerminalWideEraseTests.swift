import Testing

@testable import VitrineDomain

@Suite("Terminal wide-character erase fill")
struct TerminalWideEraseTests {
    private let esc = "\u{1B}"

    @Test(
        arguments: ["你", "🚀"],
        [
            ("2G", "X", 2), ("3G", "X", 1),
            ("3G", "K", 1), ("2G", "1K", 2),
            ("3G", "J", 1), ("2G", "1J", 2),
            ("2G", "P", 1), ("3G", "P", 1),
            ("3G", "@", 1),
        ])
    func splitWideGlyphErasesItsPartnerWithThePenBackground(
        glyph: String, operation: (cursor: String, edit: String, partnerColumn: Int)
    ) throws {
        var screen = TerminalScreen(columns: 6, rows: 2)
        screen.feed("A\(glyph)Z\(esc)[42m\(esc)[\(operation.cursor)\(esc)[\(operation.edit)")

        // Every edit removes the glyph. The partner outside the requested range must erase
        // with the same background as the explicitly erased or inserted cell.
        let fill = TerminalCell(content: .grapheme(" "), style: ANSIStyle(background: .indexed(2)))
        let row = try #require(screen.rows.first)
        try #require(row.indices.contains(operation.partnerColumn))
        let partner = row[operation.partnerColumn]
        #expect(partner == fill)
        #expect(screen.rows[0].contains { $0.content == .grapheme(glyph) } == false)
        #expect(screen.rows[0].contains { $0.content == .continuation } == false)
        #expect(screen.style == ANSIStyle(background: .indexed(2)))
    }

    @Test(arguments: ["你", "🚀"], ["2G", "3G"])
    func aBoundedEraseKeepsTheNeighboringGlyphsAndFillsBothHalves(
        glyph: String, cursor: String
    ) {
        var screen = TerminalScreen(columns: 6, rows: 2)
        screen.feed("A\(glyph)Z\(esc)[42m\(esc)[\(cursor)\(esc)[X")

        #expect(
            screen.runs() == [
                ANSIRun(text: "A", style: ANSIStyle()),
                ANSIRun(text: "  ", style: ANSIStyle(background: .indexed(2))),
                ANSIRun(text: "Z", style: ANSIStyle()),
            ])
    }

    @Test(arguments: ["你", "🚀"], ["", "42;"])
    func erasedHalvesKeepOnlyThePenBackgroundAndPreserveNeighborStyles(
        glyph: String, background: String
    ) {
        var screen = TerminalScreen(columns: 6, rows: 2)
        screen.feed(
            "\(esc)[35;44mA\(glyph)Z\(esc)[0;\(background)1;3;4;7;31m\(esc)[3G\(esc)[X")

        let original = ANSIStyle(foreground: .indexed(5), background: .indexed(4))
        let fill = ANSIStyle(background: background.isEmpty ? .default : .indexed(2))
        #expect(
            screen.runs() == [
                ANSIRun(text: "A", style: original),
                ANSIRun(text: "  ", style: fill),
                ANSIRun(text: "Z", style: original),
            ])
    }

    @Test(arguments: [("2X", [1, 4]), ("2P", [1, 2]), ("K", [1])])
    func anEditSplittingTwoGlyphsFillsEveryOutsidePartner(
        edit: String, partnerColumns: [Int]
    ) throws {
        var screen = TerminalScreen(columns: 8, rows: 2)
        screen.feed("A你好Z\(esc)[42m\(esc)[3G\(esc)[\(edit)")

        let fill = TerminalCell(content: .grapheme(" "), style: ANSIStyle(background: .indexed(2)))
        let row = try #require(screen.rows.first)
        for column in partnerColumns { #expect(row[column] == fill) }
        #expect(row.contains { $0.content == .continuation } == false)
        #expect(row.contains { [.grapheme("你"), .grapheme("好")].contains($0.content) } == false)
    }
}
