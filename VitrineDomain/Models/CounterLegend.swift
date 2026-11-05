import Foundation

/// The legend a capture shows for its counter badges: "1 the struct · 2 the secret".
///
/// Labels are only ever text the user typed on a badge, kept in `Annotation.text`. A
/// capture with no labels has no legend. Masking is best effort: it catches secret shapes
/// and text matching what the capture hides, not a reworded or encoded copy.
public enum CounterLegend {
    public struct Entry: Equatable, Sendable {
        public let number: Int
        public let label: String
        public let color: RGBAColor
    }

    /// What a capture hides, compacted to lowercase alphanumerics so punctuation, spacing
    /// and zero-width characters can't disguise a copy of it.
    public struct HiddenText: Equatable, Sendable {
        var tokens: Set<String> = []
        var visibleWords: Set<String> = []
        var redacted = ""
        var values = ""

        public static let none = HiddenText()
    }

    /// Replaces a hidden label, so it still reads as deliberately hidden.
    public static let mask = "•••"
    public static let maxLabelLength = 120

    private static let minHiddenLength = 4
    /// Longer than the type names that follow `:` in most languages.
    private static let minAssignedValueLength = 6

    public static func hasLabels(_ annotations: [Annotation]) -> Bool {
        annotations.contains { $0.kind == .counter && !normalized($0.text).isEmpty }
    }

    /// The labeled counters in badge order, masked against `hidden`.
    public static func entries(
        from annotations: [Annotation], hiding hidden: HiddenText = .none
    ) -> [Entry] {
        annotations
            .filter { $0.kind == .counter && !normalized($0.text).isEmpty }
            .sorted { $0.number < $1.number }
            .map { counter in
                Entry(
                    number: counter.number, label: safeLabel(counter.text, hiding: hidden),
                    color: counter.color)
            }
    }

    /// The full text is checked before it is cut, so a value straddling the limit can't
    /// slip out as a partial copy.
    public static func safeLabel(_ text: String, hiding hidden: HiddenText) -> String {
        let label = normalized(text)
        return isHidden(label, in: hidden) ? mask : String(label.prefix(maxLabelLength))
    }

    public static func isMasked(_ text: String, hiding hidden: HiddenText) -> Bool {
        let label = normalized(text)
        return !label.isEmpty && isHidden(label, in: hidden)
    }

    /// Collects what a capture hides from its rows. Redacted rows that touch are joined,
    /// so a value wrapped across them still matches. A blur box's pixels can't be mapped
    /// back to text, so a blur hides every value in the code.
    public static func hiddenText(
        rows: [String], redactions: [ClosedRange<Int>], blurred: Bool, rowsMayWrap: Bool
    ) -> HiddenText {
        var hidden = HiddenText()
        if !redactions.isEmpty { collectRedactions(rows, redactions, into: &hidden) }
        if blurred {
            var values = Set<String>()
            for line in rowsMayWrap ? unwrapped(rows) : rows {
                collectValues(in: line, into: &values)
            }
            hidden.tokens.formUnion(values)
            hidden.values = values.joined(separator: "\n")
        }
        return hidden
    }

    private static func collectRedactions(
        _ rows: [String], _ redactions: [ClosedRange<Int>], into hidden: inout HiddenText
    ) {
        var hiddenWords = Set<String>()
        var runs: [String] = []
        var runIsOpen = false
        for (index, row) in rows.enumerated() {
            let isRedacted = LineHighlight.contains(redactions, line: index + 1)
            if isRedacted {
                if !runIsOpen { runs.append("") }
                runs[runs.count - 1] += compacted(row)
                forEachWord(in: row) { hiddenWords.insert($0) }
            } else {
                forEachWord(in: row) { hidden.visibleWords.insert($0) }
            }
            runIsOpen = isRedacted
        }
        hidden.tokens = hiddenWords.subtracting(hidden.visibleWords)
            .filter { $0.utf8.count >= minHiddenLength }
        hidden.redacted = runs.joined(separator: "\n")
    }

