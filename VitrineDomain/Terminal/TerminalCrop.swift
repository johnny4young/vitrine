import Foundation

/// The rows and columns of a terminal capture's final screen that its image keeps, 1-based
/// and inclusive. `nil` keeps every row or column. It is applied to the rendered screen, so
/// the transcript itself is never edited.
public struct TerminalCrop: Codable, Hashable, Sendable {
    public static let maximum = 100_000

    public private(set) var rows: ClosedRange<Int>?
    public private(set) var columns: ClosedRange<Int>?

    public init(rows: ClosedRange<Int>? = nil, columns: ClosedRange<Int>? = nil) {
        self.rows = rows.map(Self.bounded)
        self.columns = columns.map(Self.bounded)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rows: try container.decodeIfPresent(ClosedRange<Int>.self, forKey: .rows),
            columns: try container.decodeIfPresent(ClosedRange<Int>.self, forKey: .columns))
    }

    public var isEmpty: Bool { rows == nil && columns == nil }

    /// How many screen rows sit above the first kept one.
    public var rowOffset: Int { (rows?.lowerBound ?? 1) - 1 }

    /// Renumbers screen rows to the cropped image's rows, dropping rows cut away.
    public func localRanges(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        guard let rows else { return ranges }
        return ranges.compactMap { range in
            guard range.overlaps(rows) else { return nil }
            let kept = range.clamped(to: rows)
            return (kept.lowerBound - rowOffset)...(kept.upperBound - rowOffset)
        }
    }

    /// One `first` or `first-last` span of positive numbers, either order; anything else,
    /// including a list, is `nil`. The CLI and the inspector both read spans with it.
    public static func span(_ text: String) -> ClosedRange<Int>? {
        let bounds = text.split(separator: "-", omittingEmptySubsequences: false).map {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        guard (1...2).contains(bounds.count), let low = bounds.first ?? nil,
            let high = bounds.last ?? nil, min(low, high) >= 1, max(low, high) <= maximum
        else { return nil }
        return min(low, high)...max(low, high)
    }

    /// Blur and spotlight boxes sit at fixed canvas positions, so a crop would move the
    /// content out from under them.
    public static func isBlocked(by annotations: [Annotation]) -> Bool {
        annotations.contains { $0.kind == .blur || $0.kind == .spotlight }
    }

    /// Keeps the cropped cells of rendered runs. A wide character cut by a column edge
    /// becomes a space, so the cells beside it keep their place; a tab expands to spaces.
    /// Marks and joiners go with the characters they attach, so a cut one leaves none.
    public func apply(to runs: [ANSIRun]) -> [ANSIRun] {
        guard !isEmpty else { return runs }
        var result: [ANSIRun] = []
        var row = 1
        var column = 1
        var keptBase = false
        var joiner: Unicode.Scalar?
        for run in runs {
            var text = String.UnicodeScalarView()
            for scalar in run.text.unicodeScalars {
                if scalar == "\n" {
                    if keeps(row: row), keeps(row: row + 1) { text.append(scalar) }
                    row += 1
                    column = 1
                    keptBase = false
                    joiner = nil
                    continue
                }
                guard keeps(row: row) else { continue }
                guard let columns else {
                    text.append(scalar)
                    continue
                }
                // A bar cursor draws over the cell that follows it without advancing.
                if run.style.isCursorBar || CharacterWidth.displayWidth(scalar) == 0 {
                    if run.style.isCursorBar {
                        if columns.contains(column) { text.append(scalar) }
                    } else if scalar == "\u{200D}" {
                        joiner = keptBase ? scalar : nil
                    } else if keptBase {
                        text.append(scalar)
                    }
                    continue
                }
                let width =
                    scalar == "\t" ? 8 - (column - 1) % 8 : CharacterWidth.displayWidth(scalar)
                let last = column + width - 1
                let inside = max(
                    0, min(last, columns.upperBound) - max(column, columns.lowerBound) + 1)
                keptBase = inside == width && scalar != "\t"
                if keptBase, let pending = joiner { text.append(pending) }
                joiner = nil
                if keptBase {
                    text.append(scalar)
                } else {
                    text.append(contentsOf: repeatElement(" ", count: inside))
                }
                column += width
            }
            if !text.isEmpty { result.append(ANSIRun(text: String(text), style: run.style)) }
        }
        return result
    }

    private func keeps(row: Int) -> Bool { rows?.contains(row) ?? true }

    private static func bounded(_ range: ClosedRange<Int>) -> ClosedRange<Int> {
        let low = min(max(range.lowerBound, 1), maximum)
        return low...min(max(range.upperBound, low), maximum)
    }
}
