import Foundation

/// One cell of a reconstructed terminal screen and the SGR style it was drawn with. A
/// blank cell is a space in the default style.
struct TerminalCell: Equatable {
    /// What occupies the cell: a grapheme — a base scalar plus any combining marks — or
    /// the right half of a wide (double-width) character to its left, a placeholder that
    /// owns no glyph and is never emitted (the head to its left carries the text).
    enum Content: Equatable {
        case grapheme(String)
        case continuation
    }

    var content: Content
    var style: ANSIStyle

    /// An empty cell — a space with no styling.
    static let blank = TerminalCell(content: .grapheme(" "), style: ANSIStyle())

    /// Whether the cell is an unstyled space, i.e. nothing was drawn here. Trailing
    /// blanks are trimmed when the screen is flattened into runs. A continuation cell is
    /// never blank: its head to the left is live content.
    var isBlank: Bool {
        guard case .grapheme(" ") = content else { return false }
        return style == ANSIStyle()
    }
}

/// A cell-buffer VT emulator: replays a stream of terminal output that addresses the
/// screen with cursor-positioning escapes (CUP, erase, scrolling, alternate screen) and
/// reports the **final** screen state.
///
/// This is the grid counterpart to ``ANSIRenderer/normalize(_:)``, which is
/// line-oriented and strips cursor moves: where line mode captures the scrolled
/// transcript (a `git log`, a test run), the grid captures the screen a full-screen
/// TUI — `htop`, `vim`, `lazygit`, or a pager like `less`/`man` — paints by writing
/// cells directly. Pure and AppKit-free for unit-testing, like ``ANSIParser``: it
/// produces `[ANSIRun]` that ``ANSIRenderer`` turns into the image, reusing ``ANSIStyle``
/// and ``ANSIParser/applySGR(_:to:)`` for the pen so the styling matches line mode.
///
/// The screen is a **fixed height** (`screenRows`, inferred from the stream): a line feed
/// at the bottom margin *scrolls* the screen up instead of growing the buffer, which is
/// what a real terminal does and what pagers (`less`, `man`, `bat`) rely on — they write
/// from the bottom line and let `\n` scroll. A growing buffer would stack the whole file
/// with the content stranded at the bottom.
///
/// Handles: cursor positioning (CUP/CUU-D/CUF-B/CHA/VPA/CNL/CPL, CR/LF/BS/HT), erase
/// (ED/EL), SGR, autowrap, OSC 8 hyperlinks, save/restore cursor, the alternate-screen
/// snapshot that makes `htop`/`vim` capturable, charset-designation escapes, and **scroll
/// regions** (DECSTBM) with scroll-up/down (SU/SD), insert/delete-line (IL/DL),
/// character insert/delete/erase (ICH/DCH/ECH), reverse-index / index / next-line
/// (RI/IND/NEL), and **wide (double-width CJK/emoji) characters** plus combining marks
/// (via ``CharacterWidth``), which advance the cursor by 2 and 0 columns respectively.
struct TerminalScreen {
    /// The width the stream was produced at: cursor columns clamp to it and printed text
    /// autowraps at it.
    let columns: Int
    /// The fixed screen height. The grid is always exactly this many rows; a line feed at
    /// the scroll-region bottom scrolls rather than adding a row.
    let screenRows: Int

    /// The visible buffer — always `screenRows` rows tall; each row grows to its longest
    /// written column. The primary screen, or the alternate screen while in it.
    private var rows: [[TerminalCell]]
    private var cursorRow = 0
    private var cursorCol = 0
    /// Real terminals delay autowrap until the next printable character. Keeping that
    /// pending state avoids double-advancing when a full-width line is followed by `\n`.
    private var pendingWrap = false
    /// The current pen, accumulated from SGR codes (and the OSC 8 link, which rides on the
    /// style so each cell remembers its hyperlink).
    private var style = ANSIStyle()
    private var saved: (row: Int, col: Int, pendingWrap: Bool, style: ANSIStyle)?
    /// The scroll region (DECSTBM), inclusive 0-based row bounds. Defaults to the whole
    /// screen; a line feed at `scrollBottom` scrolls `[scrollTop, scrollBottom]` up.
    private var scrollTop = 0
    private var scrollBottom = 0

