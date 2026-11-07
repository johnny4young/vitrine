import Foundation

/// Pins a text callout to one line of the source text, so it follows that line through
/// layout changes instead of staying at a canvas point. `side` picks the old or new column
/// of a split diff; a unified diff draws every row once and accepts either.
public struct DiffLineAnchor: Hashable, Codable, Sendable {
    public enum Side: String, Codable, Sendable {
        case old, new
    }

    /// The 1-based source row.
    public var row: Int
    public var side: Side
    /// Set once the anchored line is edited or removed. A detached comment never draws again,
    /// so it cannot land on unrelated code.
    public var isDetached: Bool

    /// The highest row an anchor may name; untrusted input beyond it decodes detached.
    public static let maximumRow = 10_000_000

    public init(row: Int, side: Side, isDetached: Bool = false) {
        self.row = row
        self.side = side
        self.isDetached = isDetached
    }

    private enum CodingKeys: String, CodingKey {
        case row, side, isDetached
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let row = try container.decode(Int.self, forKey: .row)
        side = (try? container.decode(Side.self, forKey: .side)) ?? .new
        let valid = (1...Self.maximumRow).contains(row)
        self.row = valid ? row : 1
        isDetached = !valid || ((try? container.decode(Bool.self, forKey: .isDetached)) ?? false)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(row, forKey: .row)
        try container.encode(side, forKey: .side)
        if isDetached { try container.encode(true, forKey: .isDetached) }
    }

    /// The anchor for `row` of `document`: a removed line lives on the old side, every other
    /// row on the new one.
    public static func anchor(row: Int, in document: DiffDocument) -> DiffLineAnchor {
        let kind = document.rowKinds.indices.contains(row - 1) ? document.rowKinds[row - 1] : nil
        return DiffLineAnchor(row: row, side: kind == .deletion ? .old : .new)
    }

    /// `annotations` with every attached anchor moved to follow the edit from `old` to `new`.
    /// Rows before or after the changed lines shift with them; an anchor on a changed line
    /// detaches.
    public static func rebasing(
        _ annotations: [Annotation], from old: String, to new: String
    ) -> [Annotation] {
        guard old != new,
            annotations.contains(where: { $0.lineAnchor.map { !$0.isDetached } ?? false })
        else { return annotations }
        let before = lines(of: old)
        let after = lines(of: new)
        let shared = min(before.count, after.count)
        var prefix = 0
        while prefix < shared, before[prefix] == after[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < shared - prefix,
            before[before.count - 1 - suffix] == after[after.count - 1 - suffix]
        {
            suffix += 1
        }
        let shift = after.count - before.count
        return annotations.map { annotation in
            guard var anchor = annotation.lineAnchor, !anchor.isDetached else { return annotation }
            if anchor.row > before.count - suffix {
                anchor.row += shift
            } else if anchor.row > prefix {
                anchor.isDetached = true
            }
            var moved = annotation
            moved.lineAnchor = anchor
            return moved
        }
    }

    private static func lines(of text: String) -> [Substring] {
        text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
    }
}
