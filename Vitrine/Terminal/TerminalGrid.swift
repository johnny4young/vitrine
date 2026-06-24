import Foundation

/// One cell of a reconstructed terminal screen: a single visible scalar and the SGR
/// style it was drawn with. A blank cell is a space in the default style.
struct TerminalCell: Equatable {
    var scalar: Unicode.Scalar
    var style: ANSIStyle

    /// An empty cell — a space with no styling.
    static let blank = TerminalCell(scalar: " ", style: ANSIStyle())

    /// Whether the cell is an unstyled space, i.e. nothing was drawn here. Trailing
    /// blanks are trimmed when the screen is flattened into runs.
    var isBlank: Bool { scalar == " " && style == ANSIStyle() }
}

/// A cell-buffer VT emulator: replays a stream of terminal output that addresses the
/// screen with cursor-positioning escapes (CUP, erase, alternate screen) and reports
/// the **final** screen state.
///
/// This is the grid counterpart to ``ANSIRenderer/normalize(_:)``, which is
/// line-oriented and strips cursor moves: where line mode captures the scrolled
/// transcript (a `git log`, a test run), the grid captures the screen a full-screen
/// TUI — `htop`, `vim`, `lazygit` — paints by writing cells directly. Pure and
/// AppKit-free for unit-testing, like ``ANSIParser``: it produces `[ANSIRun]` that
/// ``ANSIRenderer`` turns into the image, reusing ``ANSIStyle`` and
/// ``ANSIParser/applySGR(_:to:)`` for the pen so the styling is identical to line mode.
///
/// **Phase 1 scope:** cursor positioning (CUP/CUU-D/CUF-B/CHA/VPA/CNL/CPL, CR/LF/BS/HT),
/// erase (ED/EL), SGR, autowrap, OSC 8 hyperlinks, save/restore cursor, and the
/// alternate-screen snapshot that makes `htop`/`vim` capturable. Deferred: scroll
/// regions (DECSTBM), line/character insert-delete, and wide (double-width) characters.
struct TerminalScreen {
    /// The width the stream was produced at: cursor columns clamp to it and printed
    /// text autowraps at it.
    let columns: Int
    /// A safety cap so a malformed stream addressing huge rows can't grow the buffer
    /// without bound. Real TUIs fit a screen; this is far above any terminal height.
    private let maxRows: Int

    /// The visible buffer — the primary screen, or the alternate screen while in it.
    /// Rows grow on demand; each row grows to its longest written column.
    private var rows: [[TerminalCell]] = [[]]
    private var cursorRow = 0
    private var cursorCol = 0
    /// The current pen, accumulated from SGR codes (and the OSC 8 link, which rides on
    /// the style so each cell remembers its hyperlink).
    private var style = ANSIStyle()
    private var saved: (row: Int, col: Int, style: ANSIStyle)?

    /// While on the alternate screen the primary buffer is stashed here; `nil` on the
    /// primary screen.
    private var primaryStash: (rows: [[TerminalCell]], row: Int, col: Int)?
    /// The last full alternate-screen frame, captured when the program *leaves* the alt
    /// screen (its exit). That frame is the htop/vim screen the user actually saw, which
    /// the trailing shell prompt on the restored primary screen would otherwise hide.
    private var capturedAltFrame: [[TerminalCell]]?

    init(columns: Int = 80, maxRows: Int = 1000) {
        self.columns = max(1, columns)
        self.maxRows = max(1, maxRows)
    }

    // MARK: - Convenience

    /// Replays `text` at `columns` width and returns the final screen as styled runs,
    /// ready for ``ANSIRenderer`` — rows joined by newlines, trailing blank cells and
    /// rows trimmed.
    static func runs(_ text: String, columns: Int = 80) -> [ANSIRun] {
        var screen = TerminalScreen(columns: columns)
        screen.feed(text)
        return screen.runs()
    }

    // MARK: - Routing: is this a full-screen TUI?

