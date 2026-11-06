import Foundation

/// A per-line state the code editor's gutter and selection actions can set.
public enum LineMark: Sendable, CaseIterable {
    case highlight
    case redact
}

/// The highlighted and redacted line ranges together, edited a range at a time.
///
/// Both lists stay normalized through `LineHighlight`, so a gutter edit and a typed spec
/// produce the same value.
public struct LineMarks: Equatable, Sendable {
    public var highlighted: [ClosedRange<Int>]
    public var redacted: [ClosedRange<Int>]

    public init(highlighted: [ClosedRange<Int>] = [], redacted: [ClosedRange<Int>] = []) {
        self.highlighted = highlighted
        self.redacted = redacted
    }

    public var isEmpty: Bool { highlighted.isEmpty && redacted.isEmpty }

    public func contains(_ mark: LineMark, line: Int) -> Bool {
        LineHighlight.contains(ranges(of: mark), line: line)
    }

    /// Whether every line in `range` carries `mark`.
    public func covers(_ range: ClosedRange<Int>, with mark: LineMark) -> Bool {
        LineHighlight.normalize(ranges(of: mark)).contains {
            $0.lowerBound <= range.lowerBound && range.upperBound <= $0.upperBound
        }
    }

    /// Whether any line in `range` carries any mark.
    public func touches(_ range: ClosedRange<Int>) -> Bool {
        (highlighted + redacted).contains { $0.overlaps(range) }
    }

    /// Adds `mark` to every line in `range`, or removes it from all of them when it
    /// already covers the range.
    public mutating func toggle(_ mark: LineMark, on range: ClosedRange<Int>) {
        let current = ranges(of: mark)
        let updated =
            covers(range, with: mark)
            ? LineHighlight.subtracting(range, from: current)
            : LineHighlight.normalize(current + [range])
        switch mark {
        case .highlight: highlighted = updated
        case .redact: redacted = updated
        }
    }

    /// Removes every mark from the lines in `range`.
    public mutating func clear(_ range: ClosedRange<Int>) {
        highlighted = LineHighlight.subtracting(range, from: highlighted)
        redacted = LineHighlight.subtracting(range, from: redacted)
    }

    private func ranges(of mark: LineMark) -> [ClosedRange<Int>] {
        switch mark {
        case .highlight: highlighted
        case .redact: redacted
        }
    }
}

extension LineHighlight {
    /// `ranges` without the lines in `removal`, normalized.
    public static func subtracting(
        _ removal: ClosedRange<Int>, from ranges: [ClosedRange<Int>]
    ) -> [ClosedRange<Int>] {
        normalize(ranges).flatMap { range -> [ClosedRange<Int>] in
            guard range.overlaps(removal) else { return [range] }
            var pieces: [ClosedRange<Int>] = []
            if range.lowerBound < removal.lowerBound {
                pieces.append(range.lowerBound...(removal.lowerBound - 1))
            }
            if removal.upperBound < range.upperBound {
                pieces.append((removal.upperBound + 1)...range.upperBound)
            }
            return pieces
        }
    }

    /// `4` or `4–6`, the way the editor names a line or a run of lines.
    public static func label(_ range: ClosedRange<Int>) -> String {
        range.count == 1 ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
    }
}

/// Where a text edit removed and inserted line breaks, so line marks can follow their text.
public struct LineEdit: Equatable, Sendable {
    /// The 1-based line the edit starts on.
    public var line: Int
    public var removedBreaks: Int
    public var insertedBreaks: Int
    /// Nothing precedes the edit on its line, so the line's remaining text moves with the edit.
    public var startsAtLineStart: Bool
    /// Nothing but the line break follows the edit on its line.
    public var endsAtLineEnd: Bool

    public init(
        line: Int, removedBreaks: Int, insertedBreaks: Int, startsAtLineStart: Bool,
        endsAtLineEnd: Bool
    ) {
        self.line = line
        self.removedBreaks = removedBreaks
        self.insertedBreaks = insertedBreaks
        self.startsAtLineStart = startsAtLineStart
        self.endsAtLineEnd = endsAtLineEnd
    }
}

extension LineMarks {
    /// The marks after `edit`, each on the text it was put on. A highlight on a deleted line
    /// goes away; a redaction on one moves to the line its text joins, so a merge never
    /// leaves a secret showing.
    public func adjusted(for edit: LineEdit) -> LineMarks {
        LineMarks(
            highlighted: Self.adjust(highlighted, for: edit, conservative: false),
            redacted: Self.adjust(redacted, for: edit, conservative: true))
    }

    private static func adjust(
        _ ranges: [ClosedRange<Int>], for edit: LineEdit, conservative: Bool
    ) -> [ClosedRange<Int>] {
        let line = edit.line
        let removed = edit.removedBreaks
        let inserted = edit.insertedBreaks
        var result: [ClosedRange<Int>] = []
        for range in ranges {
            var low = range.lowerBound
            var high = range.upperBound
            if removed > 0 {
                if conservative {
                    // Every touched line folds into the edit's line.
                    let fold = { (x: Int) in
                        x <= line ? x : x <= line + removed ? line : x - removed
                    }
                    low = fold(low)
                    high = fold(high)
                } else {
                    // The lines whose text is gone: the edit's own line when it starts there.
                    let gone =
                        edit.startsAtLineStart
                        ? line...(line + removed - 1) : (line + 1)...(line + removed)
                    let shift = { (x: Int) in x < gone.lowerBound ? x : x - removed }
                    low = gone.contains(low) ? gone.upperBound + 1 - removed : shift(low)
                    high = gone.contains(high) ? gone.lowerBound - 1 : shift(high)
                    guard low <= high else { continue }
                }
            }
            if inserted > 0, high >= line {
                if low > line {
                    low += inserted
                    high += inserted
                } else {
                    // The range holds the edit's line, whose text after the edit moves down.
                    if low == line, edit.startsAtLineStart { low += inserted }
                    if high > line || edit.startsAtLineStart || !edit.endsAtLineEnd {
                        high += inserted
                    }
                }
            }
            result.append(low...high)
        }
        return LineHighlight.normalize(result)
    }
}
