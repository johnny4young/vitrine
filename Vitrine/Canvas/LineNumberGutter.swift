import SwiftUI

/// A set of highlighted 1-based line ranges, with parsing and membership (CS-021).
///
/// Technical posts often need to point at a line ("see line 12") without
/// annotating the image in another tool. `LineHighlight` is the value model
/// behind `SnapshotConfig.highlightedLineRanges`: it answers "is this row
/// highlighted?" for the renderer and parses a compact, human-friendly spec
/// (`"3, 7-9, 12"`) typed in settings into normalized, de-overlapped ranges.
///
/// Ranges are **1-based and inclusive**, matching how editors and reviewers
/// refer to lines. Parsing is forgiving by design (CS-050 spirit): whitespace and
/// empty fragments are ignored, a reversed pair like `9-7` is normalized to
/// `7...9`, non-positive and non-numeric fragments are dropped, and the result is
/// merged and sorted so the same visible selection always yields the same value
/// (the config round-trips and compares cleanly).
enum LineHighlight {
    /// Parses a comma/space-separated spec such as `"3, 7-9, 12"` into normalized,
    /// merged, ascending inclusive ranges.
    ///
    /// Accepted fragments: a single line (`"7"`) or a hyphenated range (`"7-9"`,
    /// `"7 - 9"`). Anything else — blanks, letters, zero, negatives, malformed
    /// hyphenation — is skipped rather than failing the whole parse, so a partial
    /// or fat-fingered entry still applies the parts that are valid.
    static func parse(_ text: String) -> [ClosedRange<Int>] {
        let fragments = text.split(whereSeparator: { $0 == "," || $0 == "\n" })
        let ranges: [ClosedRange<Int>] = fragments.compactMap(parseFragment)
        return normalize(ranges)
    }

    /// Renders ranges back into the canonical spec string (`"3, 7-9, 12"`), the
    /// inverse of `parse` for already-normalized input. A single-line range is
    /// written as one number; a wider range uses the `lower-upper` form.
    static func describe(_ ranges: [ClosedRange<Int>]) -> String {
        normalize(ranges)
            .map {
                $0.lowerBound == $0.upperBound
                    ? "\($0.lowerBound)" : "\($0.lowerBound)-\($0.upperBound)"
            }
            .joined(separator: ", ")
    }

