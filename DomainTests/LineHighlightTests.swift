import Foundation
import Testing

@testable import VitrineDomain

// MARK: - Line-range parser

@Suite("LineHighlight parser")
struct LineHighlightParserTests {
    @Test func parsesASingleLine() {
        #expect(LineHighlight.parse("7") == [7...7])
    }

    @Test func parsesAHyphenatedRange() {
        #expect(LineHighlight.parse("7-9") == [7...9])
    }

    @Test func parsesMixedLinesAndRanges() {
        #expect(LineHighlight.parse("3, 7-9, 12") == [3...3, 7...9, 12...12])
    }

    @Test func toleratesWhitespaceAndNewlinesAndBlanks() {
        // Spaces around values and separators, stray commas, and newlines are all
        // forgiven (defensive behavior).
        #expect(LineHighlight.parse("  3 ,, 7 - 9 \n 12 ") == [3...3, 7...9, 12...12])
    }

    @Test func normalizesAReversedRange() {
        // "9-7" means the same selection as "7-9".
        #expect(LineHighlight.parse("9-7") == [7...9])
    }

    @Test func dropsZeroNegativeAndNonNumericFragments() {
        // Lines are 1-based, so 0 and negatives are meaningless; letters are junk.
        // Each bad fragment is skipped without failing the whole parse.
        #expect(LineHighlight.parse("0") == [])
        #expect(LineHighlight.parse("-4") == [])
        #expect(LineHighlight.parse("abc") == [])
        #expect(LineHighlight.parse("1-2-3") == [])
        #expect(LineHighlight.parse("5, oops, 8") == [5...5, 8...8])
    }

    @Test func emptyStringParsesToNoRanges() {
        #expect(LineHighlight.parse("") == [])
        #expect(LineHighlight.parse("   ") == [])
    }

    @Test func mergesOverlappingRanges() {
        #expect(LineHighlight.parse("3-5, 4-7") == [3...7])
    }

    @Test func mergesAdjacentRanges() {
        // Touching ranges collapse so the selection has one canonical shape.
        #expect(LineHighlight.parse("1-2, 3-3") == [1...3])
        #expect(LineHighlight.parse("1, 2, 3") == [1...3])
    }

    @Test func sortsOutOfOrderInput() {
        #expect(LineHighlight.parse("12, 3, 7-9") == [3...3, 7...9, 12...12])
    }

    @Test func containsChecksMembership() {
        let ranges = LineHighlight.parse("3, 7-9")
        #expect(LineHighlight.contains(ranges, line: 3))
        #expect(LineHighlight.contains(ranges, line: 8))
        #expect(!LineHighlight.contains(ranges, line: 4))
        #expect(!LineHighlight.contains(ranges, line: 10))
    }

    /// `normalize` tested adjacency as `lowerBound <= upperBound + 1`, which overflows and
    /// traps when an upper bound is `Int.max`. The spec comes from user text — a
    /// `--highlight-lines`/`--redact-lines` value, or the inspector field, which parses on
    /// every keystroke — so typing this aborted the process (SIGTRAP, exit 133). Two
    /// ranges are required: a single huge range never reaches the merge comparison.
    @Test func extremeUpperBoundMergesInsteadOfTrapping() {
        let huge = String(Int.max)
        #expect(LineHighlight.parse("1-\(huge),5") == [1...Int.max])
        #expect(LineHighlight.parse("5,1-\(huge)") == [1...Int.max])
        #expect(LineHighlight.parse("\(huge),\(huge)") == [Int.max...Int.max])
    }

    /// `normalize` is public and takes arbitrary ranges, so the lower edge is reachable
    /// too: a second range starting at `Int.min` used to trap on `lowerBound - 1`.
    @Test func extremeLowerBoundMergesInsteadOfTrapping() {
        let floor = Int.min
        #expect(LineHighlight.normalize([floor...floor, floor...floor]) == [floor...floor])
        #expect(LineHighlight.normalize([floor...floor, (floor + 1)...5]) == [floor...5])
        #expect(
            LineHighlight.normalize([floor...floor, (floor + 2)...5]) == [
                floor...floor, (floor + 2)...5,
            ])
        #expect(LineHighlight.normalize([1...Int.max, 1...Int.max]) == [1...Int.max])
        #expect(LineHighlight.normalize([floor...Int.max, 3...4]) == [floor...Int.max])
    }

    @Test func mergeSemanticsAreUnchangedByTheOverflowGuard() {
        // The rewritten comparison must keep adjacency and gaps behaving exactly as before.
        #expect(LineHighlight.parse("1-2, 3-3") == [1...3])  // adjacent: merges
        #expect(LineHighlight.parse("1-2, 4-4") == [1...2, 4...4])  // one-line gap: stays split
        #expect(LineHighlight.parse("1-1, 2-2") == [1...2])
        #expect(LineHighlight.normalize([]) == [])
    }
}

@Suite("LineHighlight describe / round-trip")
struct LineHighlightDescribeTests {
    @Test func describesSingleLinesAndRanges() {
        #expect(LineHighlight.describe([3...3, 7...9, 12...12]) == "3, 7-9, 12")
    }

    @Test func describeNormalizesBeforePrinting() {
        // Unsorted, overlapping input still prints the canonical string.
        #expect(LineHighlight.describe([7...9, 3...3, 8...8]) == "3, 7-9")
    }

    @Test func describeOfEmptyIsEmptyString() {
        #expect(LineHighlight.describe([]) == "")
    }

    @Test func parseDescribeRoundTripsCanonicalForm() {
        for spec in ["3, 7-9, 12", "1-3", "5", "10, 20-22"] {
            let ranges = LineHighlight.parse(spec)
            #expect(LineHighlight.describe(ranges) == spec)
            // And describing then re-parsing is a fixed point.
            #expect(LineHighlight.parse(LineHighlight.describe(ranges)) == ranges)
        }
    }
}
