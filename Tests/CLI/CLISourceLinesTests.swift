import CoreGraphics
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import VitrineCLICore

@MainActor
@Suite("CLI source lines")
struct CLISourceLinesTests: CLITestSupport {
    private let tenLines = (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n"

    private func loaded(_ text: String) -> FileInputLoader.LoadedFile {
        FileInputLoader.LoadedFile(text: text, language: .swift, filename: "A.swift")
    }

    @Test func slicesTheSpanAndStopsAtTheLastLine() throws {
        #expect(try CLISourceLines.slice(loaded(tenLines), to: 3...4).text == "line 3\nline 4")
        #expect(try CLISourceLines.slice(loaded(tenLines), to: 9...40).text == "line 9\nline 10")
        #expect(try CLISourceLines.slice(loaded(tenLines), to: nil).text == tenLines)
    }

    @Test func rowsMatchTheRendererWhateverTheLineSeparators() throws {
        // CRLF ends a row; a lone CR and U+2028 do not, exactly as the renderer counts.
        let source = "one\r\ntwo\rstill two\u{2028}also two\nthree\nfour\n"
        #expect(LineSplitter.lineCount(of: source) == 5)
        let slice = try CLISourceLines.slice(loaded(source), to: 2...3)
        #expect(slice.text == "two\rstill two\u{2028}also two\nthree")
        #expect(LineSplitter.lineCount(of: slice.text) == 2)
        #expect(try CLISourceLines.slice(loaded(source), to: 1...1).text == "one\r")

        let options = try CLIArguments.parse([
            "render", "in.swift", "--out", "o.png", "--lines", "2-3", "--redact-lines", "3",
        ])
        let config = options.makeConfig(code: slice.text, language: .swift)
        #expect(config.redactedLineRanges == [2...2])
        #expect(config.sidecarText == "two\rstill two\u{2028}also two\n[redacted]")
        #expect(throws: CLIError.sourceLinesOutOfRange(first: 5, lineCount: 4)) {
            try CLISourceLines.slice(loaded(source), to: 5...5)
        }
    }

