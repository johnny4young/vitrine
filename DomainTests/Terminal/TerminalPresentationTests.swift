import Testing

@testable import VitrineDomain

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
        #expect(context.canHideArguments == false)
    }

    @Test func removingEveryChipClearsTheFields() {
        var context = TerminalHeaderContext(filename: "project · branch", title: "$ htop")
        context.labels.remove(at: 1)
        #expect(context.filename == "project")
        context.labels.remove(at: 0)
        context.command = nil
        #expect(context.filename == nil)
        #expect(context.title == nil)
    }

    @Test func changingThePromptKeepsTheCommand() {
        var context = TerminalHeaderContext(filename: nil, title: "$ htop")
        context.prompt = .chevron
        #expect(context.title == "› htop")
        context.prompt = .none
        #expect(context.title == "htop")
    }

    @Test(arguments: [
        ("$ git commit -m 'token abc'", "$ git"),
        ("$ TOKEN=abc123 npm test --ci", "$ npm"),
        ("$ /Users/someone/bin/tool --flag", "$ tool"),
        ("$ 'my-tool' secret", "$ my-tool"),
        ("› ./run.sh arg", "› run.sh"),
        ("deploy prod", "deploy"),
    ])
    func hidingArgumentsKeepsOnlyTheCommandsName(_ title: String, _ expected: String) {
        var context = TerminalHeaderContext(filename: nil, title: title)
        #expect(context.canHideArguments)
        context.hideArguments()
        #expect(context.title == expected)
        #expect(context.canHideArguments == false)
    }

    @Test func aCommandOfOnlyAssignmentsHasNothingLeftToShow() {
        var context = TerminalHeaderContext(filename: nil, title: "$ TOKEN=abc123")
        context.hideArguments()
        #expect(context.title == nil)
    }

    @Test func aBareCommandHasNoArgumentsToHide() {
        #expect(TerminalHeaderContext(filename: nil, title: "$ htop").canHideArguments == false)
    }
}