    /// Quoted strings, the right-hand side of `=` and `:`, and tokens carrying a digit.
    private static func collectValues(in line: String, into values: inout Set<String>) {
        func add(_ scalars: ArraySlice<Unicode.Scalar>, minimum: Int) {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars)
            let value = compacted(String(view))
            if value.utf8.count >= minimum { values.insert(value) }
        }
        let scalars = Array(line.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if isQuote(scalar), let close = scalars[(index + 1)...].firstIndex(of: scalar) {
                add(scalars[(index + 1)..<close], minimum: minHiddenLength)
                index = close + 1
            } else if scalar == "=" || scalar == ":" {
                var start = index + 1
                while start < scalars.count, isAssignmentGap(scalars[start]) { start += 1 }
                var end = start
                while end < scalars.count, !endsAssignedValue(scalars[end]) { end += 1 }
                // A quoted value is the quote branch's on the next pass.
                if start < scalars.count, !isQuote(scalars[start]) {
                    add(scalars[start..<end], minimum: minAssignedValueLength)
                    index = end
                } else {
                    index = start
                }
            } else {
                index += 1
            }
        }
        forEachWord(in: line) { word in
            if word.utf8.count >= minHiddenLength, word.contains(where: \.isNumber) {
                values.insert(word)
            }
        }
    }

    private static func isQuote(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\"" || scalar == "'" || scalar == "`"
    }

    private static func isAssignmentGap(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "=" || scalar == ">" || scalar == ":"
    }

    private static func endsAssignedValue(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "," || scalar == ";" || scalar == ")"
            || scalar == "}" || scalar == "]" || scalar == "&"
    }

    /// Joins a terminal row that fills the screen's width to the row it wrapped onto.
    private static func unwrapped(_ rows: [String]) -> [String] {
        let width = rows.map(\.count).max() ?? 0
        var lines: [String] = []
        var continues = false
        for row in rows {
            if continues, let last = lines.indices.last {
                lines[last] += row
            } else {
                lines.append(row)
            }
            continues = row.count == width
        }
        return lines
    }

    private static func isHidden(_ label: String, in hidden: HiddenText) -> Bool {
        guard SecretScanner.scan(withoutFormatScalars(label)).isEmpty else { return true }
        guard hidden != .none else { return false }
        let compact = compacted(label)
        guard compact.utf8.count >= minHiddenLength else { return false }
        if hidden.tokens.contains(where: { contains(compact, $0) }) { return true }
        if contains(hidden.values, compact) { return true }
        if !hidden.visibleWords.contains(compact), contains(hidden.redacted, compact) {
            return true
        }
        var found = false
        forEachWord(in: label) { word in
            guard !found, word.utf8.count >= minHiddenLength else { return }
            found =
                contains(hidden.values, word)
                || (!hidden.visibleWords.contains(word) && contains(hidden.redacted, word))
        }
        return found
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func withoutFormatScalars(_ text: String) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: text.unicodeScalars.filter { !isIgnorable($0) })
        return String(view)
    }

    private static func compacted(_ text: String) -> String {
        var result = ""
        forEachWord(in: text) { result += $0 }
        return result
    }

    /// Lowercase runs of alphanumerics. A scalar scan, because this walks whole documents.
    private static func forEachWord(in text: String, _ body: (String) -> Void) {
        var word = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if isIgnorable(scalar) { continue }
            if scalar.isASCII {
                switch scalar.value {
                case 0x30...0x39, 0x61...0x7A:
                    word.append(scalar)
                    continue
                case 0x41...0x5A:
                    word.append(Unicode.Scalar(UInt8(scalar.value + 0x20)))
                    continue
                default: break
                }
            } else if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                word.append(contentsOf: scalar.properties.lowercaseMapping.unicodeScalars)
                continue
            }
            if !word.isEmpty {
                body(String(word))
                word = String.UnicodeScalarView()
            }
        }
        if !word.isEmpty { body(String(word)) }
    }

    /// Zero-width and combining scalars can't split a word: they're invisible in a copy.
    private static func isIgnorable(_ scalar: Unicode.Scalar) -> Bool {
        guard !scalar.isASCII else { return false }
        let category = scalar.properties.generalCategory
        return category == .format || category == .nonspacingMark
    }

    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        guard !haystack.isEmpty, !needle.isEmpty else { return false }
        var haystack = haystack
        var needle = needle
        return haystack.withUTF8 { outer in
            needle.withUTF8 { inner in
                memmem(outer.baseAddress, outer.count, inner.baseAddress, inner.count) != nil
            }
        }
    }
}
