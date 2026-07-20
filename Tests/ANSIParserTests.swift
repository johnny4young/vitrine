import Testing

@testable import Vitrine

/// The ANSI terminal-output parser (Terminal/ANSI renderer): SGR styling, extended
/// colors, and the stripping of every non-styling control sequence.
@Suite("ANSI parser")
struct ANSIParserTests {
    private let esc = "\u{1B}"

    @Test func detectsTheEscapeByte() {
        #expect(ANSIParser.containsANSI("\(esc)[31mhi\(esc)[0m"))
        #expect(!ANSIParser.containsANSI("just plain text"))
        #expect(!ANSIParser.containsANSI("let x = 1  // [31m is not an escape"))
    }

    @Test func plainTextIsOneDefaultRun() {
        let runs = ANSIParser.parse("hello world")
        #expect(runs == [ANSIRun(text: "hello world", style: ANSIStyle())])
    }

    @Test func basicForegroundColor() {
        let runs = ANSIParser.parse("\(esc)[31mred\(esc)[0m")
        #expect(runs.count == 1)
        #expect(runs[0].text == "red")
        #expect(runs[0].style.foreground == .indexed(1))
    }

    @Test func resetReturnsToDefaultStyle() {
        let runs = ANSIParser.parse("\(esc)[31;1mred\(esc)[0mplain")
        #expect(runs.count == 2)
        #expect(runs[0].style.foreground == .indexed(1))
        #expect(runs[0].style.bold)
        #expect(runs[1].style == ANSIStyle())
        #expect(runs[1].text == "plain")
    }

    @Test func attributesAndTheirResets() {
        let runs = ANSIParser.parse("\(esc)[1;2;3;4;7;9mx\(esc)[22;23;24;27;29my")
        #expect(runs[0].style.bold && runs[0].style.dim && runs[0].style.italic)
        #expect(runs[0].style.underline && runs[0].style.inverse && runs[0].style.strikethrough)
        // 22 clears bold+dim, 23 italic, 24 underline, 27 inverse, 29 strikethrough.
        #expect(!runs[1].style.bold && !runs[1].style.dim && !runs[1].style.italic)
        #expect(!runs[1].style.underline && !runs[1].style.inverse && !runs[1].style.strikethrough)
    }

    @Test func brightForegroundAndBackground() {
        let runs = ANSIParser.parse("\(esc)[92;101mx")
        #expect(runs[0].style.foreground == .indexed(10))  // 92 → bright green (8 + 2)
        #expect(runs[0].style.background == .indexed(9))  // 101 → bright red bg (8 + 1)
    }

    @Test func defaultForegroundCode39() {
        let runs = ANSIParser.parse("\(esc)[31ma\(esc)[39mb")
        #expect(runs[0].style.foreground == .indexed(1))
        #expect(runs[1].style.foreground == .default)
    }

    @Test func indexed256Color() {
        let runs = ANSIParser.parse("\(esc)[38;5;208mx")
        #expect(runs[0].style.foreground == .indexed(208))
    }

    @Test func truecolor() {
        let runs = ANSIParser.parse("\(esc)[38;2;10;20;30;48;2;1;2;3mx")
        #expect(runs[0].style.foreground == .rgb(10, 20, 30))
        #expect(runs[0].style.background == .rgb(1, 2, 3))
    }

    @Test func emptyParamsAreAReset() {
        let runs = ANSIParser.parse("\(esc)[31ma\(esc)[mb")
        #expect(runs[0].style.foreground == .indexed(1))
        #expect(runs[1].style == ANSIStyle())
    }

    @Test func stripsNonSGRControlSequences() {
        // Cursor home + clear screen + cursor move — no text effect, removed entirely.
        let runs = ANSIParser.parse("\(esc)[2J\(esc)[1;1Hclean\(esc)[K")
        #expect(runs == [ANSIRun(text: "clean", style: ANSIStyle())])
    }

    @Test func stripsOSCWindowTitle() {
        let runs = ANSIParser.parse("\(esc)]0;my title\u{07}body")
        #expect(runs == [ANSIRun(text: "body", style: ANSIStyle())])
        // ST-terminated form too.
        let runs2 = ANSIParser.parse("\(esc)]0;t\(esc)\\body")
        #expect(runs2 == [ANSIRun(text: "body", style: ANSIStyle())])
    }

    @Test func charsetDesignationLeavesNoStrayByte() {
        // `tput sgr0` emits `ESC (B` before its SGR reset; the designation's final
        // byte must be consumed with the sequence, not leak into the text.
        let runs = ANSIParser.parse("\(esc)(Bplain")
        #expect(runs == [ANSIRun(text: "plain", style: ANSIStyle())])
    }