    /// Whether `line` (1-based) falls in any of `ranges`.
    static func contains(_ ranges: [ClosedRange<Int>], line: Int) -> Bool {
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
    static func normalize(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Int>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound + 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}

/// Geometry for the line-number gutter, derived from the code's own `NSFont`
/// (CS-021).
///
/// Alignment is the whole game here: the gutter must sit on the same baseline as
/// the code for every bundled font and the default line height, with no per-row
/// drift. `SnapshotCanvas` builds the code font from `SnapshotConfig.fontName`/
/// `fontSize`; passing that exact `NSFont` in lets the column width track the
/// real digit advance (monospaced fonts differ in width across families/sizes)
/// instead of guessing from an opaque SwiftUI `Font`.
struct GutterMetrics {
    /// The advance width of one monospaced digit in the code font.
    let digitWidth: CGFloat
    /// The number of digit columns to reserve (sized to the highest line number,
    /// with a two-digit floor so a short snippet's gutter is not cramped).
    let digitColumns: Int

    /// Trailing space between the gutter number and the code, in points. Applied
    /// as padding after the number so the gap sits between the number and the
    /// code, never to the left of the number.
    static let trailingGap: CGFloat = 14

    init(font: NSFont, lineCount: Int) {
        digitWidth = CodeFont.advance(of: "0", in: font)
        digitColumns = max(2, String(max(lineCount, 1)).count)
    }

    /// The number column width: just the reserved digit columns. Right-aligning
    /// the number to exactly this width keeps every line number's units digit in
    /// the same place; the trailing gap before the code is applied separately.
    var numberWidth: CGFloat { CGFloat(digitColumns) * digitWidth }
}

/// The code body, rendered row-by-row so an optional line-number gutter and
/// selected-line highlight bands align exactly with each code line (CS-021).
///
/// The plain export path keeps drawing the code as a single `Text` (see
/// `SnapshotCanvas`); this per-row layout is used only when the gutter or a
/// highlight is enabled. Each row pairs an optional right-aligned line number
/// with one syntax-highlighted code line, sitting on a highlight band when that
/// line is selected. Vertical rhythm matches the single-`Text` path: the rows use
/// the same inter-line spacing the canvas applies as `lineSpacing`, so toggling
/// the gutter does not reflow the code.
struct CodeLinesView: View {
    /// The already syntax-highlighted code, pre-split into one `AttributedString` per
    /// line (each keeping its colors) and cached by `HighlightManager`, so the
    /// character-by-character split does not rebuild on every `body` pass.
    let rows: [AttributedString]
    /// Whether to draw the leading line-number gutter.
    let showLineNumbers: Bool
    /// Normalized 1-based inclusive ranges to highlight.
    let highlightedRanges: [ClosedRange<Int>]
    /// Normalized 1-based inclusive ranges to redact: the code on these lines is blurred
    /// (the same softening as a blur annotation) so a shared snapshot never exposes a
    /// secret. The gutter number stays sharp so it's clear which line was hidden.
    var redactedRanges: [ClosedRange<Int>] = []
    /// The resolved code font, used for gutter sizing and the number glyphs.
    let font: NSFont
    /// The per-line vertical gap, matching the canvas's `lineSpacing` so the
    /// row layout and the single-`Text` layout have identical rhythm.
    let lineSpacing: CGFloat
    /// The optional soft-wrap width for the code column only. The gutter is outside
    /// this width so enabling line numbers never steals columns from wrapped code.
    var codeColumnWidth: CGFloat?
    /// The code's foreground color, dimmed for gutter numbers.
    let textColor: Color
    /// The band color drawn behind a highlighted row.
    let highlightColor: Color
    /// Fade the rows that are not highlighted, so the highlighted ones read as the
    /// subject — the "focus" mode. No effect without a highlight.
    var dimsUnfocused: Bool = false
    /// Band added (`+`) lines green and removed (`-`) lines red, GitHub-style. When
    /// on, the diff band takes precedence over the plain highlight band.
    var diffDecorations: Bool = false

    var body: some View {
        let metrics = GutterMetrics(font: font, lineCount: rows.count)
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, line in
                row(line, lineNumber: index + 1, metrics: metrics)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func row(
        _ line: AttributedString, lineNumber: Int, metrics: GutterMetrics
    )
        -> some View
    {
        let isHighlighted = LineHighlight.contains(highlightedRanges, line: lineNumber)
        let isRedacted = LineHighlight.contains(redactedRanges, line: lineNumber)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if showLineNumbers {
                // Verbatim: a line number is a locale-neutral numeral, not catalog
                // copy — and this also keeps Xcode's extractor from emitting a bare
                // "%@" key into the String Catalog (CS-047).
                Text(verbatim: "\(lineNumber)")
                    .font(Font(font))
                    .monospacedDigit()
                    .foregroundStyle(textColor.opacity(isHighlighted ? 0.85 : 0.4))
                    .frame(width: metrics.numberWidth, alignment: .trailing)
                    .padding(.trailing, GutterMetrics.trailingGap)
                    .accessibilityHidden(true)
            }
            // Redacted rows hide only the code, leaving the gutter number sharp. The
            // rendered text is a neutral placeholder — not the original source blurred —
            // so accessibility, text selection, and rich clipboard paths cannot recover
            // the secret the image is meant to hide.
            lineText(line, isRedacted: isRedacted)
            Spacer(minLength: 0)
        }
        // A full-bleed band so the highlight reads as a selected row across the
        // whole card width, behind both the gutter number and the code.
        .padding(.horizontal, Brand.Spacing.xs)
        .padding(.vertical, lineSpacing / 2)
        .background(rowBackground(line: line, isHighlighted: isHighlighted))
        // Negative inset cancels the horizontal padding so highlighted and plain
        // rows share the same left edge; the band simply extends past the text.
        .padding(.horizontal, -Brand.Spacing.xs)
        // Focus mode: fade the rows outside the highlight so the highlighted ones
        // read as the subject. A no-op when focus is off or this row is highlighted.
        .opacity(dimsUnfocused && !isHighlighted ? 0.34 : 1)
    }

    /// One code line as text, preserving its syntax colors. An empty line still
    /// occupies a full row (a zero-width space placeholder) so blank lines keep
    /// the gutter numbering and vertical rhythm intact rather than collapsing.
    @ViewBuilder
    private func lineText(_ line: AttributedString, isRedacted: Bool) -> some View {
        Group {
            if isRedacted {
                redactedText(for: line)
                    .foregroundStyle(textColor.opacity(0.55))
                    .blur(radius: max(6, font.pointSize * 0.45))
                    .textSelection(.disabled)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Redacted line"))
            } else {
                textForLine(line)
            }
        }
        .frame(width: codeColumnWidth, alignment: .leading)
    }

    /// The actual text for one row, before any optional soft-wrap frame is applied.
    private func textForLine(_ line: AttributedString) -> Text {
        // Verbatim: the zero-width space is a layout placeholder, not user copy, so
        // it must not become a String Catalog key (CS-047).
        if line.characters.isEmpty { return Text(verbatim: "\u{200B}").font(Font(font)) }
        return Text(line)
    }

    /// A same-length neutral mask for a redacted row. It keeps the row's approximate
    /// width without retaining the source text in the SwiftUI accessibility/selection
    /// tree.
    private func redactedText(for line: AttributedString) -> Text {
        let characterCount = max(8, line.characters.count)
        return Text(verbatim: String(repeating: "█", count: characterCount)).font(Font(font))
    }

    /// The band drawn behind a row: a diff add/remove band when diff decorations are
    /// on and the line is a change, otherwise the plain highlight band (or nothing).
    private func rowBackground(line: AttributedString, isHighlighted: Bool) -> Color {
        if diffDecorations, let diff = diffBand(of: line) { return diff }
        return isHighlighted ? highlightColor : Color.clear
    }

    /// A green band for an added (`+`) line, red for a removed (`-`) line, `nil`
    /// otherwise — the GitHub-style diff coloring (the first glyph is the diff marker).
    private func diffBand(of line: AttributedString) -> Color? {
        switch line.characters.first {
        case "+": Color(hex: "#2EA043").opacity(0.18)
        case "-": Color(hex: "#F85149").opacity(0.18)
        default: nil
        }
    }
}

/// Splits text and attributed text into lines on `\n`, preserving empty interior
/// and trailing lines so line numbering matches an editor's (CS-021).
///
/// Swift's `String.split` drops empty subsequences by default, which would
/// misnumber blank lines; this splitter keeps every line, including a trailing
/// empty one, so "line N" always means the same row the user sees.
enum LineSplitter {
    /// The plain-text lines, including empty ones (interior and trailing).
    static func plainLines(of text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// The number of rows `text` renders as: one per line, with empty interior
    /// and trailing lines counted. Empty text counts as a single (empty) row.
    static func lineCount(of text: String) -> Int {
        max(1, plainLines(of: text).count)
    }

    /// The attributed lines, including empty ones, each keeping its run colors.
    ///
    /// The split walks the `AttributedString` directly on its own character view
    /// and indices — never through `description`, which renders attribute runs as
    /// bracketed annotations rather than plain text — so each returned line keeps
    /// exactly the syntax colors it was highlighted with.
    static func attributedLines(of attributed: AttributedString) -> [AttributedString] {
        var result: [AttributedString] = []
        var lineStart = attributed.startIndex
        var cursor = attributed.startIndex
        let characters = attributed.characters

        while cursor < attributed.endIndex {
            if characters[cursor] == "\n" {
                result.append(AttributedString(attributed[lineStart..<cursor]))
                cursor = attributed.index(afterCharacter: cursor)
                lineStart = cursor
            } else {
                cursor = attributed.index(afterCharacter: cursor)
            }
        }
        result.append(AttributedString(attributed[lineStart..<attributed.endIndex]))
        return result
    }
}
