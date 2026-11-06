import Foundation

/// One word, number or punctuation mark of source text, at its 0-based line and column.
public struct CodeToken: Equatable, Sendable {
    public let text: String
    public let line: Int
    /// In characters, so a monospaced font places the token at `column` advances.
    public let column: Int
    /// The token's start in the source's UTF-16 view, where highlighter attributes live.
    public let utf16Offset: Int

    /// Words (letters, digits, `_`) stay whole; every other visible character stands alone.
    /// `nil` as soon as there are more than `limit` tokens.
    public static func tokens(in source: String, limit: Int = .max) -> [CodeToken]? {
        var tokens: [CodeToken] = []
        var word = ""
        var start = (column: 0, utf16: 0)
        var (line, column, utf16) = (0, 0, 0)
        func flush() {
            guard !word.isEmpty else { return }
            tokens.append(
                CodeToken(text: word, line: line, column: start.column, utf16Offset: start.utf16))
            word = ""
        }
        for character in source {
            if character.isLetter || character.isNumber || character == "_" {
                if word.isEmpty { start = (column, utf16) }
                word.append(character)
            } else {
                flush()
                if character.isNewline {
                    (line, column) = (line + 1, -1)
                } else if !character.isWhitespace {
                    tokens.append(
                        CodeToken(
                            text: String(character), line: line, column: column, utf16Offset: utf16
                        ))
                }
            }
            guard tokens.count <= limit else { return nil }
            column += 1
            utf16 += character.utf16.count
        }
        flush()
        return tokens.count <= limit ? tokens : nil
    }
}

/// How one code step becomes the next: each token of the longest common token subsequence
/// moves to its new place, and every other token leaves or enters.
public struct CodeStepTransition: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        case moved(from: CodeToken, to: CodeToken)
        case removed(CodeToken)
        case inserted(CodeToken)
    }

    /// Old tokens in order, then the new tokens no old one moved to.
    public let changes: [Change]

    /// Past this many tokens in either step there is no transition. It bounds the LCS table
    /// to `tokenLimit²` two-byte cells.
    public static let tokenLimit = 1500

    /// Deterministic; `nil` past the limit.
    public static func between(_ old: String, _ new: String) -> CodeStepTransition? {
        guard let before = CodeToken.tokens(in: old, limit: tokenLimit),
            let after = CodeToken.tokens(in: new, limit: tokenLimit)
        else { return nil }
        // Interned, so the table compares integers rather than strings.
        var symbols: [String: Int] = [:]
        func intern(_ token: CodeToken) -> Int {
            if let symbol = symbols[token.text] { return symbol }
            symbols[token.text] = symbols.count
            return symbols.count - 1
        }
        let match = matches(before.map(intern), after.map(intern))
        var targeted = [Bool](repeating: false, count: after.count)
        var changes: [Change] = []
        for (index, token) in before.enumerated() {
            if let target = match[index] {
                targeted[target] = true
                changes.append(.moved(from: token, to: after[target]))
            } else {
                changes.append(.removed(token))
            }
        }
        for (index, token) in after.enumerated() where !targeted[index] {
            changes.append(.inserted(token))
        }
        return CodeStepTransition(changes: changes)
    }

    /// For each old token, the new token it is the same as.
    private static func matches(_ old: [Int], _ new: [Int]) -> [Int?] {
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
        var (i, j) = (0, 0)
        while i < rows, j < columns {
            if old[prefix + i] == new[prefix + j] {
                result[prefix + i] = prefix + j
                (i, j) = (i + 1, j + 1)
            } else if lengths[(i + 1) * width + j] >= lengths[i * width + j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return result
    }
}
