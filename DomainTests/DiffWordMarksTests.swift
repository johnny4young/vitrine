import Foundation
import Testing

@testable import VitrineDomain

@Suite("Diff word marks")
struct DiffWordMarksTests {
    private func marks(
        _ source: String, redacting: [ClosedRange<Int>] = []
    ) -> [Int: [Range<Int>]] {
        let lines = source.components(separatedBy: "\n")
        return DiffDocument(source: source).wordMarks(lines: lines, redacting: redacting)
    }

    private func marked(_ line: String, _ spans: [Range<Int>]?) -> [String] {
        let characters = Array(line)
        return (spans ?? []).map { String(characters[$0]) }
    }

    @Test func aReplacedLineMarksOnlyTheWordsThatChanged() {
        let source = """
            @@ -1,3 +1,3 @@
             context
            -let second = "the old value"
            +let second = "the new value"
             more
            """
        let result = marks(source)
        #expect(marked("-let second = \"the old value\"", result[3]) == ["old"])
        #expect(marked("+let second = \"the new value\"", result[4]) == ["new"])
        #expect(result.keys.sorted() == [3, 4])
    }

    @Test func neighbouringChangesJoinAcrossWhitespace() {
        let source = "@@ -1 +1 @@\n-let a = value(1)\n+var b = value(1)"
        let result = marks(source)
        #expect(marked("-let a = value(1)", result[2]) == ["let a"])
        #expect(marked("+var b = value(1)", result[3]) == ["var b"])
    }

    @Test func aBlockPairsItsLinesInOrder() {
        let source = """
            @@ -1,2 +1,2 @@
            -first line one
            -second line two
            +first line 1
            +second line 2
            """
        let result = marks(source)
        #expect(marked("-first line one", result[2]) == ["one"])
        #expect(marked("-second line two", result[3]) == ["two"])
        #expect(marked("+first line 1", result[4]) == ["1"])
        #expect(marked("+second line 2", result[5]) == ["2"])
    }

    @Test func unlikeLinesAndLopsidedBlocksStayUnmarked() {
        #expect(marks("@@ -1 +1 @@\n-return total\n+print(\"hello world\")").isEmpty)
        #expect(marks("@@ -1 +1,3 @@\n-value a\n+value b\n+value c\n+value d").isEmpty)
        #expect(marks("@@ -1 +1,2 @@\n-value a\n+value b\n+value c").keys.sorted() == [2, 3])
        #expect(marks("@@ -1 +1 @@\n-same text\n+same text").isEmpty)
        #expect(marks("@@ -0,0 +1 @@\n+only added").isEmpty)
    }

    @Test func contextOrAnAdditionFirstBreaksTheBlock() {
        #expect(marks("@@ -1,2 +1,2 @@\n-value a\n context\n+value b").isEmpty)
        #expect(marks("@@ -1 +1 @@\n+value b\n-value a").isEmpty)
    }

    @Test func aNoNewlineNoteDoesNotBreakThePair() {
        let source = "@@ -1 +1 @@\n-value a\n\\ No newline at end of file\n+value b"
        #expect(marks(source).keys.sorted() == [2, 4])
    }

    @Test func combinedDiffsAreLeftUnmarked() {
        #expect(marks("@@@ -1 -1 +1 @@@\n- value a\n+ value b").isEmpty)
    }

    @Test func aRedactedLineHidesItsMarksAndItsPartners() {
        let source = """
            @@ -1,2 +1,2 @@
            -token = "abc123"
            -name = "old"
            +token = "xyz789"
            +name = "new"
            """
        #expect(marks(source).keys.sorted() == [2, 3, 4, 5])
        #expect(marks(source, redacting: [2...2]).keys.sorted() == [3, 5])
        #expect(marks(source, redacting: [4...4]).keys.sorted() == [3, 5])
    }

    @Test func longLinesAndAnExhaustedBudgetStayUnmarked() {
        let long = Array(repeating: "word", count: 200).joined(separator: " ")
        #expect(marks("@@ -1 +1 @@\n-\(long) a\n+\(long) b").isEmpty)

        var budget = 10
        #expect(DiffWordMarks.changedSpans("-value a", "+value b", budget: &budget) == nil)
        #expect(budget == 10)
        budget = DiffWordMarks.cellBudget
        #expect(DiffWordMarks.changedSpans("-value a", "+value b", budget: &budget) != nil)
        #expect(budget == DiffWordMarks.cellBudget - 16)
    }

    @Test func aHugeLineIsRejectedBeforeItIsTokenized() {
        let huge = String(repeating: "a,", count: 1_000_000)
        var budget = DiffWordMarks.cellBudget
        #expect(DiffWordMarks.changedSpans("-\(huge)x", "+\(huge)y", budget: &budget) == nil)
        #expect(budget == DiffWordMarks.cellBudget)
        #expect(marks("@@ -1 +1 @@\n-\(huge)x\n+\(huge)y").isEmpty)

        let many = Array(repeating: "a", count: DiffWordMarks.tokenLimit).joined(separator: ",")
        #expect(DiffWordMarks.tokens(Array(many)[...]) == nil)
    }

    @Test func eachCJKCharacterIsItsOwnToken() {
        let result = marks("@@ -1 +1 @@\n-这是一个测试\n+这是一个实验")
        #expect(marked("-这是一个测试", result[2]) == ["测试"])
        #expect(marked("+这是一个实验", result[3]) == ["实验"])
        #expect(DiffWordMarks.tokens(Array("かなハングル한글")[...])?.count == 8)
    }

    @Test func sharedIndentationDoesNotMakeLinesAlike() {
        let indent = String(repeating: " ", count: 8)
        #expect(marks("@@ -1 +1 @@\n-\(indent)foo(alpha)\n+\(indent)bar(beta)").isEmpty)
        let related = marks("@@ -1 +1 @@\n-\(indent)let value = 1\n+\(indent)let value = 2")
        #expect(marked("+\(indent)let value = 2", related[3]) == ["2"])
        #expect(marks("@@ -1 +1 @@\n-\(indent)\n+  ").isEmpty)
    }

    @Test func mismatchedLinesProduceNoMarks() {
        let document = DiffDocument(source: "@@ -1 +1 @@\n-value a\n+value b")
        #expect(document.wordMarks(lines: ["-value a"]).isEmpty)
    }

    @Test func tokensSplitWordsSpacesAndSymbols() {
        let characters = Array("ab_1  (x)")
        #expect(DiffWordMarks.tokens(characters[...]) == [0..<4, 4..<6, 6..<7, 7..<8, 8..<9])
    }
}
