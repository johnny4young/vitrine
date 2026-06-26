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

    @Test func newlineAfterFullWidthLineDoesNotDoubleAdvance() {
        #expect(plain("ABCD\nEFG", columns: 4) == "ABCD\nEFG")
        #expect(plain("ABCD\r\nEFG", columns: 4) == "ABCD\nEFG")
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

    @Test func alternateScreenClearedBeforeExitStillCaptures() {
        // nvim/lazygit erase the whole screen *before* leaving the alt buffer on exit;
        // the pre-clear snapshot must still recover the frame the user saw.
        let stream = "\(esc)[?1049h\(esc)[1;1HEDITOR\(esc)[2J\(esc)[?1049lshell$ "
        #expect(plain(stream) == "EDITOR")
    }

    @Test func altSnapshotDoesNotLeakAcrossAltSessions() {
        // A first alt session leaves a pre-clear snapshot; a second session that is
        // entered, cleared while still empty, then exited must NOT reuse that stale frame.
        let stream =
            "\(esc)[?1049h\(esc)[1;1HFIRST\(esc)[2J\(esc)[?1049l"  // draw, clear, leave
            + "PRIMARY"  // primary-screen content
            + "\(esc)[?1049h\(esc)[2J\(esc)[?1049l"  // enter, clear-while-empty, leave
        let result = plain(stream)
        #expect(!result.contains("FIRST"))  // no stale frame leaked from the first session
        #expect(result.contains("PRIMARY"))  // the real last screen
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

    // MARK: - Charset designation must not leak its final byte

    @Test func charsetDesignationIsConsumedNotPrinted() {
        // `ESC ( B` (designate ASCII into G0) is three bytes; htop and friends emit it
        // constantly. The final `B` must be swallowed, not printed as stray text.
        #expect(plain("A\(esc)(BC") == "AC")
        #expect(plain("\(esc)(0x\(esc)(By") == "xy")  // line-drawing in, ASCII back out
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

    // MARK: - Scrolling (bounded screen)

    @Test func lineFeedAtBottomScrollsTheScreen() {
        // A 3-row screen: writing a 4th line scrolls the first off the top — the bounded
        // behavior pagers (less/man) rely on, instead of growing the buffer unbounded.
        var screen = TerminalScreen(columns: 10, rows: 3)
        screen.feed("L1\nL2\nL3\nL4")
        #expect(screen.plainText() == "L2\nL3\nL4")
    }

    @Test func scrollRegionConfinesScrolling() {
        // DECSTBM keeps a header fixed while the body below it scrolls.
        var screen = TerminalScreen(columns: 12, rows: 5)
        screen.feed("\(esc)[1;1HHEADER\(esc)[2;5r\(esc)[2;1Ha\nb\nc\nd\ne")
        #expect(screen.plainText() == "HEADER\nb\nc\nd\ne")  // 'a' scrolled off, header kept
    }

    @Test func deleteLinesPullsContentUp() {
        var screen = TerminalScreen(columns: 6, rows: 4)
        screen.feed("\(esc)[1;1Hone\ntwo\nthree\nfour\(esc)[2;1H\(esc)[M")  // DL at line 2
        #expect(screen.plainText() == "one\nthree\nfour")
    }

    @Test func insertLinesPushesContentDown() {
        var screen = TerminalScreen(columns: 6, rows: 4)
        screen.feed("\(esc)[1;1Hone\ntwo\nthree\nfour\(esc)[2;1H\(esc)[L")  // IL at line 2
        #expect(screen.plainText() == "one\n\ntwo\nthree")  // 'four' pushed off the bottom
    }

    // MARK: - Character insert / delete / erase (ICH / DCH / ECH)

    @Test func insertCharsShiftsTheRowRight() {
        // ICH opens blank space at the cursor, pushing the rest right.
        #expect(plain("ABCDEF\(esc)[3D\(esc)[2@") == "ABC  DEF")
    }

    @Test func insertCharsPushedPastWidthFallOff() {
        // ICH at the line start on a narrow screen drops the cells pushed past the margin.
        #expect(plain("ABCD\(esc)[1G\(esc)[2@", columns: 4) == "  AB")
    }

    @Test func deleteCharsPullsTheRowLeft() {
        // DCH removes cells at the cursor; the tail slides left (backfilled blanks trim off).
        #expect(plain("ABCDEF\(esc)[3D\(esc)[2P") == "ABCF")
    }

    @Test func eraseCharsBlanksInPlaceWithoutShifting() {
        // ECH blanks a bounded count from the cursor but leaves the rest where it is.
        #expect(plain("ABCDEF\(esc)[3D\(esc)[2X") == "ABC  F")
    }

    @Test func characterEditCountDefaultsToOne() {
        // An omitted count means 1, the CSI convention.
        #expect(plain("ABC\(esc)[1G\(esc)[P") == "BC")  // DCH deletes the A
        #expect(plain("ABC\(esc)[1G\(esc)[@") == " ABC")  // ICH opens one blank at the start
    }

    @Test func inferRowsFromBottomAddressing() {
        #expect(TerminalScreen.inferRows("\(esc)[34;1Hstatus") == 34)  // the addressed bottom
        #expect(TerminalScreen.inferRows("plain \(esc)[31mtext\(esc)[0m") == 40)  // no addressing
        #expect(TerminalScreen.inferRows("\(esc)[2;1Hx") == 24)  // floor
    }

    // MARK: - Detection: line vs grid routing

    @Test func plainColoredOutputStaysLineMode() {
        #expect(!TerminalScreen.usesScreenAddressing("\(esc)[31mred\(esc)[0m plain"))
        // A progress bar (CR + erase-line) is the line-mode idiom, not a full screen.
        #expect(!TerminalScreen.usesScreenAddressing("10%\r20%\r\(esc)[Kdone"))
        // Bare cursor-home alone isn't enough to call it a TUI.
        #expect(!TerminalScreen.usesScreenAddressing("\(esc)[Hhi"))
    }

    @Test func cursorAddressedOutputUsesGrid() {
        // The alt screen, erase-display (ED), absolute CUP, and VPA each mark a TUI.
        #expect(TerminalScreen.usesScreenAddressing("\(esc)[?1049hframe\(esc)[?1049l"))
        #expect(TerminalScreen.usesScreenAddressing("\(esc)[2Jcleared"))
        #expect(TerminalScreen.usesScreenAddressing("\(esc)[5;10Hx"))
        #expect(TerminalScreen.usesScreenAddressing("\(esc)[3dx"))
    }

    @Test func inferColumnsFloorsAt80AndWidensForContent() {
        #expect(TerminalScreen.inferColumns("short") == 80)
        #expect(TerminalScreen.inferColumns(String(repeating: "x", count: 120)) == 120)
        #expect(TerminalScreen.inferColumns("\(esc)[1;200Hedge") == 200)  // CUP column
    }

    @Test func inferColumnsIgnoresEscapeBodies() {
        let longURI = "https://example.com/" + String(repeating: "x", count: 200)
        #expect(TerminalScreen.inferColumns("\(esc)]8;;\(longURI)\u{07}link\(esc)]8;;\u{07}") == 80)
        #expect(TerminalScreen.inferColumns("A\(esc)(BC") == 80)
    }

    // MARK: - Renderer routing (canvas + sidecar go through ANSIRenderer)

    @Test func rendererRoutesTUIThroughTheGrid() {
        // The renderer reconstructs the alt-screen frame for a TUI, not the escape soup —
        // so the canvas image and the copyable-text sidecar both show the final screen.
        let tui = "before\(esc)[?1049h\(esc)[2J\(esc)[1;1HTUI\(esc)[?1049lafter"
        #expect(ANSIRenderer.plainText(tui) == "TUI")
    }

    @Test func rendererKeepsScrollingOutputInLineMode() {
        // Plain colored output is untouched: the line path strips SGR to plain text and
        // keeps every scrolled line (no grid, no cap).
        #expect(ANSIRenderer.plainText("\(esc)[32mok\(esc)[0m\nnext") == "ok\nnext")
    }

    @Test func explicitColumnsOverrideInferenceInGridMode() {
        // `--terminal-width` flows through ANSIRenderer to the grid emulator. ED puts the
        // stream in grid mode; a 10-char line then wraps at the pinned width, where the
        // inferred width (floored at 80) would keep it on one line.
        let tui = "\(esc)[2JABCDEFGHIJ"
        #expect(ANSIRenderer.plainText(tui) == "ABCDEFGHIJ")  // inferred ≥ 80: no wrap
        #expect(ANSIRenderer.plainText(tui, columns: 4) == "ABCD\nEFGH\nIJ")  // pinned to 4
    }
}
