import Foundation

extension TerminalScreen {
    // MARK: - Convenience

    /// Replays `text` at an inferred width and height and returns the final screen as
    /// styled runs, ready for ``ANSIRenderer``.
    public static func runs(_ text: String, columns: Int? = nil) -> [ANSIRun] {
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
    /// `\r`/`EL`/`CHA` — so none of them trip this and they stay in line mode. `EL` (erase
    /// *line*) and `CHA` (cursor to a column) are deliberately not triggers: they are the
    /// progress-bar idiom, which line mode collapses itself in `ANSIRenderer.normalize`
    /// alongside `\r`.
    public static func usesScreenAddressing(_ text: String) -> Bool {
        guard ANSIParser.containsANSI(text) else { return false }
        let scalars = Array(text.unicodeScalars)
        var index = 0
        var erasedDisplayOnce = false
        while index < scalars.count {
            guard scalars[index] == "\u{1B}", index + 1 < scalars.count else {
                index += 1
                continue
            }
            guard scalars[index + 1] == "[" else {  // only CSI carries these
                // A DCS/SOS/PM/APC body is command data, and tmux passthrough carries
                // *escaped escape sequences* inside one — so scanning through a body
                // byte by byte would let a payload's CSI-shaped bytes decide the route.
                if ANSIParser.isStringSequenceIntroducer(scalars[index + 1]) {
                    index = ANSIParser.skipStringSequence(scalars, from: index + 2)
                    continue
                }
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
            // Vendor sequences (`<`/`=`/`>` markers) share final bytes with the
            // standard controls but are not screen addressing — counting them here
            // would misroute a stream over a stray `ESC[>…J`-shaped query.
            if ANSIParser.hasPrivateParameterPrefix(params) { continue }
            switch finalByte {
            case "J":
                // ED 2 alone is ambiguous. A TUI repaints with it — but `clear` emits
                // exactly one (macOS `\e[H\e[2J`; Linux appends `\e[3J`, the scrollback
                // erase), and `clear && <command>` is scrolling output whose transcript is
                // the artifact: routed to the grid, a 1,500-line capture collapses to the
                // last screenful. So one whole-display erase is the clear idiom and stays
                // in line mode (which resets the transcript at the erase — see
                // `ANSIRenderer.lineEdit`); a second one means a repaint loop (`watch`,
                // multi-line progress redraws) and selects the grid.
                //
                // Only parameter 2 counts. ED 0 (the default, erase forward) and ED 1
                // (erase backward) are *partial* erases that scrolling output emits
                // routinely, so counting them would let two partial erases collapse a
                // transcript; ED 3 erases saved scrollback, never the visible screen.
                if params == "2" {
                    if erasedDisplayOnce { return true }
                    erasedDisplayOnce = true
                }
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
    public static func inferColumns(_ text: String) -> Int {
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
                    if let finalByte, !params.hasPrefix("?"),
                        !ANSIParser.hasPrivateParameterPrefix(params)
                    {
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
                    // Skip a string-sequence body outright. Dropping only the introducer
                    // left the payload — a sixel frame, a kitty graphics blob — counting
                    // as visible text, so a 400-byte body inflated the inferred width to
                    // its 1,000-column ceiling and rewrapped the real cells.
                    if ANSIParser.isStringSequenceIntroducer(scalars[index + 1]) {
                        index = ANSIParser.skipStringSequence(scalars, from: index + 2)
                        continue
                    }
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
    public static func inferRows(_ text: String) -> Int {
        let scalars = Array(text.unicodeScalars)
        var maxRow = 0
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\u{1B}", index + 1 < scalars.count, scalars[index + 1] == "[" {
                let (params, finalByte, end) = ANSIParser.scanCSI(scalars, from: index + 2)
                if let finalByte, !params.hasPrefix("?"),
                    !ANSIParser.hasPrivateParameterPrefix(params)
                {
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
            // Row inference reads only CSI positioning, so a payload cannot inflate it
            // by length — but a passthrough body carries escaped sequences, and a
            // `CUP` shape inside one would still be counted. Skip the body.
            if scalars[index] == "\u{1B}", index + 1 < scalars.count,
                ANSIParser.isStringSequenceIntroducer(scalars[index + 1])
            {
                index = ANSIParser.skipStringSequence(scalars, from: index + 2)
                continue
            }
            index += 1
        }
        if maxRow == 0 { return 40 }  // relative-only app: a typical screen height
        return min(max(maxRow, 24), 300)
    }
}
