import Foundation

extension DiffDocument {
    /// The changed spans inside paired removed and added lines, as character offsets into each
    /// line keyed by its 1-based row. A replacement block pairs its lines in order; a pair that
    /// is too unlike, too long or touches a redacted row gets no marks on either side.
    public func wordMarks(
        lines: [String], redacting redactions: [ClosedRange<Int>] = []
    ) -> [Int: [Range<Int>]] {
        guard lines.count == rowKinds.count else { return [:] }
        var marks: [Int: [Range<Int>]] = [:]
        var budget = DiffWordMarks.cellBudget
        var removed: [Int] = []
        var added: [Int] = []
        var combined = false
        func flush() {
            defer { (removed, added) = ([], []) }
            guard !combined, DiffWordMarks.pairsBlock(removed.count, added.count) else { return }
            for (old, new) in zip(removed, added) {
                guard !LineHighlight.contains(redactions, line: old + 1),
                    !LineHighlight.contains(redactions, line: new + 1),
                    let spans = DiffWordMarks.changedSpans(lines[old], lines[new], budget: &budget)
                else { continue }
                if !spans.old.isEmpty { marks[old + 1] = spans.old }
                if !spans.new.isEmpty { marks[new + 1] = spans.new }
            }
        }
        for (index, kind) in rowKinds.enumerated() {
            switch kind {
            case .deletion:
                if !added.isEmpty { flush() }
                removed.append(index)
            case .addition:
                added.append(index)
            case .note:
                continue
            case .hunkHeader:
                flush()
                // A combined diff's rows carry one marker column per parent.
                combined = lines[index].hasPrefix("@@@")
            case .outside, .context:
                flush()
            }
        }
        flush()
        return marks
    }
}

enum DiffWordMarks {
    /// LCS cells one document may spend, so a huge diff costs a bounded amount of work.
    static let cellBudget = 1_000_000
    static let tokenLimit = 300
    /// Checked before a line is copied or tokenized, so a minified line costs nothing.
    static let lineByteLimit = 4_096
    /// The share of a pair's text that must survive for the pair to read as an edit.
    static let minimumSimilarity = 0.5

    /// A long run of lines against a short one is a rewrite, not a set of edits.
    static func pairsBlock(_ removed: Int, _ added: Int) -> Bool {
        let shorter = min(removed, added)
        return shorter > 0 && max(removed, added) <= shorter * 2
    }

    /// The changed spans of each line, skipping its diff marker, or `nil` when the pair is
    /// unlike, over a limit, or identical past the marker.
    static func changedSpans(
        _ old: String, _ new: String, budget: inout Int
    ) -> (old: [Range<Int>], new: [Range<Int>])? {
        guard old.utf8.count <= lineByteLimit, new.utf8.count <= lineByteLimit else { return nil }
        let a = Array(old)
        let b = Array(new)
        guard a.count > 1, b.count > 1, let tokensA = tokens(a[1...]),
            let tokensB = tokens(b[1...])
        else { return nil }
        let width = tokensB.count + 1
        let cells = (tokensA.count + 1) * width
        guard cells <= budget else { return nil }
        budget -= cells

        var ids: [ArraySlice<Character>: Int] = [:]
        func id(_ token: ArraySlice<Character>) -> Int {
            if let known = ids[token] { return known }
            ids[token] = ids.count
            return ids.count - 1
        }
        let idsA = tokensA.map { id(a[$0]) }
        let idsB = tokensB.map { id(b[$0]) }
        var lengths = [UInt16](repeating: 0, count: cells)
        for i in stride(from: idsA.count - 1, through: 0, by: -1) {
            for j in stride(from: idsB.count - 1, through: 0, by: -1) {
                lengths[i * width + j] =
                    idsA[i] == idsB[j]
                    ? lengths[(i + 1) * width + j + 1] + 1
                    : max(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
            }
        }
        var keptA = [Bool](repeating: false, count: idsA.count)
        var keptB = [Bool](repeating: false, count: idsB.count)
        // Shared indentation says nothing about whether two lines are related.
        let indentA = a.dropFirst().prefix(while: \.isWhitespace).count
        let indentB = b.dropFirst().prefix(while: \.isWhitespace).count
        var (i, j, common) = (0, 0, 0)
        while i < idsA.count, j < idsB.count {
            if idsA[i] == idsB[j] {
                (keptA[i], keptB[j]) = (true, true)
                if tokensA[i].lowerBound > indentA { common += tokensA[i].count }
                (i, j) = (i + 1, j + 1)
            } else if lengths[(i + 1) * width + j] >= lengths[i * width + j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        let total = a.count + b.count - 2 - indentA - indentB
        guard total > 0, common * 2 < total,
            Double(common * 2) / Double(total) >= minimumSimilarity
        else { return nil }
        return (spans(tokensA, kept: keptA, in: a), spans(tokensB, kept: keptB, in: b))
    }

    /// Unmatched tokens joined into spans, bridging the whitespace between two of them.
    private static func spans(
        _ tokens: [Range<Int>], kept: [Bool], in characters: [Character]
    ) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        for (index, token) in tokens.enumerated() where !kept[index] {
            if let last = spans.last,
                (last.upperBound..<token.lowerBound).allSatisfy({ characters[$0].isWhitespace })
            {
                spans[spans.count - 1] = last.lowerBound..<token.upperBound
            } else {
                spans.append(token)
            }
        }
        return spans
    }

    /// Runs of word characters, runs of whitespace, and single symbols or CJK characters, as
    /// offsets; `nil` past `tokenLimit`.
    static func tokens(_ characters: ArraySlice<Character>) -> [Range<Int>]? {
        enum Kind { case word, space, symbol }
        func kind(_ character: Character) -> Kind {
            // CJK text has no spaces between words, so each character stands alone.
            if isCJK(character) { return .symbol }
            if character.isLetter || character.isNumber || character == "_" { return .word }
            return character.isWhitespace ? .space : .symbol
        }
        var result: [Range<Int>] = []
        var index = characters.startIndex
        while index < characters.endIndex {
            let start = index
            let current = kind(characters[index])
            index += 1
            if current != .symbol {
                while index < characters.endIndex, kind(characters[index]) == current { index += 1 }
            }
            result.append(start..<index)
            if result.count > tokenLimit { return nil }
        }
        return result
    }

    /// Ideographs, kana and hangul.
    private static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        if scalar.properties.isIdeographic { return true }
        switch scalar.value {
        case 0x1100...0x11FF, 0x3040...0x30FF, 0x3130...0x318F, 0x31F0...0x31FF,
            0xAC00...0xD7AF, 0xFF66...0xFF9F:
            return true
        default:
            return false
        }
    }
}
