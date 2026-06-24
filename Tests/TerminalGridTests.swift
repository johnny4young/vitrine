import Testing

@testable import Vitrine

/// The cell-buffer VT emulator (`TerminalScreen`) that reconstructs the final screen of
/// a cursor-addressed terminal stream — the grid path for full-screen TUIs (htop/vim),
/// as opposed to the line-oriented `ANSIRenderer.normalize`.
@Suite("Terminal grid emulation")
struct TerminalGridTests {
    private let esc = "\u{1B}"

    /// Convenience: replay `text` at `columns` and read back the final screen as text.
    private func plain(_ text: String, columns: Int = 80) -> String {
        var screen = TerminalScreen(columns: columns)
        screen.feed(text)
        return screen.plainText()
    }

    // MARK: - Plain text passes through

    @Test func plainTextWithoutEscapesRoundTrips() {
        #expect(plain("hello world") == "hello world")
        #expect(plain("line one\nline two") == "line one\nline two")
    }

    // MARK: - Cursor positioning overwrites in place

    @Test func absoluteCursorPositionPlacesText() {
        // CUP to row 2, col 3 (1-based) then draw — two blank rows-worth before it.
        #expect(plain("\(esc)[2;3HX") == "\n  X")
    }

    @Test func columnAddressOverwritesEarlierCells() {
        // Draw ABC, jump to column 1 (CHA), overwrite the A.
        #expect(plain("ABC\(esc)[1GX") == "XBC")
    }

    @Test func cursorBackThenOverwrite() {
        #expect(plain("ABCDEF\(esc)[3Dxyz") == "ABCxyz")
    }

    @Test func cursorForwardSkipsCellsAsBlanks() {
        // CUF leaves the skipped cells blank (default-styled spaces).
        #expect(plain("A\(esc)[3CB") == "A   B")
    }

    // MARK: - Erase

    @Test func eraseToEndOfLineClearsTail() {
        #expect(plain("ABCDEF\(esc)[3D\(esc)[K") == "ABC")
    }

    @Test func eraseWholeLineClearsIt() {
        // EL 2 blanks the line; the cursor stays, so a redraw lands cleanly.
        #expect(plain("ABCDEF\(esc)[2K\(esc)[1GNEW") == "NEW")
    }

    @Test func eraseDisplayClearsEverythingBeforeRedraw() {
        // The htop pattern: clear the screen, home the cursor, paint a fresh frame.
        #expect(plain("old stuff\(esc)[2J\(esc)[1;1Hnew frame") == "new frame")
    }

    // MARK: - SGR per cell

    @Test func styleIsCarriedPerCell() {
        var screen = TerminalScreen(columns: 80)
        screen.feed("\(esc)[31mR\(esc)[0mX")
        let runs = screen.runs()
        #expect(runs.count == 2)
        #expect(runs[0].text == "R" && runs[0].style.foreground == .indexed(1))
        #expect(runs[1].text == "X" && runs[1].style.foreground == .default)
    }

    @Test func overwrittenCellTakesTheNewStyle() {
        // Draw a red A, then overwrite the same cell with a default-styled B.
        var screen = TerminalScreen(columns: 80)
        screen.feed("\(esc)[31mA\(esc)[0m\(esc)[1GB")
        let runs = screen.runs()
        #expect(runs.count == 1)
        #expect(runs[0].text == "B" && runs[0].style.foreground == .default)
    }

    // MARK: - Autowrap

    @Test func textAutowrapsAtTheColumnWidth() {
        #expect(plain("ABCDEFG", columns: 4) == "ABCD\nEFG")
    }

    // MARK: - Vertical movement

    @Test func cursorUpOverwritesAnEarlierRow() {
        // Draw two rows, move up one, overwrite the start of the first.
        #expect(plain("row1\nrow2\(esc)[A\(esc)[1GR") == "Row1\nrow2")
    }

    // MARK: - Trailing blanks are trimmed

    @Test func trailingBlankRowsAreTrimmed() {
        #expect(plain("A\n\n\n") == "A")
    }

    @Test func trailingBlankCellsAreTrimmed() {
        // CUF past the text then nothing — the skipped cells must not pad the line.
        #expect(plain("hi\(esc)[20C") == "hi")
    }

    // MARK: - Alternate screen (the htop / vim capture)

    @Test func alternateScreenFrameIsCapturedOnExit() {
        // A TUI: switch to the alt screen, paint a frame, leave — the trailing shell
        // prompt on the restored primary screen must not hide the captured frame.
        let stream =
            "shell prompt $ htop\n"
            + "\(esc)[?1049h\(esc)[2J\(esc)[1;1HTUI FRAME\(esc)[?1049l"
            + "shell prompt $ "
        #expect(plain(stream) == "TUI FRAME")
    }

    @Test func stillOnAlternateScreenReturnsItsContent() {
        // The program never left the alt screen (capture taken mid-run) — its buffer is
        // the screen to report, not the stashed primary.
        let stream = "primary\(esc)[?1049h\(esc)[1;1HALT BUFFER"
        #expect(plain(stream) == "ALT BUFFER")
    }

    // MARK: - Cursor save / restore

    @Test func saveAndRestoreCursorReturnsToTheMark() {
        // Save at col 2, wander right and draw, restore, draw at the mark.
        #expect(plain("AB\(esc)[s\(esc)[5GZ\(esc)[uC") == "ABC Z")
    }

    // MARK: - OSC 8 hyperlinks survive into the grid

    @Test func hyperlinkRidesOnTheCell() {
        var screen = TerminalScreen(columns: 80)
        screen.feed("\(esc)]8;;https://example.com\u{07}link\(esc)]8;;\u{07}")
        let runs = screen.runs()
        #expect(runs.count == 1)
        #expect(runs[0].text == "link")
        #expect(runs[0].style.hyperlink == "https://example.com")
    }

    // MARK: - A small realistic frame

    @Test func reconstructsAMiniBoxedFrame() {
        // Cursor-addressed lines with a box-drawing border and a colored title — the
        // shape a TUI paints. Each line is positioned absolutely, out of order.
        let frame =
            "\(esc)[2J"
            + "\(esc)[1;1H┌────────┐"
            + "\(esc)[3;1H└────────┘"
            + "\(esc)[2;1H│\(esc)[32m hello  \(esc)[0m│"
        #expect(plain(frame) == "┌────────┐\n│ hello  │\n└────────┘")
    }

    // MARK: - Static convenience

    @Test func staticRunsConvenienceMatchesInstance() {
        let viaStatic = TerminalScreen.runs("\(esc)[2;1HX", columns: 80).map(\.text).joined()
        #expect(viaStatic == "\nX")
    }
}