    /// Whether `text` addresses the screen with cursor positioning — the signal that it
    /// is a full-screen TUI (htop, vim, lazygit) whose final frame the grid emulator
    /// should reconstruct, rather than scrolling output the line renderer should keep
    /// verbatim.
    ///
    /// Triggers on the unambiguous full-screen markers: entering the alternate screen
    /// (`?1049h`/`?47h`/`?1047h`), an erase-display (`ED`), or absolute cursor
    /// positioning (`CUP` to a non-home cell, or `VPA`). Plain colored output (`git`,
    /// `ls`, a test run) carries only SGR — and a progress bar only `\r`/`EL` — so none
    /// of them trip this and they stay in line mode. `EL` (erase *line*) is deliberately
    /// not a trigger: it is the progress-bar idiom, which line mode already handles.
    static func usesScreenAddressing(_ text: String) -> Bool {
        guard ANSIParser.containsANSI(text) else { return false }
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "\u{1B}", index + 1 < scalars.count else {
                index += 1
                continue
            }
            guard scalars[index + 1] == "[" else {  // only CSI carries these
                index += 2
                continue
            }
            let (params, finalByte, end) = ANSIParser.scanCSI(scalars, from: index + 2)
            index = end
            guard let finalByte else { break }
            if params.hasPrefix("?") {
                let modes = params.dropFirst().split(separator: ";").compactMap { Int($0) }
                if finalByte == "h" || finalByte == "l",
                    modes.contains(where: { $0 == 1049 || $0 == 47 || $0 == 1047 })
                {
                    return true  // alternate screen
                }
                continue
            }
            switch finalByte {
            case "J": return true  // ED — erase display (full-screen redraw)
            case "d": return true  // VPA — absolute row
            case "H", "f":  // CUP — count only positioning beyond home
                if !params.isEmpty, params != "1", params != "1;1", params != ";" {
                    return true
                }
            default: break
            }
        }
        return false
    }

    /// A safe column width to replay `text` at: wide enough that no addressed cell or
    /// printed line wraps early — the grid trims trailing blanks, so over-estimating is
    /// harmless, while under-estimating would wrap a TUI's content wrong. Floors at 80
    /// and caps at a sane maximum.
    static func inferColumns(_ text: String) -> Int {
        let scalars = Array(text.unicodeScalars)
        var maxWidth = 80
        var lineWidth = 0
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\u{1B}", index + 1 < scalars.count, scalars[index + 1] == "[" {
                let (params, finalByte, end) = ANSIParser.scanCSI(scalars, from: index + 2)
                if let finalByte, !params.hasPrefix("?") {
                    let nums = params.split(separator: ";", omittingEmptySubsequences: false)
                        .map { Int($0) ?? 0 }
                    if finalByte == "H" || finalByte == "f", nums.count > 1 {
                        maxWidth = max(maxWidth, nums[1])  // CUP column
                    }
                    if finalByte == "G", let column = nums.first {
                        maxWidth = max(maxWidth, column)  // CHA absolute column
                    }
                }
                index = end
                continue
            }
            if scalar == "\n" || scalar == "\r" {
                lineWidth = 0
            } else if scalar.value >= 0x20, scalar.value != 0x7F {
                lineWidth += 1
                maxWidth = max(maxWidth, lineWidth)
            }
            index += 1
        }
        return min(maxWidth, 1000)
    }

    // MARK: - Feeding the stream

    /// Replays the bytes of `text`, mutating the screen. Reuses ``ANSIParser``'s CSI/OSC
    /// scanners so there is a single parser of the escape-sequence wire format.
    mutating func feed(_ text: String) {
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            switch scalar {
            case "\u{1B}":  // ESC
                guard index + 1 < scalars.count else { return }  // lone trailing ESC
                switch scalars[index + 1] {
                case "[":  // CSI
                    let (params, finalByte, end) = ANSIParser.scanCSI(scalars, from: index + 2)
                    if let finalByte { applyCSI(params, finalByte) }
                    index = end
                case "]":  // OSC — OSC 8 sets/clears the link on the pen; others drop
                    let (body, end) = ANSIParser.scanOSC(scalars, from: index + 2)
                    if let uri = ANSIParser.hyperlinkURI(fromOSC: body) {
                        style.hyperlink = uri.isEmpty ? nil : uri
                    }
                    index = end
                case "7":
                    saveCursor()
                    index += 2  // DECSC
                case "8":
                    restoreCursor()
                    index += 2  // DECRC
                default:
                    // ESC followed by an intermediate byte (0x20–0x2F) is a longer
                    // sequence — most often charset designation (`ESC ( B`, which htop and
                    // friends emit constantly): consume the intermediate(s) and the final
                    // byte, so the final (e.g. `B`) is never printed as stray text. Any
                    // other `ESC <byte>` is a two-byte escape (`ESC =`, `ESC M`) — drop both.
                    if (0x20...0x2F).contains(scalars[index + 1].value) {
                        var cursor = index + 1
                        while cursor < scalars.count,
                            (0x20...0x2F).contains(scalars[cursor].value)
                        {
                            cursor += 1
                        }
                        index = cursor < scalars.count ? cursor + 1 : cursor
                    } else {
                        index += 2
                    }
                }
            case "\r":
                cursorCol = 0
                index += 1
            case "\n":
                lineFeed()
                index += 1
            case "\u{08}":
                cursorCol = max(0, cursorCol - 1)
                index += 1  // backspace
            case "\t":
                tab()
                index += 1
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    index += 1  // BEL and other C0/DEL controls — ignore
                } else {
                    putChar(scalar)
                    index += 1
                }
            }
        }
    }

    // MARK: - CSI dispatch

    private mutating func applyCSI(_ params: String, _ finalByte: Unicode.Scalar) {
        // DEC private modes (`ESC[?…h` / `…l`) — the only one Phase 1 acts on is the
        // alternate screen; the rest (cursor visibility, mouse, bracketed paste) are
        // visual no-ops for a static capture.
        if params.hasPrefix("?") {
            applyPrivateMode(String(params.dropFirst()), finalByte)
            return
        }
        let nums = Self.parseParams(params)

        switch finalByte {
        case "m":  // SGR — reuse the line-mode parser so styling matches exactly
            style = ANSIParser.applySGR(params, to: style)
        case "H", "f":  // CUP / HVP — 1-based row;col
            cursorRow = clampRow(Self.at(nums, 0, default: 1) - 1)
            cursorCol = clampCol(Self.at(nums, 1, default: 1) - 1)
        case "A": cursorRow = max(0, cursorRow - Self.at(nums, 0, default: 1))  // up
        case "B": cursorRow = clampRow(cursorRow + Self.at(nums, 0, default: 1))  // down
        case "C": cursorCol = clampCol(cursorCol + Self.at(nums, 0, default: 1))  // forward
        case "D": cursorCol = max(0, cursorCol - Self.at(nums, 0, default: 1))  // back
        case "E":  // CNL — cursor next line
            cursorRow = clampRow(cursorRow + Self.at(nums, 0, default: 1))
            cursorCol = 0
        case "F":  // CPL — cursor previous line
            cursorRow = max(0, cursorRow - Self.at(nums, 0, default: 1))
            cursorCol = 0
        case "G": cursorCol = clampCol(Self.at(nums, 0, default: 1) - 1)  // CHA — absolute column
        case "d": cursorRow = clampRow(Self.at(nums, 0, default: 1) - 1)  // VPA — absolute row
        case "J": eraseDisplay(Self.at(nums, 0, default: 0))  // ED
        case "K": eraseLine(Self.at(nums, 0, default: 0))  // EL
        case "s": saveCursor()  // SCP
        case "u": restoreCursor()  // RCP
        default:
            break  // L/M/P/@/X/S/T/r and friends — deferred to Phase 3
        }
    }

    private mutating func applyPrivateMode(_ params: String, _ finalByte: Unicode.Scalar) {
        let modes = Self.parseParams(params)
        let setting = finalByte == "h"
        for mode in modes where mode == 1049 || mode == 47 || mode == 1047 {
            if setting { enterAltScreen() } else { leaveAltScreen() }
        }
    }

    // MARK: - Drawing

    private mutating func putChar(_ scalar: Unicode.Scalar) {
        ensureRow(cursorRow)
        padRow(cursorRow, to: cursorCol)
        rows[cursorRow][cursorCol] = TerminalCell(scalar: scalar, style: style)
        cursorCol += 1
        if cursorCol >= columns {  // autowrap
            cursorCol = 0
            cursorRow = clampRow(cursorRow + 1)
            ensureRow(cursorRow)
        }
    }

    /// Newline. Treated as CR+LF (column reset *and* down a row) rather than VT-strict
    /// LF (down only): a `script` PTY capture already emits `\r\n` (the `\r` resets the
    /// column, so this is correct for it), and pasted terminal output that uses a bare
    /// `\n` then reads without a staircase. TUIs lay out with absolute positioning, so
    /// the distinction never affects a full-screen capture.
    private mutating func lineFeed() {
        cursorRow = clampRow(cursorRow + 1)
        cursorCol = 0
        ensureRow(cursorRow)
    }

    private mutating func tab() {
        let next = ((cursorCol / 8) + 1) * 8
        cursorCol = min(columns - 1, next)
    }

    // MARK: - Erase

    private mutating func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0:  // cursor → end of screen
            ensureRow(cursorRow)
            padRow(cursorRow, to: cursorCol)
            blank(row: cursorRow, from: cursorCol)
            for row in (cursorRow + 1)..<rows.count { blank(row: row) }
        case 1:  // start of screen → cursor
            for row in 0..<min(cursorRow, rows.count) { blank(row: row) }
            ensureRow(cursorRow)
            padRow(cursorRow, to: cursorCol)
            blank(row: cursorRow, through: cursorCol)
        default:  // 2 / 3 — whole screen
            for row in rows.indices { blank(row: row) }
        }
    }

    private mutating func eraseLine(_ mode: Int) {
        ensureRow(cursorRow)
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
    private mutating func blank(row: Int) {
        guard rows.indices.contains(row) else { return }
        for col in rows[row].indices { rows[row][col] = .blank }
    }

    /// Blanks a row from `start` to its end.
    private mutating func blank(row: Int, from start: Int) {
        guard rows.indices.contains(row) else { return }
        for col in start..<rows[row].count where col >= 0 { rows[row][col] = .blank }
    }

    /// Blanks a row from its start through `end` (inclusive).
    private mutating func blank(row: Int, through end: Int) {
        guard rows.indices.contains(row) else { return }
        for col in 0...min(end, rows[row].count - 1) where col >= 0 { rows[row][col] = .blank }
    }

    // MARK: - Cursor save / restore

    private mutating func saveCursor() { saved = (cursorRow, cursorCol, style) }

    private mutating func restoreCursor() {
        guard let saved else { return }
        cursorRow = clampRow(saved.row)
        cursorCol = clampCol(saved.col)
        style = saved.style
    }

    // MARK: - Alternate screen

    private mutating func enterAltScreen() {
        guard primaryStash == nil else { return }  // already on the alt screen
        primaryStash = (rows, cursorRow, cursorCol)
        rows = [[]]
        cursorRow = 0
        cursorCol = 0
    }

    private mutating func leaveAltScreen() {
        guard let stash = primaryStash else { return }
        capturedAltFrame = rows  // the last full TUI frame, before the prompt redraws
        rows = stash.rows
        cursorRow = clampRow(stash.row)
        cursorCol = clampCol(stash.col)
        primaryStash = nil
    }

    // MARK: - Geometry helpers

    private func clampRow(_ row: Int) -> Int { min(max(0, row), maxRows - 1) }
    private func clampCol(_ col: Int) -> Int { min(max(0, col), columns - 1) }

    /// Grows `rows` so index `row` exists (within the row cap).
    private mutating func ensureRow(_ row: Int) {
        let target = min(row, maxRows - 1)
        while rows.count <= target { rows.append([]) }
    }

    /// Grows `rows[row]` so column `col` exists, padding with blank cells.
    private mutating func padRow(_ row: Int, to col: Int) {
        guard rows.indices.contains(row) else { return }
        while rows[row].count <= col { rows[row].append(.blank) }
    }

    // MARK: - Output

    /// The screen to report: the captured alternate-screen frame when a TUI ran and
    /// exited, the live buffer when still on the alt screen at end of input, otherwise
    /// the primary buffer.
    private var finalFrame: [[TerminalCell]] {
        if primaryStash != nil { return rows }  // ended inside the alt screen
        if let alt = capturedAltFrame, alt.contains(where: { row in row.contains { !$0.isBlank } })
        {
            return alt
        }
        return rows
    }

    /// The final screen flattened into styled runs: adjacent same-style cells coalesce,
    /// trailing blank cells and trailing blank rows are trimmed, and rows are separated
    /// by a default-styled newline — the same shape ``ANSIParser/parse(_:)`` yields, so
    /// ``ANSIRenderer`` renders a grid and a line capture identically.
    func runs() -> [ANSIRun] {
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
        func emit(_ scalar: Unicode.Scalar, _ cellStyle: ANSIStyle) {
            if text.isEmpty {
                runStyle = cellStyle
            } else if cellStyle != runStyle {
                flush()
                runStyle = cellStyle
            }
            text.unicodeScalars.append(scalar)
        }

        for rowIndex in 0...lastRow {
            let row = frame[rowIndex]
            // Trim trailing blank cells so a row isn't padded to the wrap width.
            var lastCol = row.count - 1
            while lastCol >= 0, row[lastCol].isBlank { lastCol -= 1 }
            if lastCol >= 0 {
                for col in 0...lastCol { emit(row[col].scalar, row[col].style) }
            }
            if rowIndex < lastRow { emit("\n", ANSIStyle()) }
        }
        flush()
        return out
    }

    /// The final screen as plain text (styling dropped) — the copyable-text counterpart
    /// of the rendered image, matching ``ANSIRenderer/plainText(_:)`` for line mode.
    func plainText() -> String {
        runs().map(\.text).joined()
    }

    // MARK: - Parameter parsing

    /// Splits a CSI parameter string (`"2;10"`) into integers; a missing or non-numeric
    /// field is `0`. An empty string yields `[]`.
    private static func parseParams(_ params: String) -> [Int] {
        guard !params.isEmpty else { return [] }
        return params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
    }

    /// The parameter at `index`, treating a missing or zero value as `default` — the CSI
    /// convention where an omitted or `0` count means `1` for cursor moves and positions.
    private static func at(_ nums: [Int], _ index: Int, default fallback: Int) -> Int {
        guard index < nums.count, nums[index] > 0 else { return fallback }
        return nums[index]
    }
}
