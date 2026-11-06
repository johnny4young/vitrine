import Foundation
import Testing

@testable import VitrineDomain

@Suite("Code step transition")
struct CodeStepTransitionTests {
    private func tokens(_ source: String) -> [CodeToken] {
        CodeToken.tokens(in: source) ?? []
    }

    private func token(_ text: String, _ line: Int, _ column: Int, in source: String) -> CodeToken {
        tokens(source).first { $0.text == text && $0.line == line && $0.column == column }
            ?? CodeToken(text: "missing", line: -1, column: -1, utf16Offset: -1)
    }

    @Test func tokensKeepWordsWholeAndSkipWhitespace() {
        let tokens = tokens("let a_1 = f(x)\n  é→ 2")
        #expect(tokens.map(\.text) == ["let", "a_1", "=", "f", "(", "x", ")", "é", "→", "2"])
        #expect(tokens[1].column == 4)
        #expect((tokens[7].line, tokens[7].column) == (1, 2))
        #expect(tokens[8].column == 3)
        #expect(tokens[9].column == 5)
    }

    @Test func utf16OffsetsPointAtTheTokenInTheSource() {
        let source = "a 👍 bc"
        let bc = tokens(source)[2]
        let utf16 = Array(source.utf16)
        #expect(bc.text == "bc")
        #expect(bc.column == 4)
        #expect(
            String(utf16CodeUnits: Array(utf16[bc.utf16Offset..<bc.utf16Offset + 2]), count: 2)
                == "bc")
    }

    @Test func tokenizingStopsPastTheLimit() {
        #expect(CodeToken.tokens(in: "a b c", limit: 2) == nil)
        #expect(CodeToken.tokens(in: "a b", limit: 2)?.count == 2)
        #expect(CodeToken.tokens(in: "ab", limit: 1)?.count == 1)
    }

    @Test func anInsertedLineMovesWhatFollowsAndFadesInItsTokens() throws {
        let old = "func greet() {\n    return name\n}"
        let new = "func greet() {\n    let trimmed = name\n    return trimmed\n}"
        let transition = try #require(CodeStepTransition.between(old, new))
        let inserted = transition.changes.compactMap { change -> String? in
            if case .inserted(let token) = change { return token.text }
            return nil
        }
        #expect(inserted.count == 5)
        #expect(
            transition.changes.contains(
                .moved(from: token("}", 2, 0, in: old), to: token("}", 3, 0, in: new))))
    }

    @Test func removedTokensLeave() throws {
        let transition = try #require(CodeStepTransition.between("a b c", "a c"))
        #expect(
            transition.changes == [
                .moved(from: token("a", 0, 0, in: "a b c"), to: token("a", 0, 0, in: "a c")),
                .removed(token("b", 0, 2, in: "a b c")),
                .moved(from: token("c", 0, 4, in: "a b c"), to: token("c", 0, 2, in: "a c")),
            ])
    }

    @Test func tokensOutOfOrderFadeInsteadOfFlying() throws {
        let transition = try #require(CodeStepTransition.between("one\ntwo", "two\none"))
        let moved = transition.changes.filter { if case .moved = $0 { true } else { false } }
        #expect(moved.count == 1)
        #expect(transition.changes.count == 3)
    }

    @Test func theTransitionIsDeterministic() {
        #expect(
            CodeStepTransition.between("x = 1\ny = 2", "z = 0\nx = 1\ny = 3")
                == CodeStepTransition.between("x = 1\ny = 2", "z = 0\nx = 1\ny = 3"))
    }

    @Test func identicalStepsOnlyMoveInPlace() throws {
        let code = "print(\"hi\")"
        let transition = try #require(CodeStepTransition.between(code, code))
        #expect(transition.changes == tokens(code).map { .moved(from: $0, to: $0) })
    }

    @Test func emptyStepsHaveNothingToMatch() throws {
        #expect(try #require(CodeStepTransition.between("", "")).changes.isEmpty)
        #expect(try #require(CodeStepTransition.between("", "a b")).changes.count == 2)
    }

    @Test func stepsPastTheLimitHaveNoTransition() {
        let tooLong = String(repeating: "a ", count: CodeStepTransition.tokenLimit + 1)
        #expect(CodeStepTransition.between(tooLong, "a") == nil)
        #expect(CodeStepTransition.between("a", tooLong) == nil)
    }

    @Test func entirelyDifferentStepsAtTheLimitStayFast() throws {
        let half = CodeStepTransition.tokenLimit / 2
        let left = (0..<half).map { "l\($0);" }.joined(separator: " ")
        let right = (0..<half).map { "r\($0);" }.joined(separator: " ")
        let clock = ContinuousClock()
        let start = clock.now
        let transition = try #require(CodeStepTransition.between(left, right))
        #expect(clock.now - start < .seconds(3))
        #expect(transition.changes.count == 4 * half - half)
    }
}