    /// While on the alternate screen the primary buffer (and its cursor / scroll region)
    /// is stashed here; `nil` on the primary screen.
    private var primaryStash:
        (
            rows: [[TerminalCell]], row: Int, col: Int, pendingWrap: Bool, top: Int, bottom: Int
        )?
    /// The last full alternate-screen frame, captured when the program *leaves* the alt
    /// screen (its exit) — the htop/vim screen the user saw, which the restored primary
    /// screen's shell prompt would otherwise hide.
    private var capturedAltFrame: [[TerminalCell]]?
    /// A fallback alt-screen frame snapshotted just before an in-alt full clear: some apps
    /// (`nvim`, `lazygit`) erase the screen *before* leaving the alt buffer on exit, which
    /// would otherwise blank the frame we capture.
    private var altSnapshot: [[TerminalCell]]?

    init(columns: Int = 80, rows screenRows: Int = 200) {
        self.columns = max(1, columns)
        self.screenRows = max(1, min(screenRows, 1000))
        self.rows = Array(repeating: [], count: self.screenRows)
        self.scrollBottom = self.screenRows - 1
    }

    // MARK: - Convenience

    /// Replays `text` at an inferred width and height and returns the final screen as
    /// styled runs, ready for ``ANSIRenderer``.
    static func runs(_ text: String, columns: Int? = nil) -> [ANSIRun] {
        var screen = TerminalScreen(
            columns: columns ?? inferColumns(text), rows: inferRows(text))
        screen.feed(text)
        return screen.runs()
    }

    // MARK: - Routing: is this a full-screen TUI?

