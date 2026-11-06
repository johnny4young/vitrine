import Foundation
import Testing
import VitrineDomain

@testable import VitrineCLICore

@MainActor
@Suite("CLI run command")
struct CLIRunCommandTests: CLITestSupport {
    private let path = ["PATH": "/usr/bin:/bin"]

    private func invocation(_ arguments: [String]) throws -> CLIRunCommand.Invocation {
        try #require(try CLIRunCommand.invocation(for: arguments))
    }

    @Test func splitsOptionsFromTheCommandAndCopiesByDefault() throws {
        let dashed = try invocation(["--terminal-width", "100", "--", "swift", "test", "--quiet"])
        #expect(dashed.command == ["swift", "test", "--quiet"])
        #expect(dashed.options.command == .terminalCapture)
        #expect(dashed.options.language == .terminal)
        #expect(dashed.options.terminalColumns == 100)
        #expect(dashed.options.copyToClipboard)
        #expect(dashed.context)
        #expect(!dashed.titleFromCommand)
        #expect(try invocation(["--title-from-command", "ls"]).titleFromCommand)

        let bare = try invocation(["--no-context", "--edit", "git", "status"])
        #expect(bare.command == ["git", "status"])
        #expect(bare.options.openInEditor && !bare.options.copyToClipboard)
        #expect(!bare.context)

        let redacted = try invocation(["--redact-secrets", "--title", "--copy", "env"])
        #expect(redacted.options.redactSecrets)
        #expect(redacted.options.metadataTitle == "--copy")
        #expect(try CLIRunCommand.invocation(for: ["--help", "ls"]) == nil)
    }

