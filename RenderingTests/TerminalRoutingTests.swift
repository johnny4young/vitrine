import Testing
import VitrineDomain

@testable import VitrineRendering

/// Integration routing from ANSI capture mode into the shared rendering adapter.
@Suite("Terminal renderer routing")
struct TerminalRoutingTests {
    private let esc = "\u{1B}"

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
        // `--terminal-width` flows through ANSIRenderer to the grid emulator. Absolute
        // positioning puts the stream in grid mode (a lone ED no longer does — that is
        // the `clear` idiom); a 10-char line then wraps at the pinned width, where the
        // inferred width (floored at 80) would keep it on one line.
        let tui = "\(esc)[2;1HABCDEFGHIJ"
        #expect(ANSIRenderer.plainText(tui) == "\nABCDEFGHIJ")  // inferred ≥ 80: no wrap
        #expect(ANSIRenderer.plainText(tui, columns: 4) == "\nABCD\nEFGH\nIJ")  // pinned to 4
    }

    // MARK: - `clear` routes to line mode; repaint loops route to the grid

    /// One display erase is `clear && <command>`: scrolling output whose transcript is
    /// the artifact. Routed to the grid, a long capture collapsed to the last screenful
    /// (reproduced: 1,500 lines → 38). Line mode instead resets the transcript at the
    /// erase and keeps everything after it.
    @Test func aLoneClearStaysInLineModeAndResetsTheTranscript() {
        let macOSClear = "\(esc)[H\(esc)[2J"
        let capture =
            "old prompt\n\(macOSClear)" + (1...100).map(String.init).joined(separator: "\n")

        #expect(!TerminalScreen.usesScreenAddressing(capture))
        let text = ANSIRenderer.plainText(capture)
        #expect(text.hasPrefix("1\n"))
        #expect(text.hasSuffix("\n100"))
        #expect(!text.contains("old prompt"))
    }

    @Test func linuxClearWithScrollbackEraseIsStillOneClear() {
        // Linux `clear` appends ED-3 (erase scrollback) to ED-2. Two J sequences, one
        // clear — ED-3 never means repaint, so it must not count toward the grid.
        let linuxClear = "\(esc)[H\(esc)[2J\(esc)[3J"
        #expect(!TerminalScreen.usesScreenAddressing("\(linuxClear)hello\nworld"))
        #expect(ANSIRenderer.plainText("before\n\(linuxClear)hello") == "hello")
    }

    @Test func repeatedDisplayErasesSelectTheGrid() {
        // Two or more full erases are a repaint loop (`watch`, multi-line progress):
        // the final frame is the artifact, so the grid takes over. Real repaints home
        // the cursor before erasing, exactly as `watch` emits.
        let watchStyle = "\(esc)[H\(esc)[2Jframe one\(esc)[H\(esc)[2Jframe two"
        #expect(TerminalScreen.usesScreenAddressing(watchStyle))
        #expect(ANSIRenderer.plainText(watchStyle) == "frame two")
    }

    @Test func partialDisplayErasesNeverSelectTheGridOrResetTheTranscript() {
        // ED 0 (the default, erase forward) and ED 1 (erase backward) are *partial*
        // erases that ordinary scrolling output emits routinely. Counting them toward
        // the repaint threshold would let two of them collapse a transcript to a
        // screenful, and treating either as a transcript reset would delete lines the
        // user saw.
        let partials = "line one\n\(esc)[Jline two\n\(esc)[0Jline three\n\(esc)[1Jline four"
        #expect(!TerminalScreen.usesScreenAddressing(partials))
        let text = ANSIRenderer.plainText(partials)
        for line in ["line one", "line two", "line three", "line four"] {
            #expect(text.contains(line))
        }
    }

    @Test func aStandaloneScrollbackEraseKeepsTheVisibleTranscript() {
        // ED 3 erases *saved scrollback*, never the visible screen. A program that
        // emits it on its own must not lose the lines already printed.
        let capture = "kept before\n\(esc)[3Jkept after"
        #expect(!TerminalScreen.usesScreenAddressing(capture))
        #expect(ANSIRenderer.plainText(capture) == "kept before\nkept after")
    }

    @Test func aClearBesideRealAddressingStillSelectsTheGrid() {
        // The single-ED allowance never weakens the unambiguous triggers: one clear
        // plus absolute positioning (or the alternate screen) is a TUI.
        #expect(TerminalScreen.usesScreenAddressing("\(esc)[2J\(esc)[5;3Hx"))
        #expect(TerminalScreen.usesScreenAddressing("\(esc)[?1049h\(esc)[2Jx\(esc)[?1049l"))
    }

}
