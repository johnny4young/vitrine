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

    @Test func labelNamesALineOrARun() {
        #expect(LineHighlight.label(7...7) == "7")
        #expect(LineHighlight.label(4...6) == "4–6")
    }
}
