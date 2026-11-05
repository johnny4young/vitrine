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

    /// Where the final frame's cursor sits. A frame kept from a program that left the
    /// alternate screen has none: by then the cursor is on the restored shell screen.
    var finalCursor: (row: Int, col: Int)? {
        guard cursorVisible else { return nil }
        if primaryStash != nil, !isPopulated(rows) { return nil }
        if primaryStash == nil, let alt = capturedAltFrame, isPopulated(alt) { return nil }
        var col = cursorCol
        let row = rows[cursorRow]
        while col > 0, col < row.count, row[col].content == .continuation { col -= 1 }
        return (cursorRow, col)
    }

    /// `finalCursor`, unless a program parked it where drawing would grow the capture: more than
    /// one row past the content, or past both the content's width and 80 columns. `columns`
    /// can't be the limit, because that same move widens the inferred width.
    private func drawableCursor(
        in frame: [[TerminalCell]], lastContentRow: Int
    ) -> (row: Int, col: Int)? {
        guard let cursor = finalCursor, cursor.row <= lastContentRow + 1 else { return nil }
        let contentWidth =
            frame.map { row in
                (row.lastIndex { !$0.isBlank } ?? -1) + 1
            }.max() ?? 0
        return cursor.col < max(80, contentWidth) ? cursor : nil
    }

    /// The final screen flattened into styled runs: adjacent same-style cells coalesce,
    /// trailing blank cells and trailing blank rows are trimmed, and rows are separated by
    /// a default-styled newline — the same shape ``ANSIParser/parse(_:)`` yields, so
    /// ``ANSIRenderer`` renders a grid and a line capture identically.
    public func runs(cursor style: TerminalCursorStyle = .hidden) -> [ANSIRun] {
        let frame = finalFrame
        // Drop trailing all-blank rows so the image isn't padded with empty lines.
        var lastRow = frame.count - 1
        while lastRow >= 0, !frame[lastRow].contains(where: { !$0.isBlank }) { lastRow -= 1 }
        let cursor = style == .hidden ? nil : drawableCursor(in: frame, lastContentRow: lastRow)
        if let cursor { lastRow = max(lastRow, cursor.row) }
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
            let cursorCol = cursor?.row == rowIndex ? cursor?.col : nil
            if let cursorCol { lastCol = max(lastCol, cursorCol) }
            if lastCol >= 0 {
                for col in 0...lastCol {
                    let cell = col < row.count ? row[col] : .blank
                    // A continuation cell owns no glyph — its wide head already emitted it.
                    guard case .grapheme(let g) = cell.content else { continue }
                    if col == cursorCol {
                        for run in style.runs(over: g, style: cell.style) {
                            emit(run.text, run.style)
                        }
                    } else {
                        emit(g, cell.style)
                    }
                }
            }
            if rowIndex < lastRow { emit("\n", ANSIStyle()) }
        }
        flush()
        return out
    }
}
