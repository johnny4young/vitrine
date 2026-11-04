import Foundation

/// One row the diff layout draws: a source line (1-based) or a marker for folded lines.
public enum DiffDisplayRow: Equatable, Sendable {
    case line(Int)
    case fold
}

/// The structure of a unified diff, read row by row. Pure and deterministic, so a stats
/// header and a context fold render the same patch identically everywhere.
///
/// Hunk headers decide what a row means: inside a hunk `--- x` is a removed line, outside
/// it is a file header. Text with no hunk header at all (a hand-written `+`/`-` snippet)
/// reads as one hunk, matching how the diff bands treat it.
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

    public init(source: String) {
        let lines = source.split(
            omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
        let hasHunks = lines.contains(where: Self.isHunkHeader)
        rowKinds = Array(repeating: .outside, count: lines.count)

        var inHunk = !hasHunks
        var fileHasBody = false
        // Line budgets from the hunk header; nil when absent, malformed or used up.
        var remaining: (old: Int, new: Int)?
        var index = 0
        while index < lines.count {
            defer { index += 1 }
            let line = lines[index]
            if line.hasPrefix("diff --git ") {
                files.append(
                    ChangedFile(
                        path: Self.gitHeaderPath(line), headerRows: (index + 1)...(index + 1)))
                (fileHasBody, inHunk, remaining) = (false, !hasHunks, nil)
                continue
            }
            if remaining == nil, Self.isFileHeaderPair(lines, at: index) {
                let target = Self.filePath(lines[index + 1], prefix: "+++ b/", marker: "+++ ")
                let origin = Self.filePath(line, prefix: "--- a/", marker: "--- ")
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
                remaining = Self.hunkLineCounts(line, limit: lines.count)
                (inHunk, fileHasBody) = (true, true)
                continue
            }
            if !fileHasBody, line.first != "+", line.first != "-", let last = files.indices.last {
                files[last].headerRows = files[last].headerRows.lowerBound...(index + 1)
            }
            guard inHunk else { continue }

            switch line.first {
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

    /// Rows to draw when keeping `contextLines` unchanged lines on each side of a change.
    /// Source rows keep their numbers, so highlights and redactions stay on their lines. A
    /// marker stands in for a gap between two changes; at a hunk's edge the header says it.
    public func displayRows(contextLines: Int) -> [DiffDisplayRow] {
        guard additions + deletions > 0 else {
            return rowKinds.indices.map { .line($0 + 1) }
        }
        let keep = max(contextLines, 0)
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

            rows += (index..<(index + head)).map { .line($0 + 1) }
            if head + tail < length, followsChange, precedesChange { rows.append(.fold) }
            rows += ((end - tail)..<end).map { .line($0 + 1) }
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
        line.hasPrefix("@@ ") || line == "@@"
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

    private static func lineCount(_ range: Substring, marker: Character, limit: Int) -> Int? {
        guard range.first == marker else { return nil }
        let bounds = range.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
        guard let first = bounds.first, Int(first) != nil else { return nil }
        guard bounds.count > 1 else { return 1 }
        guard let count = Int(bounds[1]), (0...limit).contains(count) else { return nil }
        return count
    }

    /// The path after the last ` b/` in `diff --git a/x b/x`. Paths may contain spaces and
    /// Git quotes unusual ones, so the separator is searched from the end.
    private static func gitHeaderPath(_ line: Substring) -> String? {
        for separator in [" \"b/", " b/"] {
            if let range = line.range(of: separator, options: .backwards) {
                return unquoted(line[range.upperBound...])
            }
        }
        return nil
    }

    /// A `---`/`+++` line's path without its timestamp, or nil for `/dev/null`.
    private static func filePath(
        _ line: Substring, prefix: String, marker: String
    ) -> String? {
        let raw =
            line.hasPrefix(prefix) ? line.dropFirst(prefix.count) : line.dropFirst(marker.count)
        let path = unquoted(raw.prefix { $0 != "\t" })
        return path == "/dev/null" || path.isEmpty ? nil : path
    }

    private static func unquoted(_ path: Substring) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}
