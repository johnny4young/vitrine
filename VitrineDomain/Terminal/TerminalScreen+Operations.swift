import Foundation

extension TerminalScreen {
    // MARK: - Drawing

    mutating func putChar(_ scalar: Unicode.Scalar) {
        let width = CharacterWidth.displayWidth(scalar)
        // A combining / zero-width mark stacks on the previous cell without advancing. If
        // there is nothing to stack on (line start), it falls through and prints as width 1.
        if width == 0, appendCombining(scalar) { return }

        if pendingWrap {
            pendingWrap = false
            cursorCol = 0
            indexDown()
        }
        // A base-less combining mark draws as a single cell; on a degenerate 1-column
        // grid a wide char collapses to its head so it never writes past the margin.
        let cells = min(max(1, width), columns)
        // A wide char needs two columns; if only the last one is free, wrap so it isn't
        // split across the right edge.
        if cells == 2, cursorCol == columns - 1 {
            cursorCol = 0
            indexDown()
        }
        writeCell(TerminalCell(content: .grapheme(String(scalar)), style: style), at: cursorCol)
        if cells == 2 {
            writeCell(TerminalCell(content: .continuation, style: style), at: cursorCol + 1)
        }
        let last = cursorCol + cells - 1
        if last >= columns - 1 {
            cursorCol = columns - 1
            pendingWrap = true
        } else {
            cursorCol = last + 1
        }
    }

    /// Stacks a combining / zero-width `scalar` onto the most recent grapheme (skipping a
    /// wide char's continuation back to its head), without moving the cursor. Returns
    /// `false` when there is no base to combine with (e.g. a mark at the line start), so
    /// the caller can draw it as an ordinary cell instead of dropping it.
    mutating func appendCombining(_ scalar: Unicode.Scalar) -> Bool {
        guard rows.indices.contains(cursorRow) else { return false }
        // When autowrap is pending the last glyph sits at the cursor; otherwise it's behind.
        var col = pendingWrap ? cursorCol : cursorCol - 1
        if col >= 0, rows[cursorRow].indices.contains(col),
            case .continuation = rows[cursorRow][col].content
        {
            col -= 1
        }
        guard col >= 0, rows[cursorRow].indices.contains(col),
            case .grapheme(let base) = rows[cursorRow][col].content
        else { return false }
        rows[cursorRow][col] = TerminalCell(
            content: .grapheme(base + String(scalar)), style: rows[cursorRow][col].style)
        return true
    }

    /// Writes `cell` at (`cursorRow`, `col`), growing the row to reach it and dissolving any
    /// wide character it would half-overwrite (so a redraw never leaves a stray half-glyph).
    mutating func writeCell(_ cell: TerminalCell, at col: Int) {
        padRow(cursorRow, to: col)
        clearWideOverlap(row: cursorRow, col: col)
        rows[cursorRow][col] = cell
    }

    /// Blanks the orphaned partner of a wide character straddling (`row`, `col`): if the
    /// target is a continuation, blank its head to the left; if it is a wide head, blank
    /// the continuation to its right.
    mutating func clearWideOverlap(row: Int, col: Int) {
        guard rows.indices.contains(row), rows[row].indices.contains(col) else { return }
        if case .continuation = rows[row][col].content {
            if rows[row].indices.contains(col - 1) { rows[row][col - 1] = .blank }
        } else if rows[row].indices.contains(col + 1),
            case .continuation = rows[row][col + 1].content
        {
            rows[row][col + 1] = .blank
        }
    }

    /// The terminal cell width owned by this cell's grapheme head. Continuation cells own no
    /// width because their head to the left carries the glyph.
    func cellDisplayWidth(_ cell: TerminalCell) -> Int {
        guard case .grapheme(let grapheme) = cell.content,
            let scalar = grapheme.unicodeScalars.first
        else { return 0 }
        return CharacterWidth.displayWidth(scalar)
    }

