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
