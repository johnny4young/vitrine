import Foundation

/// One row the diff layout draws: a source line (1-based) or a marker for folded lines.
public enum DiffDisplayRow: Equatable, Sendable {
    case line(Int)
    case fold
}

/// A unified or combined diff, read row by row. Hunk headers decide what a row means: inside
/// a hunk `--- x` is a removed line, outside it is a file header. Text with no hunk header
/// reads as one hunk for its counts, as the diff bands do, but is never folded.
public struct DiffDocument: Equatable, Sendable {
    public enum RowKind: Equatable, Sendable {
        case outside, hunkHeader, context, addition, deletion, note
    }

    public struct ChangedFile: Equatable, Sendable {
        public var path: String?
        /// The 1-based rows before the file's first change. They repeat the path, so
        /// redacting any of them withholds it.
        public var headerRows: ClosedRange<Int>
    }

    public private(set) var rowKinds: [RowKind]
    public private(set) var files: [ChangedFile] = []
    public private(set) var additions = 0
    public private(set) var deletions = 0
    public private(set) var hasHunks = false
    /// The old and new start lines each well-formed hunk header names, keyed by its 0-based row.
    public private(set) var hunkStarts: [Int: DiffLinePair] = [:]

    public init(source: String) {
        let lines = source.split(
            omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
        let hasHunks = lines.contains(where: Self.isHunkHeader)
        self.hasHunks = hasHunks
        rowKinds = Array(repeating: .outside, count: lines.count)

        var inHunk = !hasHunks
        var fileHasBody = false
        // Line budgets from the hunk header; nil when absent, malformed or used up.
        var remaining: (old: Int, new: Int)?
        // A combined diff marks each row with one column per parent.
        var combinedColumns: Int?
        var index = 0
        while index < lines.count {
            defer { index += 1 }
            let line = lines[index]
            if line.hasPrefix("diff --git ") || line.hasPrefix("diff --c") {
                files.append(
                    ChangedFile(
                        path: Self.gitHeaderPath(line), headerRows: (index + 1)...(index + 1)))
                (fileHasBody, inHunk, remaining, combinedColumns) = (false, !hasHunks, nil, nil)
                continue
            }
            if remaining == nil, combinedColumns == nil, Self.isFileHeaderPair(lines, at: index) {
                let target = Self.filePath(lines[index + 1], stripping: "b/")
                let origin = Self.filePath(line, stripping: "a/")
                if fileHasBody || files.isEmpty {
                    files.append(
                        ChangedFile(
                            path: target ?? origin, headerRows: (index + 1)...(index + 2)))
                } else {
                    let last = files.count - 1
                    files[last].path = target ?? origin ?? files[last].path
                    files[last].headerRows = files[last].headerRows.lowerBound...(index + 2)
                }
                (fileHasBody, inHunk) = (false, !hasHunks)
                index += 1
                continue
            }
            if Self.isHunkHeader(line) {
                rowKinds[index] = .hunkHeader
                let columns = line.prefix { $0 == "@" }.count - 1
                combinedColumns = columns > 1 ? columns : nil
                remaining = columns > 1 ? nil : Self.hunkLineCounts(line, limit: lines.count)
                hunkStarts[index] = Self.hunkStart(line)
                (inHunk, fileHasBody) = (true, true)
                continue
            }
            if !fileHasBody, line.first != "+", line.first != "-", let last = files.indices.last {
                files[last].headerRows = files[last].headerRows.lowerBound...(index + 1)
                for marker in ["rename to ", "copy to "] where line.hasPrefix(marker) {
                    files[last].path = Self.pathName(line.dropFirst(marker.count))
                }
            }
            guard inHunk else { continue }

            let marker = combinedColumns.map { columns in
                line.prefix(columns).first { $0 != " " } ?? " "
            }
            switch marker ?? line.first {
            case "\\":
                rowKinds[index] = .note
                continue
            case "+":
                rowKinds[index] = .addition
                additions += 1
                fileHasBody = true
            case "-":
                // A mail signature can only follow a hunk whose lines are used up.
                if remaining == nil, line == "-- " || line == "--" {
                    inHunk = !hasHunks
                    continue
                }
                rowKinds[index] = .deletion
                deletions += 1
                fileHasBody = true
            case " ", nil:
                rowKinds[index] = .context
            default:
                guard !hasHunks else {
                    (inHunk, remaining) = (false, nil)
                    continue
                }
                rowKinds[index] = .context
            }

            if let budget = remaining {
                let old = max(budget.old - (rowKinds[index] == .addition ? 0 : 1), 0)
                let new = max(budget.new - (rowKinds[index] == .deletion ? 0 : 1), 0)
                remaining = old == 0 && new == 0 ? nil : (old, new)
            }
        }
    }

    /// Rows to draw when keeping `contextLines` unchanged lines around each change, plus the
    /// `kept` rows. Source rows keep their numbers. A marker stands in for a gap inside a
    /// hunk; a gap at its edge is accounted for by the hunk's own header.
    public func displayRows(
        contextLines: Int, keeping kept: [ClosedRange<Int>] = []
    ) -> [DiffDisplayRow] {
        guard hasHunks, additions + deletions > 0 else {
            return rowKinds.indices.map { .line($0 + 1) }
        }
        let keep = max(contextLines, 0)
        let keptRanges = LineHighlight.normalize(kept)
        var rows: [DiffDisplayRow] = []
        var index = 0
        while index < rowKinds.count {
            guard rowKinds[index] == .context else {
                rows.append(.line(index + 1))
                index += 1
                continue
            }
            var end = index
            while end < rowKinds.count, rowKinds[end] == .context { end += 1 }
            let followsChange = index > 0 && Self.isChange(rowKinds[index - 1])
            let precedesChange = end < rowKinds.count && Self.isChange(rowKinds[end])
            let length = end - index
            let head = followsChange ? min(keep, length) : 0
            let tail = precedesChange ? min(keep, length - head) : 0

            var hasRowBefore = followsChange
            var inGap = false
            for row in index..<end {
                guard
                    row < index + head || row >= end - tail
                        || LineHighlight.contains(keptRanges, line: row + 1)
                else {
                    inGap = true
                    continue
                }
                if inGap, hasRowBefore { rows.append(.fold) }
                rows.append(.line(row + 1))
                (hasRowBefore, inGap) = (true, false)
            }
            if inGap, hasRowBefore, precedesChange { rows.append(.fold) }
            index = end
        }
        return rows
    }

    /// The single changed file's path, unless a header row is redacted or there are several.
    public func singleFilePath(redacting redactions: [ClosedRange<Int>]) -> String? {
        guard files.count == 1, let file = files.first,
            !redactions.contains(where: { $0.overlaps(file.headerRows) })
        else { return nil }
        return file.path
    }

    /// A redacted row that keeps its diff markers, which carry no content, so whoever parses
    /// the masked text reads the same hunks and counts.
    public static func maskedRow(_ row: String, placeholder: String) -> String {
        for header in ["@@@ ", "@@ ", "diff --git ", "diff --cc ", "diff --combined "]
        where row.hasPrefix(header) {
            return header + placeholder
        }
        let markers = row.prefix(4).prefix { " +-\\".contains($0) }
        return (markers.isEmpty ? " " : String(markers)) + placeholder
    }

    /// How many of `cellCount` diffstat cells are additions. Each side that changed
    /// keeps at least one cell, so a lone removal in a large diff stays visible.
    public func additionCells(of cellCount: Int) -> Int {
        let total = additions + deletions
        guard total > 0, additions > 0 else { return 0 }
        guard deletions > 0 else { return cellCount }
        let share = (Double(additions) / Double(total) * Double(cellCount)).rounded()
        return min(max(Int(share), 1), cellCount - 1)
    }

    private static func isChange(_ kind: RowKind) -> Bool {
        kind == .addition || kind == .deletion || kind == .note
    }

    private static func isHunkHeader(_ line: Substring) -> Bool {
        line.hasPrefix("@@ ") || line == "@@" || line.hasPrefix("@@@")
    }

    private static func isFileHeaderPair(_ lines: [Substring], at index: Int) -> Bool {
        lines[index].hasPrefix("--- ") && index + 1 < lines.count
            && lines[index + 1].hasPrefix("+++ ")
    }

    /// The old and new line counts in `@@ -a,b +c,d @@`, where a missing count means 1.
    /// Pasted text is untrusted: a count outside `0...limit` makes the header malformed.
    private static func hunkLineCounts(
        _ header: Substring, limit: Int
    ) -> (old: Int, new: Int)? {
        let parts = header.split(separator: " ", maxSplits: 3)
        guard parts.count >= 3, let old = lineCount(parts[1], marker: "-", limit: limit),
            let new = lineCount(parts[2], marker: "+", limit: limit)
        else { return nil }
        return (old, new)
    }

    /// The highest start line a hunk header may name; pasted text is untrusted, and a larger
    /// one leaves its hunk unnumbered rather than overflowing the count.
    public static let maximumHunkStart = 10_000_000

    /// The first `-a` and the `+c` in a hunk header, which a combined diff also ends with.
    private static func hunkStart(_ header: Substring) -> DiffLinePair? {
        func start(_ marker: Character) -> Int? {
            let parts = header.split(separator: " ").dropFirst()
            guard let range = parts.first(where: { $0.first == marker }),
                let value = Int(range.dropFirst().prefix { $0 != "," }),
                (0...maximumHunkStart).contains(value)
            else { return nil }
            return value
        }
        guard let old = start("-"), let new = start("+") else { return nil }
        return DiffLinePair(old: old, new: new)
    }

    private static func lineCount(_ range: Substring, marker: Character, limit: Int) -> Int? {
        guard range.first == marker else { return nil }
        let bounds = range.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
        guard let first = bounds.first, Int(first) != nil else { return nil }
        guard bounds.count > 1 else { return 1 }
        guard let count = Int(bounds[1]), (0...limit).contains(count) else { return nil }
        return count
    }

    /// The path in a `diff --cc` header, or in `diff --git a/P b/P`. Unquoted names may hold
    /// spaces, so only that symmetric form splits without guessing; a rename row names its own.
    private static func gitHeaderPath(_ line: Substring) -> String? {
        if !line.hasPrefix("diff --git ") {
            return line.split(separator: " ", maxSplits: 2).last.flatMap { pathName($0) }
        }
        let names = line.dropFirst("diff --git ".count)
        guard names.count % 2 == 1 else { return nil }
        let origin = pathName(names.prefix(names.count / 2), stripping: "a/")
        let target = pathName(names.suffix(names.count / 2), stripping: "b/")
        return origin == target ? target : nil
    }

    /// A `---`/`+++` line's path, without its timestamp.
    private static func filePath(_ line: Substring, stripping prefix: String) -> String? {
        pathName(line.dropFirst(4).prefix { $0 != "\t" }, stripping: prefix)
    }

    /// A path as Git wrote it, or nil for `/dev/null` and for quoted names with escapes,
    /// which would otherwise show mangled.
    private static func pathName(_ raw: Substring, stripping prefix: String = "") -> String? {
        var name = raw
        if name.count >= 2, name.first == "\"", name.last == "\"" {
            name = name.dropFirst().dropLast()
            guard !name.contains("\\") else { return nil }
        }
        if !prefix.isEmpty, name.hasPrefix(prefix) { name = name.dropFirst(prefix.count) }
        return name.isEmpty || name == "/dev/null" ? nil : String(name)
    }
}
