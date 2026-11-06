import Foundation
import Testing

@testable import VitrineDomain

@Suite("LineMarks")
struct LineMarksTests {
    @Test func toggleAddsThenRemovesAMark() {
        var marks = LineMarks(highlighted: [2...3])
        marks.toggle(.highlight, on: 4...5)
        #expect(marks.highlighted == [2...5])
        marks.toggle(.highlight, on: 3...4)
        #expect(marks.highlighted == [2...2, 5...5])
        #expect(marks.redacted.isEmpty)
    }

    @Test func togglePartiallyCoveredRangeFillsIt() {
        var marks = LineMarks(redacted: [4...4])
        marks.toggle(.redact, on: 3...5)
        #expect(marks.redacted == [3...5])
        #expect(marks.covers(3...5, with: .redact))
        #expect(!marks.covers(3...6, with: .redact))
    }

    @Test func clearRemovesBothMarksOnlyInsideTheRange() {
        var marks = LineMarks(highlighted: [1...6], redacted: [5...8])
        #expect(marks.touches(6...6))
        marks.clear(5...6)
        #expect(marks.highlighted == [1...4])
        #expect(marks.redacted == [7...8])
        #expect(!marks.touches(5...6))
        #expect(marks.contains(.redact, line: 7))
        #expect(!marks.contains(.highlight, line: 5))
        #expect(!marks.isEmpty)
        marks.clear(1...8)
        #expect(marks.isEmpty)
    }

    @Test func subtractingKeepsUntouchedRangesNormalized() {
        #expect(LineHighlight.subtracting(10...12, from: [9...9, 1...3]) == [1...3, 9...9])
        #expect(LineHighlight.subtracting(1...3, from: [1...3]) == [])
    }

    private func edit(
        line: Int, removed: Int = 0, inserted: Int = 0, atStart: Bool = false, atEnd: Bool = false
    ) -> LineEdit {
        LineEdit(
            line: line, removedBreaks: removed, insertedBreaks: inserted,
            startsAtLineStart: atStart, endsAtLineEnd: atEnd)
    }

    @Test func insertingLinesAboveMovesTheMarksDown() {
        let marks = LineMarks(highlighted: [3...4], redacted: [6...6])
        // Return at the end of line 2.
        #expect(
            marks.adjusted(for: edit(line: 2, inserted: 1, atEnd: true))
                == LineMarks(highlighted: [4...5], redacted: [7...7]))
        // Two lines pasted at the start of line 3: its text moves to line 5.
        #expect(
            marks.adjusted(for: edit(line: 3, inserted: 2, atStart: true))
                == LineMarks(highlighted: [5...6], redacted: [8...8]))
    }

    @Test func insertingInsideARangeGrowsIt() {
        let marks = LineMarks(highlighted: [3...5], redacted: [8...8])
        #expect(marks.adjusted(for: edit(line: 4, inserted: 1)).highlighted == [3...6])
        // Splitting a redacted line keeps both halves hidden.
        #expect(marks.adjusted(for: edit(line: 8, inserted: 1)).redacted == [8...9])
        // A new line after the last marked one starts unmarked.
        #expect(
            marks.adjusted(for: edit(line: 5, inserted: 1, atEnd: true)).highlighted == [3...5])
        #expect(marks.adjusted(for: edit(line: 9, inserted: 3)) == marks)
    }

    @Test func deletingLinesAboveMovesTheMarksUp() {
        let marks = LineMarks(highlighted: [6...7], redacted: [9...9])
        // Lines 3 and 4 deleted whole, from the start of line 3.
        #expect(
            marks.adjusted(for: edit(line: 3, removed: 2, atStart: true))
                == LineMarks(highlighted: [4...5], redacted: [7...7]))
        // The break at the end of line 2 deleted: line 3 joins it.
        #expect(
            marks.adjusted(for: edit(line: 2, removed: 1, atEnd: false))
                == LineMarks(highlighted: [5...6], redacted: [8...8]))
    }

    @Test func deletingAcrossARangeShrinksHighlightsAndKeepsRedactions() {
        let marks = LineMarks(highlighted: [4...6], redacted: [5...5])
        // From the middle of line 3 to the middle of line 5: lines 4 and 5 join line 3.
        let merged = marks.adjusted(for: edit(line: 3, removed: 2))
        #expect(merged.highlighted == [4...4])
        #expect(merged.redacted == [3...3])
        // Lines 4–6 deleted whole: the highlight goes, the redaction stays on what follows.
        let deleted = marks.adjusted(for: edit(line: 4, removed: 3, atStart: true))
        #expect(deleted.highlighted.isEmpty)
        #expect(deleted.redacted == [4...4])
    }

    @Test func labelNamesALineOrARun() {
        #expect(LineHighlight.label(7...7) == "7")
        #expect(LineHighlight.label(4...6) == "4–6")
    }
}