    /// Blanks both cells of a wide character touched by `col`. Unlike `clearWideOverlap`,
    /// this also blanks the target cell because edit/erase operations may shift it instead
    /// of immediately overwriting it.
    mutating func blankWideCluster(row: Int, col: Int) {
        guard rows.indices.contains(row), rows[row].indices.contains(col) else { return }
        if case .continuation = rows[row][col].content {
            rows[row][col] = .blank
            if rows[row].indices.contains(col - 1),
                cellDisplayWidth(rows[row][col - 1]) == 2
            {
                rows[row][col - 1] = .blank
            }
        } else if cellDisplayWidth(rows[row][col]) == 2 {
            rows[row][col] = .blank
            if rows[row].indices.contains(col + 1),
                case .continuation = rows[row][col + 1].content
            {
                rows[row][col + 1] = .blank
            }
        }
    }

    /// Repairs a row after an operation shifts or truncates cells so a wide head is always
    /// immediately followed by its continuation, and a continuation is never headless.
    mutating func repairWideClusters(row: Int) {
        guard rows.indices.contains(row), !rows[row].isEmpty else { return }
        var col = 0
        while col < rows[row].count {
            if case .continuation = rows[row][col].content {
                if col == 0 || cellDisplayWidth(rows[row][col - 1]) != 2 {
                    rows[row][col] = .blank
                }
            } else if cellDisplayWidth(rows[row][col]) == 2 {
                if col + 1 >= rows[row].count {
                    rows[row][col] = .blank
                } else if case .continuation = rows[row][col + 1].content {
                    col += 1
                } else {
                    rows[row][col] = .blank
                }
            }
            col += 1
        }
    }

    /// Move down one line, scrolling the region up if at the bottom margin (the `IND`
    /// behavior a line feed and realized right-edge autowrap share).
    mutating func indexDown() {
        if cursorRow == scrollBottom {
            scrollRegionUp(1)
        } else {
            cursorRow = min(cursorRow + 1, screenRows - 1)
        }
    }

    /// Newline. Treated as CR+LF (column reset *and* down a row) rather than VT-strict LF
    /// (down only): a `script` PTY capture already emits `\r\n` (the `\r` resets the
    /// column, so this is correct for it), and pasted terminal output that uses a bare `\n`
    /// then reads without a staircase.
    mutating func lineFeed() {
        pendingWrap = false
        indexDown()
        cursorCol = 0
    }

    mutating func tab() {
        if pendingWrap {
            pendingWrap = false
            cursorCol = 0
            indexDown()
        }
        let next = ((cursorCol / 8) + 1) * 8
        cursorCol = min(columns - 1, next)
    }

    // MARK: - Scrolling

    /// Sets the DECSTBM scroll region (1-based, inclusive). An invalid or absent pair
    /// resets to the whole screen. Homes the cursor, as the spec requires.
    mutating func setScrollRegion(_ nums: [Int]) {
        let top = Self.at(nums, 0, default: 1) - 1
        let bottom = (nums.count > 1 && nums[1] > 0 ? nums[1] : screenRows) - 1
        if top >= 0, bottom < screenRows, top < bottom {
            scrollTop = top
            scrollBottom = bottom
        } else {
            scrollTop = 0
            scrollBottom = screenRows - 1
        }
        cursorRow = 0
        cursorCol = 0
    }

    /// Scrolls `[scrollTop, scrollBottom]` up by `count` lines: the top lines fall off and
    /// blank lines come in at the bottom of the region. The standard terminal scroll.
    mutating func scrollRegionUp(_ count: Int) {
        let n = min(max(1, count), scrollBottom - scrollTop + 1)
        rows.removeSubrange(scrollTop..<(scrollTop + n))
        rows.insert(contentsOf: blankRows(n), at: scrollBottom - n + 1)
    }

    /// Scrolls `[scrollTop, scrollBottom]` down by `count`: bottom lines fall off, blanks
    /// come in at the top of the region (used by RI and SD).
    mutating func scrollRegionDown(_ count: Int) {
        let n = min(max(1, count), scrollBottom - scrollTop + 1)
        rows.removeSubrange((scrollBottom - n + 1)..<(scrollBottom + 1))
        rows.insert(contentsOf: blankRows(n), at: scrollTop)
    }