    /// Whether `text` addresses the screen with cursor positioning — the signal that it is
    /// a full-screen TUI (htop, vim, a pager) whose final frame the grid emulator should
    /// reconstruct, rather than scrolling output the line renderer should keep verbatim.
    ///
    /// Triggers on the unambiguous full-screen markers: entering the alternate screen
    /// (`?1049h`/`?47h`/`?1047h`), an erase-display (`ED`), absolute cursor positioning
    /// (`CUP` to a non-home cell, or `VPA`), or a scroll region (`DECSTBM`). Plain colored
    /// output (`git`, `ls`, a test run) carries only SGR — and a progress bar only
    /// `\r`/`EL` — so none of them trip this and they stay in line mode. `EL` (erase
    /// *line*) is deliberately not a trigger: it is the progress-bar idiom line mode
    /// already handles.
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
            case "r": return true  // DECSTBM — scroll region
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
    /// harmless, while under-estimating would wrap a TUI's content wrong. Floors at 80 and
    /// caps at a sane maximum.
    static func inferColumns(_ text: String) -> Int {
        let scalars = Array(text.unicodeScalars)
        var maxWidth = 80
        var lineWidth = 0
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\u{1B}", index + 1 < scalars.count {
                switch scalars[index + 1] {
                case "[":
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
                case "]":
                    let (_, end) = ANSIParser.scanOSC(scalars, from: index + 2)
                    index = end
                    continue
                default:
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
                    continue
                }
            }
            if scalar == "\n" || scalar == "\r" {
                lineWidth = 0
            } else if scalar.value >= 0x20, scalar.value != 0x7F {
                // Count terminal columns, not scalars: a wide (CJK/emoji) char takes two,
                // a combining mark none — so an unaddressed wide line isn't under-measured
                // and wrapped early.
                lineWidth += CharacterWidth.displayWidth(scalar)
                maxWidth = max(maxWidth, lineWidth)
            }
            index += 1
        }
        return min(maxWidth, 1000)
    }

    /// A safe screen height to replay `text` at: the app reveals its height by addressing
    /// its bottom row (a status line via CUP/VPA, or a DECSTBM bottom margin), so the
    /// highest addressed row is the screen height. Floors at 24 for a sane minimum; an app
    /// that only ever uses relative moves (e.g. `fzf`) gets a typical screen so it stays
    /// bounded. Getting this right is what lets a pager's bottom-line scrolling reconstruct
    /// correctly instead of stacking the whole file.
    static func inferRows(_ text: String) -> Int {
        let scalars = Array(text.unicodeScalars)
        var maxRow = 0
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\u{1B}", index + 1 < scalars.count, scalars[index + 1] == "[" {
                let (params, finalByte, end) = ANSIParser.scanCSI(scalars, from: index + 2)
                if let finalByte, !params.hasPrefix("?") {
                    let nums = params.split(separator: ";", omittingEmptySubsequences: false)
                        .map { Int($0) ?? 0 }
                    if finalByte == "H" || finalByte == "f" || finalByte == "d",
                        let row = nums.first
                    {
                        maxRow = max(maxRow, row)  // CUP / VPA row
                    }
                    if finalByte == "r", nums.count > 1 {
                        maxRow = max(maxRow, nums[1])  // DECSTBM bottom margin
                    }
                }
                index = end
                continue
            }
            index += 1
        }
        if maxRow == 0 { return 40 }  // relative-only app: a typical screen height
        return min(max(maxRow, 24), 300)
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
                case "M":  // RI — reverse index (up; scroll the region down at the top)
                    pendingWrap = false
                    if cursorRow == scrollTop {
                        scrollRegionDown(1)
                    } else {
                        cursorRow = max(0, cursorRow - 1)
                    }
                    index += 2
                case "D":  // IND — index (down; scroll up at the bottom), like a line feed
                    pendingWrap = false
                    indexDown()
                    index += 2
                case "E":  // NEL — next line (CR + IND)
                    pendingWrap = false
                    cursorCol = 0
                    indexDown()
                    index += 2
                default:
                    // ESC followed by an intermediate byte (0x20–0x2F) is a longer
                    // sequence — most often charset designation (`ESC ( B`, which htop and
                    // friends emit constantly): consume the intermediate(s) and the final
                    // byte, so the final (e.g. `B`) is never printed as stray text. Any
                    // other `ESC <byte>` is a two-byte escape (`ESC =`) — drop both.
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
                pendingWrap = false
                cursorCol = 0
                index += 1
            case "\n":
                lineFeed()
                index += 1
            case "\u{08}":
                pendingWrap = false
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
        // DEC private modes (`ESC[?…h` / `…l`) — the only one acted on is the alternate
        // screen; the rest (cursor visibility, mouse, bracketed paste) are visual no-ops
        // for a static capture.
        if params.hasPrefix("?") {
            applyPrivateMode(String(params.dropFirst()), finalByte)
            return
        }
        let nums = Self.parseParams(params)

        switch finalByte {
        case "m":  // SGR — reuse the line-mode parser so styling matches exactly
            style = ANSIParser.applySGR(params, to: style)
        case "H", "f":  // CUP / HVP — 1-based row;col
            pendingWrap = false
            cursorRow = clampRow(Self.at(nums, 0, default: 1) - 1)
            cursorCol = clampCol(Self.at(nums, 1, default: 1) - 1)
        case "A":
            pendingWrap = false
            cursorRow = max(0, cursorRow - Self.at(nums, 0, default: 1))  // up
        case "B":
            pendingWrap = false
            cursorRow = clampRow(cursorRow + Self.at(nums, 0, default: 1))  // down
        case "C":
            pendingWrap = false
            cursorCol = clampCol(cursorCol + Self.at(nums, 0, default: 1))  // forward
        case "D":
            pendingWrap = false
            cursorCol = max(0, cursorCol - Self.at(nums, 0, default: 1))  // back
        case "E":  // CNL — cursor next line
            pendingWrap = false
            cursorRow = clampRow(cursorRow + Self.at(nums, 0, default: 1))
            cursorCol = 0
        case "F":  // CPL — cursor previous line
            pendingWrap = false
            cursorRow = max(0, cursorRow - Self.at(nums, 0, default: 1))
            cursorCol = 0
        case "G":
            pendingWrap = false
            cursorCol = clampCol(Self.at(nums, 0, default: 1) - 1)  // CHA — absolute column
        case "d":
            pendingWrap = false
            cursorRow = clampRow(Self.at(nums, 0, default: 1) - 1)  // VPA — absolute row
        case "J":
            pendingWrap = false
            eraseDisplay(Self.at(nums, 0, default: 0))  // ED
        case "K":
            pendingWrap = false
            eraseLine(Self.at(nums, 0, default: 0))  // EL
        case "r":
            pendingWrap = false
            setScrollRegion(nums)  // DECSTBM
        case "S":
            pendingWrap = false
            scrollRegionUp(Self.at(nums, 0, default: 1))  // SU
        case "T":
            pendingWrap = false
            scrollRegionDown(Self.at(nums, 0, default: 1))  // SD
        case "L":
            pendingWrap = false
            insertLines(Self.at(nums, 0, default: 1))  // IL
        case "M":
            pendingWrap = false
            deleteLines(Self.at(nums, 0, default: 1))  // DL
        case "@":
            pendingWrap = false
            insertChars(Self.at(nums, 0, default: 1))  // ICH
        case "P":
            pendingWrap = false
            deleteChars(Self.at(nums, 0, default: 1))  // DCH
        case "X":
            pendingWrap = false
            eraseChars(Self.at(nums, 0, default: 1))  // ECH
        case "s": saveCursor()  // SCP
        case "u": restoreCursor()  // RCP
        default:
            break  // remaining CSI sequences have no effect on a static capture
        }
    }

    private mutating func applyPrivateMode(_ params: String, _ finalByte: Unicode.Scalar) {
        let modes = Self.parseParams(params)
        let setting = finalByte == "h"
        for mode in modes where mode == 1049 || mode == 47 || mode == 1047 {
            pendingWrap = false
            if setting { enterAltScreen() } else { leaveAltScreen() }
        }
    }

    // MARK: - Drawing

    private mutating func putChar(_ scalar: Unicode.Scalar) {
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
    private mutating func appendCombining(_ scalar: Unicode.Scalar) -> Bool {
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
    private mutating func writeCell(_ cell: TerminalCell, at col: Int) {
        padRow(cursorRow, to: col)
        clearWideOverlap(row: cursorRow, col: col)
        rows[cursorRow][col] = cell
    }

    /// Blanks the orphaned partner of a wide character straddling (`row`, `col`): if the
    /// target is a continuation, blank its head to the left; if it is a wide head, blank
    /// the continuation to its right.
    private mutating func clearWideOverlap(row: Int, col: Int) {
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
    private func cellDisplayWidth(_ cell: TerminalCell) -> Int {
        guard case .grapheme(let grapheme) = cell.content,
            let scalar = grapheme.unicodeScalars.first
        else { return 0 }
        return CharacterWidth.displayWidth(scalar)
    }

    /// Blanks both cells of a wide character touched by `col`. Unlike `clearWideOverlap`,
    /// this also blanks the target cell because edit/erase operations may shift it instead
    /// of immediately overwriting it.
    private mutating func blankWideCluster(row: Int, col: Int) {
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
    private mutating func repairWideClusters(row: Int) {
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
    private mutating func indexDown() {
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
    private mutating func lineFeed() {
        pendingWrap = false
        indexDown()
        cursorCol = 0
    }

    private mutating func tab() {
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
    private mutating func setScrollRegion(_ nums: [Int]) {
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
    private mutating func scrollRegionUp(_ count: Int) {
        let n = min(max(1, count), scrollBottom - scrollTop + 1)
        rows.removeSubrange(scrollTop..<(scrollTop + n))
        rows.insert(contentsOf: blankRows(n), at: scrollBottom - n + 1)
    }

    /// Scrolls `[scrollTop, scrollBottom]` down by `count`: bottom lines fall off, blanks
    /// come in at the top of the region (used by RI and SD).
    private mutating func scrollRegionDown(_ count: Int) {
        let n = min(max(1, count), scrollBottom - scrollTop + 1)
        rows.removeSubrange((scrollBottom - n + 1)..<(scrollBottom + 1))
        rows.insert(contentsOf: blankRows(n), at: scrollTop)
    }

    /// Inserts `count` blank lines at the cursor, pushing lines below it down within the
    /// region (lines past the bottom fall off). Editors use this to open a line.
    private mutating func insertLines(_ count: Int) {
        guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
        let n = min(max(1, count), scrollBottom - cursorRow + 1)
        rows.removeSubrange((scrollBottom - n + 1)..<(scrollBottom + 1))
        rows.insert(contentsOf: blankRows(n), at: cursorRow)
    }

    /// Deletes `count` lines at the cursor, pulling lines below it up within the region
    /// (blanks come in at the bottom). Editors use this to close a line.
    private mutating func deleteLines(_ count: Int) {
        guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
        let n = min(max(1, count), scrollBottom - cursorRow + 1)
        rows.removeSubrange(cursorRow..<(cursorRow + n))
        rows.insert(contentsOf: blankRows(n), at: scrollBottom - n + 1)
    }

    private func blankRows(_ count: Int) -> [[TerminalCell]] {
        Array(repeating: [], count: count)
    }

    // MARK: - Character insert / delete (within the cursor row)

    /// Inserts `count` blank cells at the cursor, shifting the rest of the row right; cells
    /// pushed past the right margin fall off. The `ICH` a line editor uses to open space
    /// mid-line (e.g. shell autosuggestion, `readline` insert mode).
    private mutating func insertChars(_ count: Int) {
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
    private mutating func deleteChars(_ count: Int) {
        guard rows.indices.contains(cursorRow), cursorCol < rows[cursorRow].count else { return }
        let n = min(max(1, count), rows[cursorRow].count - cursorCol)
        for col in cursorCol..<(cursorCol + n) { blankWideCluster(row: cursorRow, col: col) }
        rows[cursorRow].removeSubrange(cursorCol..<(cursorCol + n))
        rows[cursorRow].append(contentsOf: Array(repeating: .blank, count: n))
        repairWideClusters(row: cursorRow)
    }

    /// Blanks `count` cells from the cursor in place, leaving the rest of the row where it
    /// is. `ECH` — like erase-to-end-of-line (`EL`) from the cursor, but bounded to a count.
    private mutating func eraseChars(_ count: Int) {
        guard rows.indices.contains(cursorRow) else { return }
        padRow(cursorRow, to: cursorCol)
        let end = min(cursorCol + max(1, count), rows[cursorRow].count)
        guard cursorCol < end else { return }
        for col in cursorCol..<end { blankWideCluster(row: cursorRow, col: col) }
        for col in cursorCol..<end { rows[cursorRow][col] = .blank }
        repairWideClusters(row: cursorRow)
    }

    // MARK: - Erase

    private mutating func eraseDisplay(_ mode: Int) {
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
    private func isPopulated(_ frame: [[TerminalCell]]) -> Bool {
        frame.contains { row in row.contains { !$0.isBlank } }
    }

    private mutating func eraseLine(_ mode: Int) {
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
        let start = max(0, start)
        guard start < rows[row].count else { return }
        for col in start..<rows[row].count { blankWideCluster(row: row, col: col) }
        for col in start..<rows[row].count { rows[row][col] = .blank }
        repairWideClusters(row: row)
    }

    /// Blanks a row from its start through `end` (inclusive).
    private mutating func blank(row: Int, through end: Int) {
        guard rows.indices.contains(row) else { return }
        let end = min(end, rows[row].count - 1)
        guard end >= 0 else { return }
        for col in 0...end { blankWideCluster(row: row, col: col) }
        for col in 0...end { rows[row][col] = .blank }
        repairWideClusters(row: row)
    }

    // MARK: - Cursor save / restore

    private mutating func saveCursor() { saved = (cursorRow, cursorCol, pendingWrap, style) }

    private mutating func restoreCursor() {
        guard let saved else { return }
        cursorRow = clampRow(saved.row)
        cursorCol = clampCol(saved.col)
        pendingWrap = saved.pendingWrap
        style = saved.style
    }

    // MARK: - Alternate screen

    private mutating func enterAltScreen() {
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

    private mutating func leaveAltScreen() {
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

    private func clampRow(_ row: Int) -> Int { min(max(0, row), screenRows - 1) }
    private func clampCol(_ col: Int) -> Int { min(max(0, col), columns - 1) }

    /// Grows `rows[row]` so column `col` exists, padding with blank cells.
    private mutating func padRow(_ row: Int, to col: Int) {
        guard rows.indices.contains(row) else { return }
        while rows[row].count <= col { rows[row].append(.blank) }
    }

    // MARK: - Output

    /// The screen to report: the captured alternate-screen frame when a TUI ran and
    /// exited, the live buffer when still on the alt screen at end of input, otherwise the
    /// primary buffer.
    private var finalFrame: [[TerminalCell]] {
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
