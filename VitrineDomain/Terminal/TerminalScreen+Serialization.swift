import Foundation

extension TerminalScreen {
    // MARK: - Output

    /// The screen to report: the captured alternate-screen frame when a TUI ran and
    /// exited, the live buffer when still on the alt screen at end of input, otherwise the
    /// primary buffer.
    var finalFrame: [[TerminalCell]] {
        if primaryStash != nil {  // ended inside the alt screen
            return isPopulated(rows) ? rows : (altSnapshot ?? rows)
        }
        if let alt = capturedAltFrame, isPopulated(alt) { return alt }
        return rows
    }

    /// The final screen flattened into styled runs: adjacent same-style cells coalesce,
    /// trailing blank cells and trailing blank rows are trimmed, and rows are separated by
    /// a default-styled newline — the same shape ``ANSIParser/parse(_:)`` yields, so
    /// ``ANSIRenderer`` renders a grid and a line capture identically.
    public func runs() -> [ANSIRun] {
        let frame = finalFrame
        // Drop trailing all-blank rows so the image isn't padded with empty lines.
        var lastRow = frame.count - 1
        while lastRow >= 0, !frame[lastRow].contains(where: { !$0.isBlank }) { lastRow -= 1 }
        guard lastRow >= 0 else { return [] }

        var out: [ANSIRun] = []
        var text = ""
        var runStyle = ANSIStyle()

        func flush() {
            guard !text.isEmpty else { return }
            out.append(ANSIRun(text: text, style: runStyle))
            text = ""
        }
        func emit(_ fragment: String, _ cellStyle: ANSIStyle) {
            if text.isEmpty {
                runStyle = cellStyle
            } else if cellStyle != runStyle {
                flush()
                runStyle = cellStyle
            }
            text += fragment
        }

        for rowIndex in 0...lastRow {
            let row = frame[rowIndex]
            // Trim trailing blank cells so a row isn't padded to the wrap width.
            var lastCol = row.count - 1
            while lastCol >= 0, row[lastCol].isBlank { lastCol -= 1 }
            if lastCol >= 0 {
                for col in 0...lastCol {
                    // A continuation cell owns no glyph — its wide head already emitted it.
                    if case .grapheme(let g) = row[col].content { emit(g, row[col].style) }
                }
            }
            if rowIndex < lastRow { emit("\n", ANSIStyle()) }
        }
        flush()
        return out
    }

    /// The final screen as plain text (styling dropped) — the copyable-text counterpart of
    /// the rendered image, matching ``ANSIRenderer/plainText(_:)`` for line mode.
    public func plainText() -> String {
        runs().map(\.text).joined()
    }
}