    /// Inserts `count` blank lines at the cursor, pushing lines below it down within the
    /// region (lines past the bottom fall off). Editors use this to open a line.
    mutating func insertLines(_ count: Int) {
        guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
        let n = min(max(1, count), scrollBottom - cursorRow + 1)
        rows.removeSubrange((scrollBottom - n + 1)..<(scrollBottom + 1))
        rows.insert(contentsOf: blankRows(n), at: cursorRow)
    }

    /// Deletes `count` lines at the cursor, pulling lines below it up within the region
    /// (blanks come in at the bottom). Editors use this to close a line.
    mutating func deleteLines(_ count: Int) {
        guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
        let n = min(max(1, count), scrollBottom - cursorRow + 1)
        rows.removeSubrange(cursorRow..<(cursorRow + n))
        rows.insert(contentsOf: blankRows(n), at: scrollBottom - n + 1)
    }

    func blankRows(_ count: Int) -> [[TerminalCell]] {
        Array(repeating: [], count: count)
    }

    // MARK: - Character insert / delete (within the cursor row)

    /// Inserts `count` blank cells at the cursor, shifting the rest of the row right; cells
    /// pushed past the right margin fall off. The `ICH` a line editor uses to open space
    /// mid-line (e.g. shell autosuggestion, `readline` insert mode).
    mutating func insertChars(_ count: Int) {
        guard rows.indices.contains(cursorRow) else { return }
        let n = min(max(1, count), columns - cursorCol)
        guard n > 0 else { return }
        padRow(cursorRow, to: cursorCol)
        blankWideCluster(row: cursorRow, col: cursorCol)
        rows[cursorRow].insert(contentsOf: Array(repeating: .blank, count: n), at: cursorCol)
        if rows[cursorRow].count > columns {
            rows[cursorRow].removeLast(rows[cursorRow].count - columns)
        }
        repairWideClusters(row: cursorRow)
    }

    /// Deletes `count` cells at the cursor, pulling the rest of the row left and backfilling
    /// blanks at the right (those trailing blanks are trimmed on output). The `DCH` a line
    /// editor uses to close space mid-line.
    mutating func deleteChars(_ count: Int) {
        guard rows.indices.contains(cursorRow), cursorCol < rows[cursorRow].count else { return }
        let n = min(max(1, count), rows[cursorRow].count - cursorCol)
        for col in cursorCol..<(cursorCol + n) { blankWideCluster(row: cursorRow, col: col) }
        rows[cursorRow].removeSubrange(cursorCol..<(cursorCol + n))
        rows[cursorRow].append(contentsOf: Array(repeating: .blank, count: n))
        repairWideClusters(row: cursorRow)
    }

    /// Blanks `count` cells from the cursor in place, leaving the rest of the row where it
    /// is. `ECH` — like erase-to-end-of-line (`EL`) from the cursor, but bounded to a count.
    mutating func eraseChars(_ count: Int) {
        guard rows.indices.contains(cursorRow) else { return }
        padRow(cursorRow, to: cursorCol)
        let end = min(cursorCol + max(1, count), rows[cursorRow].count)
        guard cursorCol < end else { return }
        for col in cursorCol..<end { blankWideCluster(row: cursorRow, col: col) }
        for col in cursorCol..<end { rows[cursorRow][col] = .blank }
        repairWideClusters(row: cursorRow)
    }

    // MARK: - Erase

