import Foundation

extension TerminalScreen {
    // MARK: - Feeding the stream

    /// Replays the bytes of `text`, mutating the screen. Reuses ``ANSIParser``'s CSI/OSC
    /// scanners so there is a single parser of the escape-sequence wire format.
    public mutating func feed(_ text: String) {
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
                    // DCS/SOS/PM/APC string bodies are command data, never cells: skip
                    // to their terminator with the shared scanner so a sixel or kitty
                    // graphics payload is not typed into the screen.
                    if ANSIParser.isStringSequenceIntroducer(scalars[index + 1]) {
                        index = ANSIParser.skipStringSequence(scalars, from: index + 2)
                        continue
                    }
                    // ESC followed by an intermediate byte (0x20–0x2F) is a longer
                    // sequence — most often charset designation (`ESC (B`, which htop and
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

    mutating func applyCSI(_ params: String, _ finalByte: Unicode.Scalar) {
        // DEC private modes (`ESC[?…h` / `…l`) — the only one acted on is the alternate
        // screen; the rest (cursor visibility, mouse, bracketed paste) are visual no-ops
        // for a static capture.
        if params.hasPrefix("?") {
            applyPrivateMode(String(params.dropFirst()), finalByte)
            return
        }
        // Other private-use markers (`<`, `=`, `>`) are vendor sequences sharing final
        // bytes with the standard controls: executed as standard, xterm's `>4;1m`
        // ghost-styles the pen and a private cursor final walks the cursor. Nothing a
        // static capture can honor — drop them wholesale.
        if ANSIParser.hasPrivateParameterPrefix(params) { return }
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

    mutating func applyPrivateMode(_ params: String, _ finalByte: Unicode.Scalar) {
        let modes = Self.parseParams(params)
        let setting = finalByte == "h"
        for mode in modes where mode == 1049 || mode == 47 || mode == 1047 {
            pendingWrap = false
            if setting { enterAltScreen() } else { leaveAltScreen() }
        }
    }

}
