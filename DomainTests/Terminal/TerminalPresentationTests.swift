import Testing

@testable import VitrineDomain

@Suite("Terminal cursor")
struct TerminalCursorTests {
    private func runs(_ text: String, _ cursor: TerminalCursorStyle) -> [ANSIRun] {
        TerminalScreen.runs(text, columns: 20, cursor: cursor)
    }

    private func inverted(_ runs: [ANSIRun]) -> String {
        runs.filter(\.style.inverse).map(\.text).joined()
    }

    private func text(_ runs: [ANSIRun]) -> String { runs.map(\.text).joined() }

    @Test func hiddenDrawsNothing() {
        let stream = "one\u{1B}[3;2Htwo\u{1B}[1;1H"
        #expect(runs(stream, .hidden) == TerminalScreen.runs(stream, columns: 20))
        #expect(inverted(runs(stream, .hidden)).isEmpty)
    }

    @Test func blockInvertsTheCellUnderTheCursor() {
        let result = runs("abc\u{1B}[1;2H", .block)
        #expect(text(result) == "abc")
        #expect(inverted(result) == "b")
    }

    @Test func blockUndoesAnAlreadyInverseCell() {
        let result = runs("\u{1B}[7mabc\u{1B}[0m\u{1B}[1;2H", .block)
        #expect(inverted(result) == "ac")
    }

    @Test func aCursorPastTheTextPadsToItsColumn() {
        let result = runs("ab\u{1B}[1;5H", .block)
        #expect(text(result) == "ab   ")
        #expect(inverted(result) == " ")
    }

    @Test func aCursorBelowTheTextAddsOnlyItsRow() {
        let result = runs("ab\u{1B}[2;1H", .block)
        #expect(text(result) == "ab\n ")
    }

    @Test func aCursorParkedFarBelowTheContentIsNotDrawn() {
        let parked = TerminalScreen.runs("hello\u{1B}[24;1H", cursor: .block)
        #expect(text(parked) == "hello")
        #expect(inverted(parked).isEmpty)
        #expect(text(TerminalScreen.runs("hello\u{1B}[999;999H", cursor: .block)) == "hello")
    }

    @Test func aCursorPastTheStandardWidthIsNotDrawn() {
        // The move itself widens the inferred width, so that can't be the limit.
        let parked = TerminalScreen.runs("hello\u{1B}[1;500H", cursor: .block)
        #expect(text(parked) == "hello")
        #expect(inverted(TerminalScreen.runs("hello\u{1B}[1;80H", cursor: .block)) == " ")
    }

    @Test func aCursorWithinWideContentIsDrawn() {
        let wide = String(repeating: "x", count: 120)
        let result = TerminalScreen.runs("\(wide)\u{1B}[1;100H", cursor: .block)
        #expect(inverted(result) == "x")
    }

    @Test func resetsMakeAHiddenCursorVisibleOnTheGrid() {
        #expect(inverted(runs("abc\u{1B}[?25l\u{1B}c\u{1B}[1;2H", .block)) == "b")
        #expect(inverted(runs("abc\u{1B}[?25l\u{1B}[!p\u{1B}[1;2H", .block)) == "b")
    }

    @Test func barKeepsTheCellItCovers() {
        let result = runs("abc\u{1B}[1;2H", .bar)
        #expect(text(result) == "a\u{258F}bc")
        #expect(result.filter(\.style.isCursorBar).map(\.text) == ["\u{258F}"])
    }

    @Test func barInvertsACellWithItsOwnBackgroundInstead() {
        let colored = runs("\u{1B}[41mabc\u{1B}[0m\u{1B}[1;2H", .bar)
        #expect(text(colored) == "abc")
        #expect(inverted(colored) == "b")
        #expect(inverted(runs("\u{1B}[7mabc\u{1B}[0m\u{1B}[1;2H", .bar)) == "ac")
    }

    @Test func aCursorOnAWideCharactersRightHalfMarksTheCharacter() {
        let result = runs("\u{1B}[1;1H日本\u{1B}[1;2H", .block)
        #expect(inverted(result) == "日")
    }

    @Test func aProgramThatHidItsCursorHasNoneToDraw() {
        #expect(inverted(runs("abc\u{1B}[?25l\u{1B}[1;2H", .block)).isEmpty)
        #expect(inverted(runs("abc\u{1B}[?25l\u{1B}[?25h\u{1B}[1;2H", .block)) == "b")
    }

    @Test func aFrameKeptFromAnExitedFullScreenAppHasNoCursor() {
        let exited = "\u{1B}[?1049h\u{1B}[2J\u{1B}[1;1Hframe\u{1B}[?1049l"
        #expect(inverted(runs(exited, .block)).isEmpty)
        #expect(text(runs(exited, .block)) == "frame")
    }

    @Test func aFullScreenAppStillRunningKeepsItsCursor() {
        let running = "\u{1B}[?1049h\u{1B}[1;1Hframe\u{1B}[1;2H"
        #expect(inverted(runs(running, .block)) == "r")
    }

    @Test func lineModeReadsTheLastVisibilityEscape() {
        #expect(TerminalScreen.leavesCursorHidden("plain") == false)
        #expect(TerminalScreen.leavesCursorHidden("\u{1B}[?25l spin"))
        #expect(TerminalScreen.leavesCursorHidden("\u{1B}[?25l spin \u{1B}[?25h") == false)
        #expect(TerminalScreen.leavesCursorHidden("\u{1B}[?25h \u{1B}[?25l"))
    }