    mutating func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0:  // cursor → end of screen
            padRow(cursorRow, to: cursorCol)
            blank(row: cursorRow, from: cursorCol)
            for row in (cursorRow + 1)..<rows.count { blank(row: row) }
        case 1:  // start of screen → cursor
            for row in 0..<min(cursorRow, rows.count) { blank(row: row) }
            padRow(cursorRow, to: cursorCol)
            blank(row: cursorRow, through: cursorCol)
        default:  // 2 / 3 — whole screen
            // If a full clear would blank a populated alt-screen buffer — apps that erase
            // the screen right before leaving the alt buffer on exit — keep a pre-clear
            // copy so the final frame isn't lost.
            if primaryStash != nil, isPopulated(rows) { altSnapshot = rows }
            for row in rows.indices { blank(row: row) }
        }
    }

    /// Whether any cell in `frame` was actually drawn (a non-blank cell).
    func isPopulated(_ frame: [[TerminalCell]]) -> Bool {
        frame.contains { row in row.contains { !$0.isBlank } }
    }

    mutating func eraseLine(_ mode: Int) {
        switch mode {
        case 1:
            padRow(cursorRow, to: cursorCol)
            blank(row: cursorRow, through: cursorCol)
        case 2: blank(row: cursorRow)
        default:
            padRow(cursorRow, to: cursorCol)
            blank(row: cursorRow, from: cursorCol)
        }
    }

    /// Blanks an entire row in place (keeping its current length).
    mutating func blank(row: Int) {
        guard rows.indices.contains(row) else { return }
        for col in rows[row].indices { rows[row][col] = .blank }
    }

    /// Blanks a row from `start` to its end.
    mutating func blank(row: Int, from start: Int) {
        guard rows.indices.contains(row) else { return }
        let start = max(0, start)
        guard start < rows[row].count else { return }
        for col in start..<rows[row].count { blankWideCluster(row: row, col: col) }
        for col in start..<rows[row].count { rows[row][col] = .blank }
        repairWideClusters(row: row)
    }

    /// Blanks a row from its start through `end` (inclusive).
    mutating func blank(row: Int, through end: Int) {
        guard rows.indices.contains(row) else { return }
        let end = min(end, rows[row].count - 1)
        guard end >= 0 else { return }
        for col in 0...end { blankWideCluster(row: row, col: col) }
        for col in 0...end { rows[row][col] = .blank }
        repairWideClusters(row: row)
    }

    // MARK: - Cursor save / restore

    mutating func saveCursor() { saved = (cursorRow, cursorCol, pendingWrap, style) }

    mutating func restoreCursor() {
        guard let saved else { return }
        cursorRow = clampRow(saved.row)
        cursorCol = clampCol(saved.col)
        pendingWrap = saved.pendingWrap
        style = saved.style
    }

    // MARK: - Alternate screen

    mutating func enterAltScreen() {
        guard primaryStash == nil else { return }  // already on the alt screen
        primaryStash = (rows, cursorRow, cursorCol, pendingWrap, scrollTop, scrollBottom)
        rows = Array(repeating: [], count: screenRows)
        cursorRow = 0
        cursorCol = 0
        pendingWrap = false
        scrollTop = 0
        scrollBottom = screenRows - 1
        // Each alt session starts clean: never let a snapshot from a previous alt session
        // (entered, cleared while empty, then exited) leak into this one's capture.
        altSnapshot = nil
    }

    mutating func leaveAltScreen() {
        guard let stash = primaryStash else { return }
        // The last full TUI frame: the live alt buffer, or the pre-clear snapshot when the
        // app erased the screen on its way out.
        capturedAltFrame = isPopulated(rows) ? rows : altSnapshot
        altSnapshot = nil  // consumed — drop the prior frame and guard against reuse
        rows = stash.rows
        cursorRow = clampRow(stash.row)
        cursorCol = clampCol(stash.col)
        pendingWrap = stash.pendingWrap
        scrollTop = stash.top
        scrollBottom = stash.bottom
        primaryStash = nil
    }

    // MARK: - Geometry helpers

    func clampRow(_ row: Int) -> Int { min(max(0, row), screenRows - 1) }
    func clampCol(_ col: Int) -> Int { min(max(0, col), columns - 1) }

    /// Grows `rows[row]` so column `col` exists, padding with blank cells.
    mutating func padRow(_ row: Int, to col: Int) {
        guard rows.indices.contains(row) else { return }
        while rows[row].count <= col { rows[row].append(.blank) }
    }
}
