import Foundation

/// How a diff is laid out: one column, or the old and new file side by side.
public enum DiffViewMode: String, CaseIterable, Codable, Sendable {
    case unified, split
}

public struct DiffLinePair: Equatable, Sendable {
    public var old: Int
    public var new: Int
}

/// One side of a split row: the 1-based source row it draws and that side's file line,
/// unknown when the hunk header that numbers it is redacted.
public struct DiffSplitCell: Equatable, Sendable {
    public var row: Int
    public var number: Int?
}

/// A row of the split layout: a header, note or fold across both sides, or an old/new pair.
public enum DiffSplitRow: Equatable, Sendable {
    case spanning(DiffDisplayRow)
    case pair(old: DiffSplitCell?, new: DiffSplitCell?)
}

extension DiffDocument {
    /// Lays `rows` out side by side. Context shows on both sides, each run of removals pairs
    /// with the additions after it, and headers, notes and folds span both sides. Line
    /// numbers come from the hunk headers; text without one counts from `firstLineNumber`.
    public func splitRows(
        _ rows: [DiffDisplayRow], firstLineNumber: Int = 1,
        redacting redactions: [ClosedRange<Int>] = []
    ) -> [DiffSplitRow] {
        let numbers = sideLineNumbers(firstLineNumber: firstLineNumber, redacting: redactions)
        var result: [DiffSplitRow] = []
        var removed: [DiffSplitCell] = []
        var added: [DiffSplitCell] = []
        var previous: DiffDocument.RowKind?
        func flush() {
            for index in 0..<max(removed.count, added.count) {
                result.append(
                    .pair(
                        old: removed.indices.contains(index) ? removed[index] : nil,
                        new: added.indices.contains(index) ? added[index] : nil))
            }
            (removed, added) = ([], [])
        }
        for row in rows {
            guard case .line(let line) = row, rowKinds.indices.contains(line - 1) else {
                flush()
                result.append(.spanning(row))
                previous = nil
                continue
            }
            let side = numbers[line - 1]
            let kind = rowKinds[line - 1]
            defer { previous = kind }
            switch kind {
            case .deletion:
                if !added.isEmpty { flush() }
                removed.append(DiffSplitCell(row: line, number: side?.old))
            case .addition:
                added.append(DiffSplitCell(row: line, number: side?.new))
            case .context:
                flush()
                result.append(
                    .pair(
                        old: DiffSplitCell(row: line, number: side?.old),
                        new: DiffSplitCell(row: line, number: side?.new)))
            // A note belongs to the line before it, so it stays on that line's side.
            case .note where previous == .deletion:
                removed.append(DiffSplitCell(row: line, number: nil))
            case .note where previous == .addition:
                added.append(DiffSplitCell(row: line, number: nil))
            case .outside, .hunkHeader, .note:
                flush()
                result.append(.spanning(row))
            }
        }
        flush()
        return result
    }

    /// Each row's line in the old and new file. A hunk whose header is redacted or names no
    /// lines stays unnumbered, so the image never shows the lines a redaction hid, and the
    /// masked header a shared link carries reads the same way.
    private func sideLineNumbers(
        firstLineNumber: Int, redacting redactions: [ClosedRange<Int>]
    ) -> [DiffLinePair?] {
        var next: DiffLinePair? = DiffLinePair(old: firstLineNumber, new: firstLineNumber)
        var numbers: [DiffLinePair?] = []
        numbers.reserveCapacity(rowKinds.count)
        for (index, kind) in rowKinds.enumerated() {
            if kind == .hunkHeader {
                next =
                    LineHighlight.contains(redactions, line: index + 1)
                    ? nil : hunkStarts[index]
            }
            numbers.append(next)
            guard let pair = next else { continue }
            let old = pair.old.addingReportingOverflow(
                kind == .context || kind == .deletion ? 1 : 0)
            let new = pair.new.addingReportingOverflow(
                kind == .context || kind == .addition ? 1 : 0)
            next =
                old.overflow || new.overflow
                ? nil : DiffLinePair(old: old.partialValue, new: new.partialValue)
        }
        return numbers
    }
}