    @Test func lineModeIgnoresPayloadsAndHonorsResets() {
        #expect(TerminalScreen.leavesCursorHidden("\u{1B}]0;\u{1B}[?25l\u{07} x") == false)
        #expect(TerminalScreen.leavesCursorHidden("\u{1B}Ptmux;\u{1B}[?25l\u{1B}\\ x") == false)
        #expect(TerminalScreen.leavesCursorHidden("\u{1B}[?25l \u{1B}c x") == false)
        #expect(TerminalScreen.leavesCursorHidden("\u{1B}[?25l \u{1B}[!p x") == false)
        #expect(TerminalScreen.leavesCursorHidden("\u{1B}c \u{1B}[?25l x"))
    }

    @Test func lineModeReadsACompoundModeAndIgnoresOtherModes() {
        #expect(TerminalScreen.leavesCursorHidden("\u{1B}[?1;25l x"))
        #expect(TerminalScreen.leavesCursorHidden("\u{1B}[?25l \u{1B}[?25;1h") == false)
        #expect(TerminalScreen.leavesCursorHidden("\u{1B}[?2004l x") == false)
        #expect(TerminalScreen.leavesCursorHidden("\u{1B}[25l x") == false)
    }
}

@Suite("Terminal header context")
struct TerminalHeaderContextTests {
    @Test func splitsWhatVgrabWrites() {
        let context = TerminalHeaderContext(
            filename: "weather-app · main", title: "$ git log -n 5")
        #expect(context.labels == ["weather-app", "main"])
        #expect(context.prompt == .dollar)
        #expect(context.command == "git log -n 5")
    }

    @Test(arguments: [
        ("weather-app · main", "$ htop"), ("build.log", "› swift test"), ("a", "Plain title"),
        ("a · b · c", "$x"),
    ])
    func anUneditedContextWritesBackTheSameText(_ filename: String, _ title: String) {
        let context = TerminalHeaderContext(filename: filename, title: title)
        #expect(context.filename == filename)
        #expect(context.title == title)
    }

    @Test func emptyFieldsStayEmpty() {
        let context = TerminalHeaderContext(filename: nil, title: nil)
        #expect(context.labels.isEmpty)
        #expect(context.command == nil)
        #expect(context.filename == nil)
        #expect(context.title == nil)
        #expect(context.canRemoveArguments == false)
    }

    @Test func removingEveryChipClearsTheFields() {
        var context = TerminalHeaderContext(filename: "project · branch", title: "$ htop")
        context.labels.remove(at: 1)
        #expect(context.filename == "project")
        context.labels.remove(at: 0)
        context.removeTitle()
        #expect(context.filename == nil)
        #expect(context.title == nil)
    }

    @Test func changingThePromptKeepsTheText() {
        var context = TerminalHeaderContext(filename: nil, title: "$ htop")
        context.prompt = .chevron
        #expect(context.title == "› htop")
        context.prompt = .none
        #expect(context.title == "htop")
        #expect(context.command == nil)
        context.prompt = .dollar
        #expect(context.command == "htop")
    }

    @Test(arguments: ["Aurora gradient", "user@host:~$ deploy --token abc", "$htop"])
    func aTitleWithoutAPromptGlyphIsNotACommand(_ title: String) {
        var context = TerminalHeaderContext(filename: nil, title: title)
        #expect(context.command == nil)
        #expect(context.canRemoveArguments == false)
        context.removeArguments()
        #expect(context.title == title)
    }

    @Test(arguments: [
        ("$ git commit -m 'token abc'", "$ git"),
        ("$ TOKEN=abc123 npm test --ci", "$ npm"),
        (#"$ API_KEY="abc def" npm test"#, "$ npm"),
        ("$ PASSWORD='correct horse' ./deploy.sh", "$ deploy.sh"),
        (#"$ TOKEN=abc\ def FOO=1 make all"#, "$ make"),
        ("$ /Users/someone/bin/tool --flag", "$ tool"),
        ("$ ~/bin/tool", "$ tool"),
        ("$ 'my-tool' secret", "$ my-tool"),
        ("› ./run.sh arg", "› run.sh"),
        ("$ make; rm -rf build", "$ make"),
        ("$ cat secret.txt | grep key", "$ cat"),
    ])
    func removingArgumentsKeepsOnlyTheCommandsName(_ title: String, _ expected: String) {
        var context = TerminalHeaderContext(filename: nil, title: title)
        #expect(context.canRemoveArguments)
        context.removeArguments()
        #expect(context.title == expected)
        #expect(context.canRemoveArguments == false)
    }

    /// Nothing here is safely a command's name, and each would otherwise leak a part of it.
    @Test(arguments: [
        "$ postgres://me:pw@db",
        "$ https://me:pw@db.example.com/tool --flag",
        "$ user@host:~$ deploy --token abc",
        "$ TOKEN=abc123",
        "$ FOO=1; BAR=2 cmd",
        #"$ "FOO=bar" cmd"#,
        "$ $(cat secret) arg",
        "$ `cat secret` arg",
        #"$ "$(cat secret)" arg"#,
        "$ $TOKEN arg",
        "$ -t abc",
        "$ 'my tool' secret",
        #"$ my\ tool secret"#,
        #"$ API_KEY="abc def npm test"#,
        "$ PASSWORD='unterminated horse",
        #"$ trailing\"#,
        "$ .. arg",
        "$ / arg",
        "$ > out.txt",
    ])
    func aFirstWordThatIsNoCommandNameLeavesNothing(_ title: String) {
        var context = TerminalHeaderContext(filename: nil, title: title)
        context.removeArguments()
        #expect(context.title == nil)
    }

    @Test func aBareCommandHasNoArgumentsToRemove() {
        #expect(TerminalHeaderContext(filename: nil, title: "$ htop").canRemoveArguments == false)
    }
}