    @Test func colonSeparatedSGRParametersAreIgnoredNotAReset() {
        // The ITU colon form (`38:5:196`) is not interpreted yet, but it must never
        // be misread as SGR 0 — that would wipe accumulated attributes.
        let runs = ANSIParser.parse("\(esc)[1mbold\(esc)[38:5:196mstill")
        #expect(runs.count == 2)
        #expect(runs[1].style.bold, "an uninterpreted colon parameter must not reset bold")
    }

    @Test func c0ControlInsideCSIAbortsTheSequence() {
        // A C0 control inside a CSI body means the sequence was truncated or
        // interleaved; the control byte must survive (a terminal executes it), not
        // be swallowed into the parameter string.
        let runs = ANSIParser.parse("A\(esc)[31\nmB")
        #expect(runs.map(\.text).joined() == "A\nmB")
    }

    @Test func toleratesTruncatedEscapeAtEnd() {
        #expect(ANSIParser.parse("ok\(esc)[31") == [ANSIRun(text: "ok", style: ANSIStyle())])
        #expect(ANSIParser.parse("ok\(esc)") == [ANSIRun(text: "ok", style: ANSIStyle())])
    }

    @Test func textConcatenatesToInputWithoutEscapes() {
        let input = "\(esc)[32m$ git status\(esc)[0m\n\(esc)[31mmodified:\(esc)[0m file.swift\n"
        let stripped = ANSIParser.parse(input).map(\.text).joined()
        #expect(stripped == "$ git status\nmodified: file.swift\n")
    }

    @Test func multipleParamsInOneSGR() {
        let runs = ANSIParser.parse("\(esc)[1;4;33mx")
        #expect(runs[0].style.bold && runs[0].style.underline)
        #expect(runs[0].style.foreground == .indexed(3))
    }

    @Test func parsesOSC8Hyperlink() {
        // Open (`8;;URI`) … linked text … close (`8;;` empty URI).
        let runs = ANSIParser.parse(
            "\(esc)]8;;https://example.com\u{07}link\(esc)]8;;\u{07} after")
        #expect(runs.count == 2)
        #expect(runs[0].text == "link")
        #expect(runs[0].style.hyperlink == "https://example.com")
        #expect(runs[1].text == " after")
        #expect(runs[1].style.hyperlink == nil)
    }

    @Test func hyperlinkAcceptsTheSTTerminator() {
        let runs = ANSIParser.parse("\(esc)]8;;https://x\(esc)\\link\(esc)]8;;\(esc)\\")
        #expect(runs[0].text == "link")
        #expect(runs[0].style.hyperlink == "https://x")
    }

    @Test func hyperlinkSurvivesSGRReset() {
        // OSC 8 is independent of SGR: a color + full reset inside the link must not
        // drop it — only the closing OSC 8 does.
        let runs = ANSIParser.parse(
            "\(esc)]8;;https://x\u{07}\(esc)[31mred\(esc)[0mplain\(esc)]8;;\u{07}")
        #expect(runs.map(\.text).joined() == "redplain")
        #expect(runs.allSatisfy { $0.style.hyperlink == "https://x" })
    }

    @Test func hyperlinkURIKeepsParamsAndQuerySemicolons() {
        // The `id=…` params field is skipped; a URI carrying its own `;` survives.
        let runs = ANSIParser.parse(
            "\(esc)]8;id=42;https://e.com/a?x=1;y=2\u{07}t\(esc)]8;;\u{07}")
        #expect(runs[0].style.hyperlink == "https://e.com/a?x=1;y=2")
    }

    @Test func nonHyperlinkOSCLeavesNoLink() {
        // A window-title OSC (`0;…`) is still stripped and sets no hyperlink.
        let runs = ANSIParser.parse("\(esc)]0;my title\u{07}body")
        #expect(runs == [ANSIRun(text: "body", style: ANSIStyle())])
    }

    @Test func malformedOSC8DoesNotClearAnOpenLink() {
        // A truncated `8` body (no `;params;URI`) is not a valid OSC 8: it must neither
        // clear an open link nor split the run. Here a bogus `ESC]8 BEL` sits between two
        // linked spans — both stay linked and merge into one run.
        let runs = ANSIParser.parse(
            "\(esc)]8;;https://x\u{07}a\(esc)]8\u{07}b\(esc)]8;;\u{07}")
        #expect(runs.map(\.text).joined() == "ab")
        #expect(runs.allSatisfy { $0.style.hyperlink == "https://x" })
    }
}