    @Test func refusesASpanThatStartsPastTheEnd() {
        #expect(throws: CLIError.sourceLinesOutOfRange(first: 11, lineCount: 10)) {
            try CLISourceLines.slice(loaded(tenLines), to: 11...12)
        }
        #expect(
            CLIError.sourceLinesOutOfRange(first: 3, lineCount: 1).message
                == "--lines starts at line 3, but the source has 1 line.")
        #expect(CLIError.sourceLinesOutOfRange(first: 3, lineCount: 1).exitCode == 1)
    }

    @Test func fileRangesMapOntoRenderedRows() {
        #expect(
            CLISourceLines.rows([143...144, 1...2, 146...200], in: 142...146) == [2...3, 5...5])
        #expect(CLISourceLines.rows([3...4], in: nil) == [3...4])
    }

    @Test func theFlagNumbersTheGutterFromTheFileAndRebasesMarks() throws {
        let options = try CLIArguments.parse([
            "render", "in.swift", "--out", "o.png", "--lines", "146-142",
            "--highlight-lines", "143", "--redact-lines", "145-150",
        ])
        #expect(options.sourceLines == 142...146)
        let config = options.makeConfig(code: "a\nb\nc\nd\ne", language: .swift)
        #expect(config.firstLineNumber == 142)
        #expect(config.showLineNumbers)
        #expect(config.highlightedLineRanges == [2...2])
        #expect(config.redactedLineRanges == [4...5])

        let hidden = try CLIArguments.parse([
            "render", "in.swift", "--out", "o.png", "--lines", "5", "--no-line-numbers",
        ])
        #expect(!hidden.makeConfig(code: "x", language: .swift).showLineNumbers)
        let bare = try CLIArguments.parse(["render", "in.swift", "--out", "o.png"])
        #expect(bare.makeConfig(code: "x", language: .swift).firstLineNumber == 1)
        #expect(bare.sourceTitle == nil)
    }

    @Test func refusesSpecsAndSourcesItCannotNumber() {
        for spec in ["1-2,5", "0-3", "a", ""] {
            #expect(throws: CLIError.invalidValue(flag: "--lines", value: spec)) {
                try CLIArguments.parse(["render", "in.swift", "--out", "o.png", "--lines", spec])
            }
        }
        let refused: [[String]] = [
            ["render", "--git-staged", "--out", "o.png", "--lines", "1-2"],
            ["render", "in.swift", "--edit", "--lines", "1-2"],
            ["batch", "src", "--out", "out", "--lines", "1-2"],
            ["render", "in.log", "--out", "o.png", "--language", "terminal", "--lines", "1-2"],
            ["render", "--image", "a.png", "--out", "o.png", "--lines", "1-2"],
        ]
        for arguments in refused {
            #expect(throws: CLIError.self) { try CLIArguments.parse(arguments) }
        }
        #expect(throws: CLIError.unknownFlag("--lines")) {
            try CLIArguments.parse(["terminal-capture", "in.log", "--copy", "--lines", "1-2"])
        }
    }

    @Test func theWindowTitleNamesTheWorkTreeUnlessOneIsGiven() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = directory.appendingPathComponent("weather-app")
        let sources = project.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let input = try writeInput(tenLines, named: "ForecastClient.swift", in: sources)
        let loose = try writeInput(tenLines, named: "Loose.swift", in: directory)

        let options = try CLIArguments.parse(["render", input, "--out", "o.png", "--lines", "2-3"])
        #expect(options.sourceTitle == "weather-app — ForecastClient.swift")
        #expect(
            options.makeConfig(code: "x", language: .swift).windowTitle
                == "weather-app — ForecastClient.swift")
        #expect(CLISourceOrigin.windowTitle(forFile: loose) == "Loose.swift")

        let titled = try CLIArguments.parse([
            "render", input, "--out", "o.png", "--lines", "2-3", "--window-title", "Mine",
        ])
        #expect(titled.makeConfig(code: "x", language: .swift).windowTitle == "Mine")
        let piped = try CLIArguments.parse(["render", "--stdin", "--copy", "--lines", "2-3"])
        #expect(piped.sourceTitle == nil)
    }

    @Test func readsTheBranchFromHeadAndFollowsALinkedWorktree() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let main = directory.appendingPathComponent("app")
        let gitDirectory = main.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        try "ref: refs/heads/feature/run\n".write(
            to: gitDirectory.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        #expect(CLISourceOrigin.projectLabel(directory: main) == "app · feature/run")

        let linked = directory.appendingPathComponent("linked")
        let linkedGit = gitDirectory.appendingPathComponent("worktrees/linked")
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkedGit, withIntermediateDirectories: true)
        try "gitdir: ../app/.git/worktrees/linked\n".write(
            to: linked.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try "0123456789abcdef\n".write(
            to: linkedGit.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        #expect(CLISourceOrigin.projectLabel(directory: linked) == "linked")

        let plain = directory.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        #expect(CLISourceOrigin.repositoryRoot(containing: plain) == nil)
        #expect(CLISourceOrigin.projectLabel(directory: plain) == "plain")
    }

    @Test func rendersASliceAndRefusesTerminalOutput() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try writeInput(tenLines, named: "Ten.swift", in: directory)
        let output = directory.appendingPathComponent("ten.png").path

        let summary = try CLIRenderer.run(
            CLIArguments.parse(["render", input, "--out", output, "--lines", "4-6"]))
        #expect(summary.contains(output))
        #expect(try decodePNG(at: output).width > 0)

        let multiSize = directory.appendingPathComponent("sizes")
        try CLIRenderer.runMultiSize(
            CLIArguments.parse([
                "multi-size", input, "--out", multiSize.path, "--presets", "docs", "--lines", "2",
            ]))
        #expect(
            FileManager.default.fileExists(
                atPath: multiSize.appendingPathComponent("vitrine-docs.png").path))

        let terminal = try CLIArguments.parse(["render", input, "--out", output, "--lines", "1"])
        #expect(throws: CLIError.incompatibleOptions("--lines does not apply to terminal output."))
        {
            try CLIRenderer.run(terminal) { _ in
                FileInputLoader.LoadedFile(
                    text: "\u{1B}[31mred\u{1B}[0m", language: .terminal, filename: "")
            }
        }
    }

    @Test func readsOnlyTheFirstLineOfASmallRegularHead() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gitDirectory = directory.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        let head = gitDirectory.appendingPathComponent("HEAD")

        try "ref: refs/heads/main\nref: refs/heads/other\n".write(
            to: head, atomically: true, encoding: .utf8)
        #expect(CLISourceOrigin.branch(atRepositoryRoot: directory) == "main")
        try "ref: refs/heads/.invalid\n".write(to: head, atomically: true, encoding: .utf8)
        #expect(CLISourceOrigin.branch(atRepositoryRoot: directory) == nil)
        try ("ref: refs/heads/" + String(repeating: "b", count: 5000)).write(
            to: head, atomically: true, encoding: .utf8)
        #expect(CLISourceOrigin.branch(atRepositoryRoot: directory) == nil)

        try FileManager.default.removeItem(at: head)
        #expect(mkfifo(head.path, 0o600) == 0)
        #expect(CLISourceOrigin.firstLine(of: head) == nil)
        #expect(CLISourceOrigin.branch(atRepositoryRoot: directory) == nil)
        #expect(CLISourceOrigin.firstLine(of: gitDirectory) == nil)
    }

    @Test func secretWarningsNameFileLinesAndOutOfSpanRedactionsAreRefused() throws {
        let secret = "let token = \"" + "sk-" + String(repeating: "a", count: 24) + "\""
        let options = try CLIArguments.parse([
            "render", "in.swift", "--out", "o.png", "--lines", "142-143",
        ])
        let config = options.makeConfig(code: "let a = 1\n" + secret, language: .swift)
        let message = try #require(CLIPreflightNotice.message(for: config))
        #expect(message.contains("line 143"))

        #expect(
            throws: CLIError.incompatibleOptions(
                "--redact-lines 300-300 is outside --lines 142-146; use file line numbers.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "o.png", "--lines", "142-146",
                "--redact-lines", "143, 300",
            ])
        }
        #expect(throws: CLIError.incompatibleOptions("Cannot combine --lines with --format-code."))
        {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "o.png", "--lines", "1-2", "--format-code",
            ])
        }
    }
}
