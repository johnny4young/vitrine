import Foundation
import Testing

@testable import VitrineDomain

@Suite("Code step transition")
struct CodeStepTransitionTests {
    private typealias Change = CodeStepTransition.Change

    @Test func tokensKeepWordsWholeAndSkipWhitespace() {
        let tokens = CodeToken.tokens(in: "let a_1 = f(x)\n  é→ 2")
        #expect(tokens.map(\.text) == ["let", "a_1", "=", "f", "(", "x", ")", "é", "→", "2"])
        #expect(tokens[1].column == 4)
        #expect(tokens[7].line == 1)
        #expect(tokens[7].column == 2)
        #expect(tokens[8].column == 3)
        #expect(tokens[9].column == 5)
    }

    @Test func utf16OffsetsPointAtTheTokenInTheSource() {
        let source = "a 👍 bc"
        let tokens = CodeToken.tokens(in: source)
        let utf16 = Array(source.utf16)
        let bc = tokens[2]
        #expect(bc.text == "bc")
        #expect(
            String(utf16CodeUnits: Array(utf16[bc.utf16Offset..<bc.utf16Offset + 2]), count: 2)
                == "bc")
        #expect(bc.column == 4)
    }

    @Test func anInsertedLineMovesWhatFollowsAndFadesInItsTokens() throws {
        let old = "func greet() {\n    return name\n}"
        let new = "func greet() {\n    let trimmed = name\n    return trimmed\n}"
        let transition = try #require(CodeStepTransition.between(old, new))

        let inserted = transition.items.compactMap { item -> String? in
            if case .inserted(let token) = item.change { return token.text }
            return nil
        }
        let removed = transition.items.compactMap { item -> String? in
            if case .removed(let token) = item.change { return token.text }
            return nil
        }
        #expect(
            inserted == ["let", "trimmed", "=", "trimmed"])
        #expect(removed.isEmpty)
        let brace = try #require(
            transition.items.last { item in
                if case .moved(let from, _) = item.change { return from.text == "}" }
                return false
            })
        #expect(
            brace.change == .moved(from: token("}", 2, 0, in: old), to: token("}", 3, 0, in: new)))
    }

    @Test func removedTokensLeave() throws {
        let transition = try #require(CodeStepTransition.between("a b c", "a c"))
        #expect(
            transition.items.map(\.change) == [
                .moved(from: token("a", 0, 0, in: "a b c"), to: token("a", 0, 0, in: "a c")),
                .removed(token("b", 0, 2, in: "a b c")),
                .moved(from: token("c", 0, 4, in: "a b c"), to: token("c", 0, 2, in: "a c")),
            ])
    }

    @Test func swappedLinesGlideInsteadOfFading() throws {
        let transition = try #require(CodeStepTransition.between("one\ntwo", "two\none"))
        #expect(transition.items.allSatisfy { if case .moved = $0.change { true } else { false } })
        #expect(transition.items.count == 2)
    }

    @Test func identitiesAreStableAndUnique() throws {
        let old = "x = 1\ny = 2"
        let new = "z = 0\nx = 1\ny = 3"
        let transition = try #require(CodeStepTransition.between(old, new))
        let ids = transition.items.map(\.id)
        #expect(Set(ids).count == ids.count)
        let oldCount = CodeToken.tokens(in: old).count
        for item in transition.items {
            switch item.change {
            case .moved, .removed: #expect(item.id < oldCount)
            case .inserted: #expect(item.id >= oldCount)
            }
        }
        #expect(CodeStepTransition.between(old, new) == transition)
    }

    @Test func identicalStepsOnlyMoveInPlace() throws {
        let code = "print(\"hi\")"
        let transition = try #require(CodeStepTransition.between(code, code))
        for item in transition.items {
            guard case .moved(let from, let to) = item.change else {
                Issue.record("Expected every token to stay")
                continue
            }
            #expect(from == to)
        }
    }

    @Test func emptyStepsHaveNothingToMatch() throws {
        #expect(try #require(CodeStepTransition.between("", "")).items.isEmpty)
        let entering = try #require(CodeStepTransition.between("", "a b"))
        #expect(entering.items.map(\.id) == [0, 1])
    }

    @Test func inputsPastTheLimitsHaveNoTransition() {
        let tooLong = String(repeating: "a ", count: CodeStepTransition.tokenLimit + 1)
        #expect(CodeStepTransition.between(tooLong, "a") == nil)
        let left = (0..<2000).map { "l\($0)" }.joined(separator: " ")
        let right = (0..<2000).map { "r\($0)" }.joined(separator: " ")
        #expect(CodeStepTransition.between(left, right) == nil)
    }

    @Test func largeStepsSharingMostTokensStayFast() throws {
        let lines = (0..<800).map { "let value\($0) = compute(\($0))" }
        let old = lines.joined(separator: "\n")
        var edited = lines
        edited[500] = "let changed = compute(500)"
        let clock = ContinuousClock()
        let start = clock.now
        let transition = try #require(
            CodeStepTransition.between(old, edited.joined(separator: "\n")))
        #expect(clock.now - start < .seconds(2))
        let edit = token("value500", 500, 4, in: old)
        #expect(transition.items.contains { $0.change == .removed(edit) })
    }

    private func token(_ text: String, _ line: Int, _ column: Int, in source: String) -> CodeToken {
        CodeToken.tokens(in: source).first {
            $0.text == text && $0.line == line && $0.column == column
        }
            ?? CodeToken(text: "missing", line: -1, column: -1, utf16Offset: -1)
    }
}