    @Test func refusesOptionsBeforeAnythingRuns() {
        #expect(throws: CLIError.unknownFlag("--out")) {
            try CLIRunCommand.invocation(for: ["--out", "x.png", "--", "ls"])
        }
        #expect(throws: CLIError.unknownFlag("--lines")) {
            try CLIRunCommand.invocation(for: ["--lines", "3-12", "--", "ls"])
        }
        #expect(throws: CLIError.missingRequired("command to run")) {
            try CLIRunCommand.invocation(for: ["--copy", "--"])
        }
        #expect(throws: CLIError.incompatibleOptions("Cannot combine --edit with --copy.")) {
            try CLIRunCommand.invocation(for: ["--edit", "--copy", "ls"])
        }
    }

    @Test func runsTheCommandThenRendersTheCaptureWithItsContext() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var seen: (capture: URL, command: [String], columns: String?)?
        var rendered: CLIOptions?
        var captureText = ""

        let outcome = try CLIRunCommand.perform(
            invocation(["--terminal-width", "80", "--", "ls", "it's here"]), directory: directory,
            environment: path,
            execute: { capture, command, environment in
                try "\u{1B}[32mok\u{1B}[0m\n".write(to: capture, atomically: true, encoding: .utf8)
                seen = (capture, command, environment["COLUMNS"])
                return 3
            },
            render: { options in
                rendered = options
                captureText = try String(contentsOfFile: options.inputPath, encoding: .utf8)
                return "Copied the image to the clipboard"
            })

        #expect(outcome == .init(status: 3, summary: "Copied the image to the clipboard"))
        #expect(seen?.command == ["ls", "it's here"])
        #expect(seen?.columns == "80")
        #expect(captureText.contains("ok"))
        #expect(rendered?.metadataFilename == directory.standardizedFileURL.lastPathComponent)
        #expect(rendered?.metadataTitle == "$ ls …")
        let capture = try #require(seen?.capture)
        #expect(!FileManager.default.fileExists(atPath: capture.path))
    }

    @Test func leavesTheHeaderOutWhenAskedAndKeepsExplicitText() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var headers: [String?] = []
        for arguments in [
            ["--no-context", "ls"], ["--edit", "ls"],
            ["--title", "Tests", "--filename", "app", "ls"],
        ] {
            _ = try CLIRunCommand.perform(
                invocation(arguments), directory: directory, environment: path,
                execute: { _, _, _ in 0 },
                render: { options in
                    headers.append(options.metadataTitle)
                    headers.append(options.metadataFilename)
                    return ""
                })
        }
        #expect(headers == [nil, nil, nil, nil, "Tests", "app"])
    }

    @Test func reportsAMissingCommandWithoutRunningAnything() throws {
        var ran = false
        #expect(throws: CLIError.commandNotFound("no-such-tool")) {
            try CLIRunCommand.perform(
                invocation(["no-such-tool"]), environment: path,
                execute: { _, _, _ in
                    ran = true
                    return 0
                },
                render: { _ in "" })
        }
        #expect(!ran)
        #expect(CLIError.commandNotFound("x").exitCode == 127)
        #expect(!CLIError.commandNotFound("x").isUsageError)
    }

    @Test(arguments: [
        // Options and assignments named like credentials, whatever the value looks like.
        (["mysql", "--password", "hunter2"], "mysql --password ••••"),
        (["mysql", "--password=hunter2"], "mysql --password=••••"),
        (["tool", "-token", "abc"], "tool -token ••••"),
        (["env", "DB_PASS=abc", "npm", "test"], "env DB_PASS=•••• npm test"),
        (["env", "SESSION_ID=1", "x"], "env SESSION_ID=•••• x"),
        (
            ["app", "--client-secret", "s", "--cookie-jar", "j"],
            "app --client-secret •••• --cookie-jar ••••"
        ),
        // Known credential shapes.
        (["mysql", "-phunter2", "db"], "mysql -p•••• db"),
        (["tool", "-password", "hunter2"], "tool -p•••• ••••"),
        (["mysqldump", "-Psecret"], "mysqldump -P••••"),
        (["curl", "-u", "user:pass", "https://example.com"], "curl -u •••• https://example.com"),
        (["curl", "--user", "user:pass"], "curl --user ••••"),
        (["curl", "-uuser:pass"], "curl -u••••"),
        (["curl", "--user=user:pass"], "curl --user=••••"),
        (["mysql", "-p", "hunter2"], "mysql -p ••••"),
        (["tool", "-a", "acct", "-k", "k1"], "tool -a •••• -k ••••"),
        (["tool", "--token", "-abc", "-v"], "tool --token •••• -v"),
        (
            ["git", "clone", "https://me:pw@example.com/r.git"],
            "git clone https://••••@example.com/r.git"
        ),
        (["curl", "-H", "Authorization: Basic dXNlcjpw"], "curl -H 'Authorization: ••••'"),
        (["curl", "-H", "Cookie: id=1"], "curl -H 'Cookie: ••••'"),
        (["curl", "--header", "X-Api-Key: k1"], "curl --header 'X-Api-Key: ••••'"),
        (["curl", "--header=Proxy-Authorization: x"], "curl '--header=Proxy-Authorization: ••••'"),
        (["curl", "-HX-Auth-Token: t"], "curl '-HX-Auth-Token: ••••'"),
        // Plain arguments stay readable.
        (
            ["git", "log", "--author", "alice", "-n", "5", "-H", "Accept: text/html", "a b"],
            "git log --author alice -n 5 -H 'Accept: text/html' 'a b'"
        ),
        (
            ["curl", "-u", "alice", "https://example.com/a?q=1"],
            "curl -u alice 'https://example.com/a?q=1'"
        ),
    ])
    func masksCredentialsInTheHeader(arguments: [String], expected: String) {
        #expect(CLIRunHeader.command(arguments) == expected)
    }

    @Test func theDefaultHeaderNamesOnlyTheProgram() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var titles: [String?] = []
        for arguments in [
            ["--", "/usr/bin/env", "API_KEY=abc", "ls"], ["ls"],
            ["--redact-secrets", "curl", "-u", "me:pw", "-k"],
        ] {
            _ = try CLIRunCommand.perform(
                invocation(arguments), directory: directory, environment: path,
                execute: { _, _, _ in 0 },
                render: { options in
                    titles.append(options.metadataTitle)
                    return ""
                })
        }
        #expect(titles == ["$ env …", "$ ls", "$ curl …"])
        #expect(CLIRunHeader.program([]) == "")
        #expect(CLIRunHeader.program(["my tool", "x"]) == "'my tool' …")
    }

    @Test func theSecretScannerStillRunsOnTop() throws {
        let bearer = "Bearer " + String(repeating: "a", count: 24)
        let key = "OPENAI=" + "sk-" + String(repeating: "k", count: 24)
        #expect(CLIRunHeader.command(["say", bearer]) == "say ••••")
        #expect(CLIRunHeader.command(["env", key, "ls"]) == "env OPENAI=•••• ls")
        #expect(CLIRunHeader.command(["say", "-H", "X-Trace: " + bearer]) == "say -H ••••")

        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var title: String?
        _ = try CLIRunCommand.perform(
            invocation(["--title-from-command", "--", "env", "API_KEY=abc", "ls"]),
            directory: directory, environment: path, execute: { _, _, _ in 0 },
            render: { options in
                title = options.metadataTitle
                return ""
            })
        #expect(title == "$ env API_KEY=•••• ls")
    }

    @Test func resolvesExecutablesOnThePath() {
        #expect(CLIRunCommand.executablePath(for: "ls", environment: path) == "/bin/ls")
        #expect(CLIRunCommand.executablePath(for: "/bin/ls", environment: [:]) == "/bin/ls")
        #expect(CLIRunCommand.executablePath(for: "./missing", environment: path) == nil)
        #expect(CLIRunCommand.executablePath(for: "ls", environment: [:]) == nil)
    }

    @Test func runsUnderAPseudoTerminalAndReturnsTheCommandStatus() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = directory.appendingPathComponent("capture.log")
        let status = try CLIRunCommand.runUnderPseudoTerminal(
            capture: capture, command: ["/bin/sh", "-c", "printf 'ran\\n'; exit 4"],
            environment: path)
        #expect(status == 4)
        #expect(try String(contentsOf: capture, encoding: .utf8).contains("ran"))
    }
}
