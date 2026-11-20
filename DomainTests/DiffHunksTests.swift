import Testing

@testable import VitrineDomain

@Suite("Diff hunks and numbering")
struct DiffHunksTests {
    private static let patch = """
        --- a/Client.swift
        +++ b/Client.swift
        @@ -10,6 +10,6 @@ struct Client {
         ten
        -eleven
        +ELEVEN
         twelve
         thirteen
         fourteen
        -fifteen
        +FIFTEEN
        @@ -98,2 +98,3 @@ extension Client {
         ninety-eight
        +added
        \\ No newline at end of file
        """

    private var document: DiffDocument { DiffDocument(source: Self.patch) }

    private func allRows() -> [DiffDisplayRow] {
        document.rowKinds.indices.map { .line($0 + 1) }
    }

    @Test func hunksSpanTheirHeaderThroughTheirLastLineWithTheirCounts() {
        #expect(
            document.hunks == [
                DiffHunk(rows: 3...11, additions: 2, deletions: 2),
                DiffHunk(rows: 12...15, additions: 1, deletions: 0),
            ])
        #expect(DiffDocument(source: "plain\ntext").hunks.isEmpty)
        #expect(DiffDocument(source: "+added\n-removed").hunks.isEmpty)
    }

    @Test func aHunkStopsAtTheNextFilesHeader() {
        let twoFiles = Self.patch + "\ndiff --git a/b b/b\n--- a/b\n+++ b/b\n@@ -1 +1 @@\n-x\n+y"
        let hunks = DiffDocument(source: twoFiles).hunks
        #expect(hunks.map(\.rows) == [3...11, 12...15, 19...21])
    }

    @Test func anUnpickedHunkFoldsToItsCountsAlone() {
        let folded = document.foldingHunks(allRows(), keeping: [2])
        #expect(
            folded == [.line(1), .line(2), .hunk(additions: 2, deletions: 2)]
                + (12...15).map { .line($0) })
        #expect(document.foldingHunks(allRows(), keeping: [1, 2]) == allRows())
        #expect(
            document.foldingHunks(allRows(), keeping: [9])
                == [
                    .line(1), .line(2), .hunk(additions: 2, deletions: 2),
                    .hunk(additions: 1, deletions: 0),
                ])
    }

    @Test func aContextFoldInsideAFoldedHunkJoinsItsRow() {
        let context = document.displayRows(contextLines: 1)
        #expect(context.contains(.fold))
        let folded = document.foldingHunks(context, keeping: [2])
        #expect(!folded.contains(.fold))
        #expect(folded.prefix(3) == [.line(1), .line(2), .hunk(additions: 2, deletions: 2)])
        #expect(document.foldingHunks(context, keeping: [1]).contains(.fold))
    }

    @Test func oldAndNewNumberOnlyTheLinesEachSideHas() {
        let old = document.gutterLabels(.old)
        #expect(old.labels[2...6] == ["", "10", "11", "", "12"])
        #expect(old.columns == 2)
        let new = document.gutterLabels(.new)
        #expect(new.labels[2...6] == ["", "10", "", "11", "12"])
        #expect(new.labels[12...14] == ["98", "99", ""])
        let rows = document.gutterLabels(.rows, firstLineNumber: 3)
        #expect(rows.labels == (3...17).map(String.init))
        #expect(rows.columns == 2)
    }

    @Test func bothRightAlignsTheTwoColumns() {
        let both = document.gutterLabels(.both)
        #expect(both.columns == 5)
        #expect(both.labels[0] == "")
        #expect(both.labels[3] == "10 10")
        #expect(both.labels[4] == "11   ")
        #expect(both.labels[5] == "   11")
        let wide = DiffDocument(source: "@@ -998,2 +1000,2 @@\n a\n b")
        #expect(wide.gutterLabels(.both).labels[1] == " 998 1000")
    }

    @Test func aRedactedHeaderLeavesItsHunkUnnumbered() {
        let labels = document.gutterLabels(.both, redacting: [3...3]).labels
        #expect(labels[3...10].allSatisfy { $0.isEmpty })
        #expect(labels[12] == "98 98")
    }

    @Test func textWithoutAHeaderCountsFromTheFirstLine() {
        let labels = DiffDocument(source: " a\n-b\n+c").gutterLabels(.new, firstLineNumber: 5)
        #expect(labels.labels == ["5", "", "6"])
    }

    @Test func storedPicksAreSortedUniqueAndBounded() {
        #expect(SettingsDefaults.normalizeDiffHunks([3, 1, 3]) == [1, 3])
        #expect(SettingsDefaults.normalizeDiffHunks([0, -2, 20_000]) == nil)
        #expect(SettingsDefaults.normalizeDiffHunks([]) == nil)
    }
}
