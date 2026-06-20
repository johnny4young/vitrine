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
}
