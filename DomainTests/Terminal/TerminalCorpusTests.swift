import Testing

@testable import VitrineDomain

/// Complete VT commands, never arbitrary byte chunks: `feed` consumes a capture,
/// not an incremental transport whose escape sequences may span calls.
@Suite("Bounded terminal corpus")
struct TerminalCorpusTests {
    @Test(arguments: [UInt64(1), 42, 0xC0FFEE, .max], [1, 2, 7, 32])
    func seededCommandsPreserveGridAndReplayInvariants(seed: UInt64, columns: Int) throws {
        var generator = Generator(state: seed)
        var screen = TerminalScreen(columns: columns, rows: 5)
        var transcript = ""
        for step in 0..<128 {
            let command = generator.command(columns: columns)
            transcript += command
            screen.feed(command)
            let context = "seed=\(seed), columns=\(columns), step=\(step)"
            try check(screen, context: context)

            // An independent replay from a fresh screen catches state accidentally
            // reset between complete commands (pen, cursor, margins, alternate screen).
            var replay = TerminalScreen(columns: columns, rows: 5)
            replay.feed(transcript)
            #expect(screen.rows == replay.rows, Comment(rawValue: context))
            #expect(screen.finalFrame == replay.finalFrame, Comment(rawValue: context))
            #expect(screen.cursorRow == replay.cursorRow, Comment(rawValue: context))
            #expect(screen.cursorCol == replay.cursorCol, Comment(rawValue: context))
            #expect(screen.pendingWrap == replay.pendingWrap, Comment(rawValue: context))
            #expect(screen.style == replay.style, Comment(rawValue: context))
        }
    }

    @Test func scrollingAndWideGlyphsHaveReviewedExpectedFrames() {
        var screen = TerminalScreen(columns: 5, rows: 3)
        screen.feed("one\r\ntwo\r\nthree\r\nfour")
        #expect(screen.plainText() == "two\nthree\nfour")
        var wide = TerminalScreen(columns: 4, rows: 3)
        wide.feed("界abX")
        #expect(wide.plainText() == "界ab\nX")
        wide.feed("\u{1B}[1;2HZ")
        #expect(wide.plainText() == " Zab\nX")
    }

    private func check(_ screen: TerminalScreen, context: String) throws {
        #expect(screen.rows.count == screen.screenRows, Comment(rawValue: context))
        #expect((0..<screen.screenRows).contains(screen.cursorRow), Comment(rawValue: context))
        #expect((0..<screen.columns).contains(screen.cursorCol), Comment(rawValue: context))
        #expect((0..<screen.screenRows).contains(screen.scrollTop), Comment(rawValue: context))
        #expect(
            (screen.scrollTop..<screen.screenRows).contains(screen.scrollBottom),
            Comment(rawValue: context))
        for frame in [screen.rows, screen.finalFrame] {
            #expect(frame.count == screen.screenRows, Comment(rawValue: context))
            for row in frame {
                #expect(row.count <= screen.columns, Comment(rawValue: context))
                for (column, cell) in row.enumerated() {
                    switch cell.content {
                    case .continuation:
                        try #require(column > 0, Comment(rawValue: context))
                        #expect(
                            screen.cellDisplayWidth(row[column - 1]) == 2,
                            Comment(rawValue: context))
                    case .grapheme:
                        if screen.columns > 1, screen.cellDisplayWidth(cell) == 2 {
                            try #require(column + 1 < row.count, Comment(rawValue: context))
                            #expect(
                                row[column + 1].content == .continuation, Comment(rawValue: context)
                            )
                        }
                    }
                }
            }
        }
    }

    /// Fixed arithmetic, no system randomness or time seed. Failed arguments and
    /// step numbers reproduce exactly, including on the sanitizer lane.
    private struct Generator {
        var state: UInt64

        mutating func next(_ upperBound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 32) % UInt64(upperBound))
        }

        mutating func command(columns: Int) -> String {
            let esc = "\u{1B}"
            switch next(16) {
            case 0: return ["ab", "界", "🙂", "e\u{301}"][next(4)]
            case 1: return "\(esc)[\(next(8) + 1);\(next(columns + 3) + 1)H"
            case 2: return "\r"
            case 3: return "\n"
            case 4: return "\t"
            case 5: return "\u{8}"
            case 6: return "\(esc)[\(next(3))K"
            case 7: return "\(esc)[\(next(3))J"
            case 8: return "\(esc)[\(next(5) + 1)\(["S", "T", "L", "M"][next(4)])"
            case 9: return "\(esc)[\(next(5) + 1)\(["@", "P", "X"][next(3)])"
            case 10: return "\(esc)[\(next(4) + 1)\(["A", "B", "C", "D"][next(4)])"
            case 11: return "\(esc)[2;4r"
            case 12: return "\(esc)\(next(2) == 0 ? "7" : "8")"
            case 13: return "\(esc)[?1049\(next(2) == 0 ? "h" : "l")"
            case 14: return "\(esc)[\(next(2) == 0 ? "31" : "0")m"
            default: return "\(esc)]8;;https://example.invalid/corpus\u{7}x\(esc)]8;;\u{7}"
            }
        }
    }
}
