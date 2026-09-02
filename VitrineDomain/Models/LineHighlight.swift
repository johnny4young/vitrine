import Foundation

/// A set of highlighted 1-based line ranges, with parsing and membership.
///
/// Technical posts often need to point at a line ("see line 12") without
/// annotating the image in another tool. `LineHighlight` is the value model
/// behind `SnapshotConfig.highlightedLineRanges`: it answers "is this row
/// highlighted?" for the renderer and parses a compact, human-friendly spec
/// (`"3, 7-9, 12"`) typed in settings into normalized, de-overlapped ranges.
///
/// Ranges are **1-based and inclusive**, matching how editors and reviewers
/// refer to lines. Parsing is forgiving by design (defensive behavior): whitespace and
/// empty fragments are ignored, a reversed pair like `9-7` is normalized to
/// `7...9`, non-positive and non-numeric fragments are dropped, and the result is
/// merged and sorted so the same visible selection always yields the same value
/// (the config round-trips and compares cleanly).
public enum LineHighlight {
    /// Parses a comma/space-separated spec such as `"3, 7-9, 12"` into normalized,
    /// merged, ascending inclusive ranges.
    ///
    /// Accepted fragments: a single line (`"7"`) or a hyphenated range (`"7-9"`,
    /// `"7 - 9"`). Anything else — blanks, letters, zero, negatives, malformed
    /// hyphenation — is skipped rather than failing the whole parse, so a partial
    /// or fat-fingered entry still applies the parts that are valid.
    public static func parse(_ text: String) -> [ClosedRange<Int>] {
        let fragments = text.split(whereSeparator: { $0 == "," || $0 == "\n" })
        let ranges: [ClosedRange<Int>] = fragments.compactMap(parseFragment)
        return normalize(ranges)
    }

    /// Renders ranges back into the canonical spec string (`"3, 7-9, 12"`), the
    /// inverse of `parse` for already-normalized input. A single-line range is
    /// written as one number; a wider range uses the `lower-upper` form.
    public static func describe(_ ranges: [ClosedRange<Int>]) -> String {
        normalize(ranges)
            .map {
                $0.lowerBound == $0.upperBound
                    ? "\($0.lowerBound)" : "\($0.lowerBound)-\($0.upperBound)"
            }
            .joined(separator: ", ")
    }

    /// Whether `line` (1-based) falls in any of `ranges`.
    public static func contains(_ ranges: [ClosedRange<Int>], line: Int) -> Bool {
        ranges.contains { $0.contains(line) }
    }

    /// Parses one fragment into a single inclusive range, or `nil` if it is not a
    /// valid line or range. A reversed `upper-lower` pair is normalized so order
    /// in the input never matters.
    private static func parseFragment(_ fragment: Substring) -> ClosedRange<Int>? {
        let trimmed = fragment.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let bounds = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        switch bounds.count {
        case 1:
            guard let value = positiveLine(bounds[0]) else { return nil }
            return value...value
        case 2:
            guard let low = positiveLine(bounds[0]), let high = positiveLine(bounds[1]) else {
                return nil
            }
            return min(low, high)...max(low, high)
        default:
            // More than one hyphen (e.g. "1-2-3") is malformed; drop it.
            return nil
        }
    }

    /// Parses a single positive line number, rejecting blanks, non-numerics, and
    /// values below 1 (lines are 1-based, so 0 and negatives are meaningless).
    private static func positiveLine(_ text: Substring) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), value >= 1 else {
            return nil
        }
        return value
    }

    /// Sorts and merges overlapping or adjacent ranges so a selection has one
    /// canonical representation (e.g. `[3...5, 4...7]` → `[3...7]`,
    /// `[1...2, 3...3]` → `[1...3]`). Stable output keeps the config Equatable
    /// comparison and the round-trip string meaningful.
    public static func normalize(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Int>] = []
        for range in sorted {
            if let last = merged.last, isOverlappingOrAdjacent(range, after: last) {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Whether `range` overlaps or immediately follows `last`, decided without
    /// arithmetic on either bound. `parse` only ever produces bounds `>= 1`, but
    /// `normalize` is public and accepts any `ClosedRange<Int>`, so both edges are
    /// reachable: an upper bound of `Int.max` overflows `upperBound + 1`, and a lower
    /// bound of `Int.min` overflows `lowerBound - 1`. Either would trap the process on
    /// input that ultimately comes from user text.
    private static func isOverlappingOrAdjacent(
        _ range: ClosedRange<Int>, after last: ClosedRange<Int>
    ) -> Bool {
        if range.lowerBound <= last.upperBound { return true }
        return last.upperBound < Int.max && range.lowerBound == last.upperBound + 1
    }
}
