import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import VitrineCLICore

@MainActor
@Suite("CLI pre-flight notice")
struct CLIPreflightNoticeTests: CLITestSupport {
    // Assembled at runtime so secret-shaped fixtures never trip push protection.
    private let token = "gh" + "p_" + String(repeating: "x", count: 36)

    private func config(_ arguments: [String] = [], code: String) throws -> SnapshotConfig {
        let options = try CLIArguments.parse(
            ["render", "input.swift", "--out", "image.png"] + arguments)
        return options.makeConfig(code: code, language: .swift)
    }

    @Test func cleanInputStaysSilent() throws {
        #expect(CLIPreflightNotice.message(for: try config(code: "let a = 1")) == nil)
    }

    @Test func namesRowsAndKindsWithoutTheMatchOrChangingTheExport() throws {
        let flagged = try config(code: "let a = 1\nlet b = \"\(token)\"")
        let message = try #require(CLIPreflightNotice.message(for: flagged))
        #expect(message.hasPrefix("vitrine: warning: possible secrets at line 2 (github-token)"))
        #expect(message.contains("output unchanged"))
        #expect(message.contains("--redact-secrets"))
        #expect(message.hasSuffix("\n"))
        #expect(!message.contains(token))
        #expect(flagged.redactedLineRanges.isEmpty)
        #expect(flagged.sidecarText.contains(token))
    }

    @Test func redactionFlagsSilenceTheRowsTheyCover() throws {
        let code = "let b = \"\(token)\""
        #expect(
            CLIPreflightNotice.message(for: try config(["--redact-secrets"], code: code)) == nil)
        #expect(
            CLIPreflightNotice.message(for: try config(["--redact-lines", "1"], code: code)) == nil)
    }

    @Test func batchNamesTheFileAndRangesReadAsOne() throws {
        let pem =
            "-----BEGIN RSA PRIVATE " + "KEY-----\nbWF0ZXJpYWw=\n-----END RSA PRIVATE " + "KEY-----"
        let message = try #require(
            CLIPreflightNotice.message(for: try config(code: pem), source: "keys.swift"))
        #expect(message.contains("keys.swift: possible secrets at lines 1-3 (private-key)"))
    }

    @Test func unredactableTextDoesNotOfferTheFlag() throws {
        let flagged = try config(["--title", token, "--redact-secrets"], code: "let a = 1")
        let message = try #require(CLIPreflightNotice.message(for: flagged))
        #expect(message.contains("header or annotation text (github-token)"))
        #expect(!message.contains("--redact-secrets"))
    }

    @Test func overwrittenTerminalOutputIsNotInAnyCLIExport() throws {
        var flagged = try config(code: "\(token)\r\u{1B}[2Kclean\n")
        flagged.language = .terminal
        #expect(
            CLIPreflightNotice.message(for: flagged) == nil, "Sidecars carry the resolved screen")
    }
}
