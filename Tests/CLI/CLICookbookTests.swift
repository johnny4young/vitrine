import Foundation
import Testing

@testable import VitrineCLICore

/// Every line on the recipes card parses from a clone of this repository, and each access
/// label comes from what the real gate does with that line.
@MainActor
@Suite("Recipes card commands")
struct CLICookbookTests: CLITestSupport {
    /// The sample paths are relative, so resolve them where the card says they run.
    private func atRepositoryRoot<T>(_ body: () throws -> T) throws -> T {
        let manager = FileManager.default
        let previous = manager.currentDirectoryPath
        #expect(manager.changeCurrentDirectoryPath(repoFile().path))
        defer { manager.changeCurrentDirectoryPath(previous) }
        return try body()
    }

    private func expectAccess(_ arguments: [String], requiresPro: Bool, line: String) throws {
        let options = try CLIArguments.parse(arguments)
        if !options.readStdin, options.gitDiffSource == nil {
            #expect(FileManager.default.fileExists(atPath: options.inputPath), "\(line)")
        }
        var gateReadEntitlement = false
        var refused = false
        do {
            try CLIEntitlement.authorize(options) {
                gateReadEntitlement = true
                return false
            }
        } catch {
            refused = true
        }
        #expect(refused == requiresPro, "\(line)")
        #expect(gateReadEntitlement == requiresPro, "\(line)")
    }

    /// `vgrab` and `vpane` are shell functions, so the gate sees the subcommand they run.
    private func helperArguments(_ words: [String], capture: String) -> [String] {
        let edit = words.contains("-e")
        if words[0] == "vgrab" {
            return ["terminal-capture", capture, edit ? "--edit" : "--copy"]
        }
        return ["render", capture, "--language", "terminal", edit ? "--edit" : "--copy"]
    }

    @Test func eachEntrysBadgeMatchesWhatTheGateDoesWithItsLines() throws {
        #expect(CLICookbookEntry.all.count == 5)
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = try writeInput("output", named: "capture", in: directory)

        try atRepositoryRoot {
            for entry in CLICookbookEntry.all {
                for line in entry.lines {
                    let words = line.split(separator: " ").map(String.init)
                    if words[0] != "vitrine" {
                        try expectAccess(
                            helperArguments(words, capture: capture),
                            requiresPro: entry.requiresPro, line: line)
                    } else if let outcome = CLICommandLine.recipeOutcome(
                        for: Array(words.dropFirst()))
                    {
                        #expect(outcome.status == 0, "\(line): \(outcome.error ?? "")")
                        #expect(!entry.requiresPro, "\(line)")
                    } else {
                        try expectAccess(
                            Array(words.dropFirst()), requiresPro: entry.requiresPro, line: line)
                    }
                }
            }
        }
    }

    /// The note beside the terminal entry states this boundary.
    @Test func vpaneNeedsProOnlyWithoutEdit() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = try writeInput("output", named: "capture", in: directory)
        try expectAccess(
            helperArguments(["vpane"], capture: capture), requiresPro: true, line: "vpane")
        try expectAccess(
            helperArguments(["vpane", "-e"], capture: capture), requiresPro: false, line: "vpane -e"
        )
    }

    @Test func theHelpersRunTheSubcommandsTheGateWasAskedAbout() {
        for shell in [ShellInit.Shell.zsh, .bash, .fish] {
            let snippet = ShellInit.snippet(for: shell)
            #expect(snippet.contains("command vitrine terminal-capture"))
            #expect(snippet.contains("--language terminal"))
        }
    }

    @Test func recipeOutcomeReportsOtherCommandsAndFailures() throws {
        #expect(CLICommandLine.recipeOutcome(for: ["render", "a.swift"]) == nil)
        #expect(CLICommandLine.recipeOutcome(for: ["recipe", "--help"])?.status == 0)
        #expect(CLICommandLine.recipeOutcome(for: ["recipe", "nope", "a"])?.status == 2)
        #expect(CLICommandLine.recipeOutcome(for: ["recipe", "validate", "a", "b"])?.status == 2)
        #expect(CLICommandLine.recipeOutcome(for: ["recipe", "validate", "a", "--x"])?.status == 2)
        let missing = try #require(
            CLICommandLine.recipeOutcome(for: ["recipe", "validate", "/absent.json"]))
        #expect(missing.status != 0)
        #expect(missing.error?.hasPrefix("error: ") == true)
    }
}
