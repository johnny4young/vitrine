import AppKit
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import VitrineCLICore

/// Input bounds, input protection, editor handoff, clipboard, and exit-code contracts.
@MainActor
@Suite("CLI input safety")
struct CLIInputSafetyTests: CLITestSupport {
    // MARK: - Bounded stdin

    @Test func endlessStandardInputStopsOneBytePastTheLimit() {
        var requested = 0
        #expect(throws: CLIError.inputTooLarge(path: "<stdin>")) {
            try CLIRenderer.readBoundedStandardInput { count in
                requested += count
                return Data(repeating: 0x79, count: count)
            }
        }
        #expect(requested == FileInputLoader.maximumByteCount + 1)
    }

    @Test func standardInputWithinTheLimitIsReadToTheEnd() throws {
        var chunks = [Data("let a = 1\n".utf8), Data("let b = 2\n".utf8)]
        let data = try CLIRenderer.readBoundedStandardInput(limit: 64) { _ in
            chunks.isEmpty ? nil : chunks.removeFirst()
        }
        #expect(String(decoding: data, as: UTF8.self) == "let a = 1\nlet b = 2\n")
    }

    // MARK: - Outputs never replace inputs

    @Test func primaryOutputCannotOverwriteItsSource() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try writeInput("# Notes\n", named: "notes.md", in: directory)
        let options = try CLIArguments.parse(["render", input, "--out", input])

        #expect(throws: CLIError.self) { try CLIRenderer.run(options) }
        #expect(try String(contentsOfFile: input, encoding: .utf8) == "# Notes\n")
    }

    @Test func outputCannotOverwriteTheBackgroundImage() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try writeInput(named: "Sample.swift", in: directory)
        let background = directory.appendingPathComponent("background.png")
        try writeFixtureImage(to: background, size: CGSize(width: 32, height: 20))
        let original = try Data(contentsOf: background)
        let options = try CLIArguments.parse([
            "render", input, "--out", background.path, "--background-image", background.path,
        ])

        #expect(throws: CLIError.self) { try CLIRenderer.run(options) }
        #expect(try Data(contentsOf: background) == original)
    }

    // MARK: - Editor handoff

    @Test(arguments: [
        ["--theme", "dracula"], ["--scale", "3"], ["--format", "pdf"],
        ["--preset", "opengraph"], ["--profile", "p3"], ["--no-overwrite"],
    ])
    func editRejectsOptionsTheHandoffCannotCarry(_ flags: [String]) {
        #expect(throws: CLIError.self) {
            try CLIArguments.parse(["render", "snippet.swift", "--edit"] + flags)
        }
    }

    @Test func editCarriesThePinnedTerminalWidth() throws {
        let options = try CLIArguments.parse([
            "terminal-capture", "capture.log", "--edit", "--terminal-width", "120",
        ])
        var staged: EditorHandoff.Payload?
        try CLIRenderer.openInEditor(
            options,
            fileLoader: { _ in
                FileInputLoader.LoadedFile(text: "ok", language: .terminal, filename: "capture.log")
            },
            stage: {
                staged = $0
                return URL(string: "vitrine://edit")
            },
            open: { _ in true })
        #expect(staged?.columns == 120)
        #expect(staged?.language == .terminal)
    }

    @Test func handoffRoundTripsColumnsAndDropsOutOfRangeHints() throws {
        let url = try #require(
            EditorHandoff.stage(content: "wide", language: .terminal, columns: 132))
        #expect(EditorHandoff.consume(url: url)?.columns == 132)

        let staged = try #require(EditorHandoff.stage(content: "x", language: .terminal))
        defer { _ = EditorHandoff.consume(url: staged) }
        var components = try #require(URLComponents(url: staged, resolvingAgainstBaseURL: false))
        components.queryItems?.append(URLQueryItem(name: EditorHandoff.columnsKey, value: "5000"))
        let hostile = try #require(components.url)
        #expect(EditorHandoff.consume(url: hostile)?.columns == nil)
    }

    @Test func editRefusesAnEmptySourceBeforeOpeningTheApp() throws {
        let options = try CLIArguments.parse(["render", "empty.log", "--edit"])
        #expect(throws: CLIError.editorHandoffEmpty) {
            try CLIRenderer.openInEditor(
                options,
                fileLoader: { _ in
                    FileInputLoader.LoadedFile(text: "", language: .terminal, filename: "empty.log")
                },
                stage: { _ in
                    Issue.record("An empty source must not be staged")
                    return nil
                },
                open: { _ in
                    Issue.record("An empty source must not open the app")
                    return true
                })
        }
    }

    // MARK: - Clipboard

    @Test func clipboardOnlyCopyRejectsANonPNGFormat() {
        #expect(throws: CLIError.self) {
            try CLIArguments.parse(["render", "in.swift", "--copy", "--format", "pdf"])
        }
        #expect(throws: Never.self) {
            try CLIArguments.parse([
                "render", "in.swift", "--copy", "--out", "o.pdf", "--format", "pdf",
            ])
        }
    }

    @Test func failedWriteLeavesTheClipboardUntouched() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try writeInput(named: "Sample.swift", in: directory)
        let unwritable = directory.appendingPathComponent("missing/out.png").path
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let changeCount = pasteboard.changeCount
        let options = try CLIArguments.parse(["render", input, "--copy", "--out", unwritable])

        #expect(throws: CLIError.writeFailed(path: unwritable)) {
            try CLIRenderer.run(options, pasteboard: pasteboard)
        }
        #expect(pasteboard.changeCount == changeCount)
    }

    @Test func copyAndWriteShareOneRasterAndReportPNGForTheClipboard() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try writeInput(named: "Sample.swift", in: directory)
        let output = directory.appendingPathComponent("out.png")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }

        let both = try CLIArguments.parse([
            "render", input, "--copy", "--out", output.path, "--json",
        ])
        let summary = try CLIRenderer.run(both, pasteboard: pasteboard)
        #expect(summary.contains("copied_and_rendered"))
        #expect(pasteboard.data(forType: .png) == (try Data(contentsOf: output)))

        let copyOnly = try CLIArguments.parse(["render", input, "--copy", "--json"])
        let copied = try CLIRenderer.run(copyOnly, pasteboard: pasteboard)
        #expect(copied.contains(#""format" : "png""#))
    }

    // MARK: - Executable location

    @Test func fontsAreFoundThroughAPathSymlink() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let binDirectory = root.appendingPathComponent("Vitrine.app/Contents/MacOS")
        let fonts = root.appendingPathComponent("Vitrine.app/Contents/Resources/Fonts")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
        let executable = binDirectory.appendingPathComponent("vitrine-cli")
        try Data().write(to: executable)
        let pathDirectory = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(
            at: pathDirectory, withIntermediateDirectories: true)
        let link = pathDirectory.appendingPathComponent("vitrine")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)

        let found = CLIEnvironment.bundledFontsDirectory(executableURL: link)
        #expect(found?.resolvingSymlinksInPath().path == fonts.resolvingSymlinksInPath().path)
        #expect(CLIEnvironment.bundledFontsDirectory(executableURL: nil) == nil)
    }

    @Test func theExecutableLocationIsAbsoluteRegardlessOfArgv() throws {
        let url = try #require(CLIEnvironment.executableURL)
        #expect(url.path.hasPrefix("/"))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Exit codes and diagnostics

    @Test func usageErrorsExitTwoAndRuntimeFailuresExitOne() {
        let usage: [CLIError] = [
            .unknownCommand("x"), .unknownFlag("--x"), .unexpectedArgument("b.swift"),
            .missingValue(flag: "--out"), .missingRequired("input file"),
            .invalidValue(flag: "--theme", value: "x"), .incompatibleOptions("conflict"),
        ]
        for error in usage {
            #expect(error.isUsageError)
            #expect(error.exitCode == 2)
        }
        let runtime: [CLIError] = [
            .proRequired, .writeFailed(path: "/x"), .renderTooLarge,
            .batchSkipped(rendered: 1, skipped: 1), .editorOpenFailed,
            .inputTooLarge(path: "/x"),
        ]
        for error in runtime {
            #expect(!error.isUsageError)
            #expect(error.exitCode == 1)
        }
    }

    @Test func aSecondPositionalIsAnUnexpectedArgument() {
        #expect(throws: CLIError.unexpectedArgument("b.swift")) {
            try CLIArguments.parse(["render", "a.swift", "b.swift", "--out", "o.png"])
        }
    }

    @Test func helpTextMatchesWhatTheParserAccepts() {
        #expect(CLIUsage.text.contains("(--copy [--filename <text>] [--title <text>] | --edit)"))
        let profile = CLIArgumentSchema.helpText
        #expect(profile.contains("HEIC"))
        #expect(!profile.contains("PNG color profile"))
    }
}
