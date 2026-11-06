import Foundation

/// One word, number or punctuation mark of source text, at its 0-based line and column.
public struct CodeToken: Equatable, Sendable {
    public let text: String
    public let line: Int
    /// In characters, so a monospaced font places the token at `column` advances.
    public let column: Int
    /// The token's start in the source's UTF-16 view, where highlighter attributes live.
    public let utf16Offset: Int

    public init(text: String, line: Int, column: Int, utf16Offset: Int) {
        self.text = text
        self.line = line
        self.column = column
        self.utf16Offset = utf16Offset
    }

    /// Words (letters, digits, `_`) stay whole; every other visible character stands alone.
    public static func tokens(in source: String) -> [CodeToken] {
        var tokens: [CodeToken] = []
        var word = ""
        var wordStart = (column: 0, utf16: 0)
        var line = 0
        var column = 0
        var utf16 = 0
        func flush() {
            guard !word.isEmpty else { return }
            tokens.append(
                CodeToken(
                    text: word, line: line, column: wordStart.column, utf16Offset: wordStart.utf16))
            word = ""
        }
        for character in source {
            if character.isLetter || character.isNumber || character == "_" {
                if word.isEmpty { wordStart = (column, utf16) }
                word.append(character)
            } else {
                flush()
                if character.isNewline {
                    line += 1
                    column = -1
                } else if !character.isWhitespace {
                    tokens.append(
                        CodeToken(
                            text: String(character), line: line, column: column, utf16Offset: utf16
                        ))
                }
            }
            column += 1
            utf16 += character.utf16.count
        }
        flush()
        return tokens
    }
}

/// How one code step becomes the next: every token either moves (it exists in both steps,
/// possibly at a new position), leaves, or enters. Identities are stable: a moved or leaving
/// token keeps its index in the old step, an entering one takes `old.count + newIndex`.
public struct CodeStepTransition: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        case moved(from: CodeToken, to: CodeToken)
        case removed(CodeToken)
        case inserted(CodeToken)
    }

    public struct Item: Equatable, Sendable, Identifiable {
        public let id: Int
        public let change: Change
    }

    public let items: [Item]

    /// Above this many tokens in either step there is no transition, only the new step.
    public static let tokenLimit = 6000
    /// The LCS table's cell budget after the shared prefix and suffix are trimmed.
    public static let cellLimit = 2_000_000

    /// Matches the longest common token subsequence, then pairs leftover tokens with equal
    /// text in order, so a line that moved still glides. Deterministic; `nil` past the limits.
    public static func between(_ old: String, _ new: String) -> CodeStepTransition? {
        let before = CodeToken.tokens(in: old)
        let after = CodeToken.tokens(in: new)
        guard before.count <= tokenLimit, after.count <= tokenLimit else { return nil }
        // Interned, so the table compares integers rather than strings.
        var symbols: [String: Int] = [:]
        func intern(_ token: CodeToken) -> Int {
            if let symbol = symbols[token.text] { return symbol }
            symbols[token.text] = symbols.count
            return symbols.count - 1
        }
        let oldSymbols = before.map(intern)
        let newSymbols = after.map(intern)
        guard var match = matches(oldSymbols, newSymbols) else { return nil }
        pairLeftovers(oldSymbols, newSymbols, into: &match)

        var targeted = [Bool](repeating: false, count: after.count)
        var items: [Item] = []
        items.reserveCapacity(before.count + after.count)
        for (index, token) in before.enumerated() {
            if let target = match[index] {
                targeted[target] = true
                items.append(Item(id: index, change: .moved(from: token, to: after[target])))
            } else {
                items.append(Item(id: index, change: .removed(token)))
            }
        }
        for (index, token) in after.enumerated() where !targeted[index] {
            items.append(Item(id: before.count + index, change: .inserted(token)))
        }
        return CodeStepTransition(items: items)
    }

    /// For each old token, the new token it is the same as, by a bounded LCS.
    private static func matches(_ old: [Int], _ new: [Int]) -> [Int?]? {
        var result = [Int?](repeating: nil, count: old.count)
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
            result[prefix] = prefix
            prefix += 1
        }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
            old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
        {
            result[old.count - 1 - suffix] = new.count - 1 - suffix
            suffix += 1
        }
        let rows = old.count - prefix - suffix
        let columns = new.count - prefix - suffix
        guard rows > 0, columns > 0 else { return result }
        guard rows * columns <= cellLimit else { return nil }

        // lengths[i][j] is the LCS of old[prefix + i...] and new[prefix + j...].
        let width = columns + 1
        var lengths = [UInt16](repeating: 0, count: (rows + 1) * width)
        for i in stride(from: rows - 1, through: 0, by: -1) {
            for j in stride(from: columns - 1, through: 0, by: -1) {
                lengths[i * width + j] =
                    old[prefix + i] == new[prefix + j]
                    ? lengths[(i + 1) * width + j + 1] + 1
                    : max(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
            }
        }
        var i = 0
        var j = 0
        while i < rows, j < columns {
            if old[prefix + i] == new[prefix + j] {
                result[prefix + i] = prefix + j
                i += 1
                j += 1
            } else if lengths[(i + 1) * width + j] >= lengths[i * width + j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return result
    }

    private static func pairLeftovers(_ old: [Int], _ new: [Int], into match: inout [Int?]) {
        var claimed = [Bool](repeating: false, count: new.count)
        for target in match.compactMap(\.self) { claimed[target] = true }
        var free: [Int: [Int]] = [:]
        for (index, text) in new.enumerated() where !claimed[index] {
            free[text, default: []].append(index)
        }
        var next: [Int: Int] = [:]
        for (index, text) in old.enumerated() where match[index] == nil {
            guard let candidates = free[text] else { continue }
            let position = next[text, default: 0]
            guard position < candidates.count else { continue }
            match[index] = candidates[position]
            next[text] = position + 1
        }
    }
}
