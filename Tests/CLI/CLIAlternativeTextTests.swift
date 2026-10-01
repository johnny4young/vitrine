import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import VitrineCLICore

@MainActor
@Suite("CLI alternative text")
struct CLIAlternativeTextTests: CLITestSupport {
    @Test func optionUsesSharedValidationAndDoesNotDrawAHeader() throws {
        let options = try CLIArguments.parse([
            "render", "input.swift", "--out", "image.png", "--alt-text", "  Description 👩🏽‍💻  ",
        ])
        let config = options.makeConfig(code: "print(42)", language: .swift)
        #expect(config.altText?.text == "Description 👩🏽‍💻")
        #expect(config.metadata.isEmpty)
        #expect(
            CLIOutputWriter.markdownSidecarContents(for: config, imageName: "image.png").contains(
                "![Description 👩🏽‍💻]"))
        #expect(
            CLIOutputWriter.htmlSidecarContents(for: config, imageName: "image.png").contains(
                "alt=\"Description 👩🏽‍💻\""))
    }

    @Test(arguments: [
        ["render", "input.swift", "--edit", "--alt-text", "Description"],
        ["terminal-capture", "input.log", "--copy", "--alt-text", "Description"],
        [
            "render", "input.swift", "--out", "image.png", "--alt-text",
            String(repeating: "x", count: 1_025),
        ],
    ])
    func invalidCombinationsAndOversizeDescriptionsFail(_ arguments: [String]) {
        #expect(throws: CLIError.self) { try CLIArguments.parse(arguments) }
    }

    @Test func allSidecarsUseSafeSourceAndExplicitAlternativeText() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try writeInput(
            "safe\nPRIVATE_REDACTED_SENTINEL", named: "input.swift", in: directory)
        let output = directory.appendingPathComponent("image.png")
        let options = try CLIArguments.parse([
            "render", input, "--out", output.path, "--sidecars", "all", "--redact-lines", "2",
            "--alt-text", "Readable [description] <&>", "--json",
        ])
        let json = try CLIRenderer.run(options)
        #expect(json.contains("rendered"))
        for ext in ["txt", "md", "html"] {
            let text = try String(
                contentsOf: output.deletingPathExtension().appendingPathExtension(ext),
                encoding: .utf8)
            #expect(!text.contains("PRIVATE_REDACTED_SENTINEL"))
            #expect(text.contains("[redacted]"))
        }
    }
}
