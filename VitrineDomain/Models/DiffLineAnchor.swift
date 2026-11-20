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
    /// Set once the anchored line is edited or removed. A detached comment does not draw, so
    /// it cannot land on unrelated code.
    public var isDetached: Bool
    /// The line's text when it detached, kept in memory only, so an edit that restores that
    /// text in place (an undo) attaches the comment again.
    var detachedLine: String?

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

    /// The anchor for `row` of `document`: a removed line, and a note right after one, lives
    /// on the old side, as the split layout draws them; every other row on the new one.
    public static func anchor(row: Int, in document: DiffDocument) -> DiffLineAnchor {
        func kind(_ row: Int) -> DiffDocument.RowKind? {
            document.rowKinds.indices.contains(row - 1) ? document.rowKinds[row - 1] : nil
        }
        let isOld = kind(row) == .deletion || (kind(row) == .note && kind(row - 1) == .deletion)
        return DiffLineAnchor(row: row, side: isOld ? .old : .new)
    }

    /// `annotations` following the edit from `old` to `new`.
    public static func rebasing(
        _ annotations: [Annotation], from old: String, to new: String
    ) -> [Annotation] {
        guard old != new, follows(annotations) else { return annotations }
        return Edit(from: old, to: new).apply(to: annotations)
    }

    /// Whether an edit can move or attach any of `annotations`.
    public static func follows(_ annotations: [Annotation]) -> Bool {
        annotations.contains { annotation in
            annotation.lineAnchor.map { !$0.isDetached || $0.detachedLine != nil } ?? false
        }
    }

    /// One text edit, read as the lines it kept before and after the span it changed.
    public struct Edit: Sendable {
        let before: [UInt8]
        let after: [UInt8]
        /// Lines equal at the start and at the end of both texts.
        let prefix: Int
        let suffix: Int
        let beforeLines: Int
        let afterLines: Int

        /// Compares bytes rather than splitting lines, since it runs on every keystroke.
        public init(from old: String, to new: String) {
            let a = Array(old.utf8)
            let b = Array(new.utf8)
            let newline = UInt8(ascii: "\n")
            func breaks(_ bytes: [UInt8], _ range: Range<Int>) -> Int {
                bytes.withUnsafeBufferPointer { buffer in
                    var count = 0
                    var index = range.lowerBound
                    while index < range.upperBound {
                        if buffer[index] == newline { count += 1 }
                        index += 1
                    }
                    return count
                }
            }
            func endsLine(_ bytes: [UInt8], at index: Int) -> Bool {
                index == bytes.count || bytes[index] == newline
            }
            func startsLine(_ bytes: [UInt8], at index: Int) -> Bool {
                index == 0 || bytes[index - 1] == newline
            }
            let shared = min(a.count, b.count)
            var bytePrefix = 0
            while bytePrefix < shared, a[bytePrefix] == b[bytePrefix] { bytePrefix += 1 }
            var byteSuffix = 0
            while byteSuffix < shared - bytePrefix,
                a[a.count - 1 - byteSuffix] == b[b.count - 1 - byteSuffix]
            {
                byteSuffix += 1
            }
            let leading = breaks(a, 0..<bytePrefix)
            let trailing = breaks(a, (a.count - byteSuffix)..<a.count)
            beforeLines = leading + breaks(a, bytePrefix..<(a.count - byteSuffix)) + trailing + 1
            afterLines = leading + breaks(b, bytePrefix..<b.count) + 1
            var prefix = leading
            if endsLine(a, at: bytePrefix), endsLine(b, at: bytePrefix) { prefix += 1 }
            var suffix = trailing
            if startsLine(a, at: a.count - byteSuffix), startsLine(b, at: b.count - byteSuffix) {
                suffix += 1
            }
            prefix = min(prefix, beforeLines, afterLines)
            self.prefix = prefix
            self.suffix = min(suffix, min(beforeLines, afterLines) - prefix)
            (before, after) = (a, b)
        }

        /// Anchors outside the changed span shift with their lines. An attached anchor inside
        /// it detaches; a detached one attaches again where the span restores its text.
        public func apply(to annotations: [Annotation]) -> [Annotation] {
            annotations.map { annotation in
                guard let anchor = annotation.lineAnchor,
                    !anchor.isDetached || anchor.detachedLine != nil
                else { return annotation }
                var moved = annotation
                moved.lineAnchor = follow(anchor)
                return moved
            }
        }

        private func follow(_ anchor: DiffLineAnchor) -> DiffLineAnchor {
            var anchor = anchor
            // A deleted line keeps its row, so putting it back (an undo) lands in the new span.
            if anchor.isDetached, anchor.row > prefix, anchor.row <= afterLines - suffix,
                let line = anchor.detachedLine, Self.line(anchor.row, of: after) == line
            {
                anchor.isDetached = false
                anchor.detachedLine = nil
                return anchor
            }
            if anchor.row > beforeLines - suffix {
                anchor.row += afterLines - beforeLines
            } else if anchor.row <= prefix {
                return anchor
            } else if !anchor.isDetached {
                anchor.isDetached = true
                anchor.detachedLine = Self.line(anchor.row, of: before)
            } else if anchor.detachedLine != nil,
                Self.line(anchor.row, of: after) == anchor.detachedLine
            {
                anchor.isDetached = false
                anchor.detachedLine = nil
            }
            return anchor
        }

        /// The text of 1-based line `row`, without its line break.
        private static func line(_ row: Int, of bytes: [UInt8]) -> String? {
            var line = 1
            var start = 0
            for index in bytes.indices where line < row && bytes[index] == UInt8(ascii: "\n") {
                line += 1
                start = index + 1
            }
            guard line == row else { return nil }
            var end = start
            while end < bytes.count, bytes[end] != UInt8(ascii: "\n") { end += 1 }
            if end > start, bytes[end - 1] == UInt8(ascii: "\r") { end -= 1 }
            return String(decoding: bytes[start..<end], as: UTF8.self)
        }
    }
}
