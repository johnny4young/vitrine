import Foundation

/// A hunk: the 1-based rows from its header through its last line, and its changed lines.
public struct DiffHunk: Equatable, Sendable {
    public var rows: ClosedRange<Int>
    public var additions: Int
    public var deletions: Int
}

/// What a diff's gutter numbers: the patch's own rows (the default), or the old file's lines,
/// the new file's, or both. Whether the gutter shows is the Line numbers switch's call.
public enum DiffLineNumbers: String, CaseIterable, Codable, Sendable {
    case rows, old, new, both
}

extension DiffDocument {
    /// The hunks in reading order. A hunk is picked by its 1-based position here.
    public var hunks: [DiffHunk] {
        var hunks: [DiffHunk] = []
        for (index, kind) in rowKinds.enumerated() {
            switch kind {
            case .hunkHeader:
                hunks.append(DiffHunk(rows: (index + 1)...(index + 1), additions: 0, deletions: 0))
            case .context, .addition, .deletion, .note:
                guard let last = hunks.indices.last, hunks[last].rows.upperBound == index else {
                    continue
                }
                hunks[last].rows = hunks[last].rows.lowerBound...(index + 1)
                if kind == .addition { hunks[last].additions += 1 }
                if kind == .deletion { hunks[last].deletions += 1 }
            case .outside:
                continue
            }
        }
        return hunks
    }

    /// `rows` with every hunk whose position is not in `kept` folded to its counts. `all` is
    /// this document's `hunks`, passed in when the caller already has them.
    public func foldingHunks(
        _ rows: [DiffDisplayRow], keeping kept: [Int], hunks all: [DiffHunk]? = nil
    ) -> [DiffDisplayRow] {
        let all = all ?? hunks
        let keep = Set(kept)
        var foldedHunk = [Int?](repeating: nil, count: rowKinds.count + 1)
        for (offset, hunk) in all.enumerated() where !keep.contains(offset + 1) {
            for row in hunk.rows { foldedHunk[row] = offset }
        }
        var result: [DiffDisplayRow] = []
        var emitted = Set<Int>()
        var followsFoldedLine = false
        for row in rows {
            if case .line(let line) = row, foldedHunk.indices.contains(line),
                let hunk = foldedHunk[line]
            {
                if emitted.insert(hunk).inserted {
                    result.append(
                        .hunk(additions: all[hunk].additions, deletions: all[hunk].deletions))
                }
                followsFoldedLine = true
                continue
            }
            // A context fold inside a folded hunk is already part of its row.
            if row == .fold, followsFoldedLine { continue }
            result.append(row)
            followsFoldedLine = false
        }
        return result
    }

    /// Each row's gutter label for `numbering`, and the digit columns the gutter needs. Only
    /// a line that exists on a side gets that side's number; `both` right-aligns the two.
    public func gutterLabels(
        _ numbering: DiffLineNumbers, firstLineNumber: Int = 1,
        redacting redactions: [ClosedRange<Int>] = []
    ) -> (labels: [String], columns: Int) {
        let numbers = sideLineNumbers(firstLineNumber: firstLineNumber, redacting: redactions)
        let sides = rowKinds.indices.map { index -> (old: Int?, new: Int?) in
            guard let pair = numbers[index] else { return (nil, nil) }
            switch rowKinds[index] {
            case .context: return (pair.old, pair.new)
            case .deletion: return (pair.old, nil)
            case .addition: return (nil, pair.new)
            case .outside, .hunkHeader, .note: return (nil, nil)
            }
        }
        let highest = sides.reduce(1) { max($0, $1.old ?? 0, $1.new ?? 0) }
        let digits = max(2, String(highest).count)
        func label(_ number: Int?) -> String { number.map(String.init) ?? "" }
        func padded(_ number: Int?) -> String {
            let text = label(number)
            return String(repeating: " ", count: digits - text.count) + text
        }
        switch numbering {
        case .old: return (sides.map { label($0.old) }, digits)
        case .new: return (sides.map { label($0.new) }, digits)
        case .rows:
            let labels = rowKinds.indices.map { String($0 + firstLineNumber) }
            return (labels, max(2, String(rowKinds.count + firstLineNumber - 1).count))
        case .both:
            let labels = sides.map { side in
                side.old == nil && side.new == nil ? "" : padded(side.old) + " " + padded(side.new)
            }
            return (labels, digits * 2 + 1)
        }
    }
}
