import Testing

@testable import VitrineDomain

@Suite("Diff split layout")
struct DiffSplitLayoutTests {
    private static let patch = """
        --- a/Client.swift
        +++ b/Client.swift
        @@ -10,5 +20,6 @@ struct Client {
         ten
        -eleven
        -twelve
        +ELEVEN
         thirteen
        +added
        +more
        \\ No newline at end of file
        """

    private func cell(_ row: Int, _ number: Int?) -> DiffSplitCell {
        DiffSplitCell(row: row, number: number)
    }

    private func split(
        _ source: String, rows: [DiffDisplayRow]? = nil, first: Int = 1,
        redacting: [ClosedRange<Int>] = []
    ) -> [DiffSplitRow] {
        let document = DiffDocument(source: source)
        return document.splitRows(
            rows ?? document.rowKinds.indices.map { .line($0 + 1) }, firstLineNumber: first,
            redacting: redacting)
    }

    @Test func pairsRemovalsWithTheAdditionsAfterThemAndNumbersEachSide() {
        #expect(
            split(Self.patch) == [
                .spanning(.line(1)), .spanning(.line(2)), .spanning(.line(3)),
                .pair(old: cell(4, 10), new: cell(4, 20)),
                .pair(old: cell(5, 11), new: cell(7, 21)),
                .pair(old: cell(6, 12), new: nil),
                .pair(old: cell(8, 13), new: cell(8, 22)),
                .pair(old: nil, new: cell(9, 23)),
                .pair(old: nil, new: cell(10, 24)),
                .pair(old: nil, new: cell(11, nil)),
            ])
    }

    @Test func additionsBeforeARemovalDoNotPairWithIt() {
        let rows = split("@@ -1,1 +1,1 @@\n+new\n-old")
        #expect(
            rows == [
                .spanning(.line(1)),
                .pair(old: nil, new: cell(2, 1)),
                .pair(old: cell(3, 1), new: nil),
            ])
    }

    @Test func foldedContextKeepsTheFileNumbersOfTheRowsLeft() {
        let source = "@@ -1,6 +1,6 @@\n a\n b\n c\n d\n-e\n+E\n f"
        let document = DiffDocument(source: source)
        let rows = document.splitRows(document.displayRows(contextLines: 1))
        #expect(
            rows == [
                .spanning(.line(1)),
                .pair(old: cell(5, 4), new: cell(5, 4)),
                .pair(old: cell(6, 5), new: cell(7, 5)),
                .pair(old: cell(8, 6), new: cell(8, 6)),
            ])
    }

    @Test func textWithoutAHunkCountsFromTheFirstLineNumber() {
        #expect(
            split(" keep\n-old\n+new", first: 7) == [
                .pair(old: cell(1, 7), new: cell(1, 7)),
                .pair(old: cell(2, 8), new: cell(3, 8)),
            ])
    }

    @Test func aRedactedHunkHeaderLeavesItsHunkUnnumbered() {
        let source = "@@ -40,2 +40,2 @@\n a\n-b\n+B\n@@ -90,1 +90,1 @@\n c"
        let rows = split(source, redacting: [1...1])
        #expect(rows[1] == .pair(old: cell(2, nil), new: cell(2, nil)))
        #expect(rows[2] == .pair(old: cell(3, nil), new: cell(4, nil)))
        #expect(rows.last == .pair(old: cell(6, 90), new: cell(6, 90)))
    }

    @Test func combinedAndMalformedHeadersStillLayOut() {
        let combined = DiffDocument(source: "@@@ -1,2 -1,2 +1,3 @@@\n  a\n+ b")
        #expect(combined.hunkStarts[0] == DiffLinePair(old: 1, new: 1))

        let masked = split("@@ ████\n a\n-b")
        #expect(masked[1] == .pair(old: cell(2, nil), new: cell(2, nil)))
        #expect(masked[2] == .pair(old: cell(3, nil), new: nil))
    }

    @Test(arguments: [Int.max, DiffDocument.maximumHunkStart + 1])
    func hostileHunkStartsLeaveTheHunkUnnumbered(_ start: Int) {
        let rows = split("@@ -\(start),2 +\(start),2 @@\n a\n-b\n+c")
        #expect(DiffDocument(source: "@@ -\(start),2 +1,2 @@").hunkStarts.isEmpty)
        #expect(rows[1] == .pair(old: cell(2, nil), new: cell(2, nil)))
        #expect(rows[2] == .pair(old: cell(3, nil), new: cell(4, nil)))
    }

    @Test func theLargestAllowedStartStillCounts() {
        let start = DiffDocument.maximumHunkStart
        let rows = split("@@ -\(start),1 +\(start),1 @@\n a\n-b")
        #expect(rows[1] == .pair(old: cell(2, start), new: cell(2, start)))
        #expect(rows[2] == .pair(old: cell(3, start + 1), new: nil))
    }

    @Test func aFirstLineNumberAtTheLimitStopsNumberingInsteadOfTrapping() {
        let rows = split(" a\n b", first: Int.max)
        #expect(
            rows == [
                .pair(old: cell(1, Int.max), new: cell(1, Int.max)),
                .pair(old: cell(2, nil), new: cell(2, nil)),
            ])
    }

    @Test func aChangedLastLineWithoutANewlineStillPairs() {
        let note = "\\ No newline at end of file"
        let rows = split("@@ -1 +1 @@\n-old\n\(note)\n+new\n\(note)")
        #expect(
            rows == [
                .spanning(.line(1)),
                .pair(old: cell(2, 1), new: cell(4, 1)),
                .pair(old: cell(3, nil), new: cell(5, nil)),
            ])

        let oneSided = split("@@ -1 +1 @@\n-old\n\(note)\n+new")
        #expect(oneSided.last == .pair(old: cell(3, nil), new: nil))
        #expect(split("@@ -1 +1 @@\n a\n\(note)").last == .spanning(.line(3)))
    }

    @Test func rowsOutsideTheDocumentSpan() {
        #expect(split("+a", rows: [.line(9), .fold]) == [.spanning(.line(9)), .spanning(.fold)])
    }
}
