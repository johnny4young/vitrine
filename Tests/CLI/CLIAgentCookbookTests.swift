import CoreGraphics
import CryptoKit
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import VitrineCLICore

/// Execute the cookbook's contracts using explicit synthetic inputs and an ephemeral verifier.
@MainActor
@Suite("Agent cookbook contracts")
struct CLIAgentCookbookTests: CLITestSupport {
    @Test func discoveryAndRecipeInspectionAreCompleteLocalJSON() throws {
        let catalog = try object(CLICatalog.output(for: .all, format: .json))
        for key in ["themes", "languages", "formats", "profiles", "presets"] {
            #expect(!(try #require(catalog[key] as? [[String: Any]])).isEmpty)
        }
        let path = repoFile("docs", "examples", "documentation.vitrine-recipe.json").path
        let validation = try object(
            CLIRecipeCommand.output(action: .validate, path: path, format: .json))
        let recipe = try object(CLIRecipeCommand.output(action: .show, path: path, format: .json))
        #expect(validation["valid"] as? Bool == true)
        #expect(recipe["format"] as? String == WorkspaceRecipeDocument.formatMarker)
        let name = try #require((recipe["recipe"] as? [String: Any])?["name"] as? String)
        #expect(name == (try #require(validation["name"] as? String)))
        #expect(throws: CLIError.self) {
            try CLIRecipeCommand.output(action: .show, path: path + ".absent", format: .json)
        }
    }

    @Test func freeHandoffDoesNotRenderCopyOrReadAnEntitlementAndFailedOpenStops() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try writeInput("let answer = 42", named: "example.swift", in: directory)
        let options = try CLIArguments.parse(["render", input, "--edit", "--json"])
        try CLIEntitlement.authorize(options) {
            Issue.record("Free handoff read a PRO entitlement")
            return false
        }
        var staged = ""
        let handoff = URL(string: "vitrine://edit?synthetic=example")!
        let result = try object(
            CLIRenderer.openInEditor(
                options,
                stage: { text, language in
                    staged = text
                    #expect(language == .swift)
                    return handoff
                }, open: { $0 == handoff }))
        #expect(staged == "let answer = 42")
        #expect(result["status"] as? String == "opened_editor")
        #expect(result["copied"] as? Bool == false)
        #expect(result["output"] == nil || result["output"] is NSNull)
        #expect(result["sidecars"] as? [String] == [])
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["example.swift"]
        )
        #expect(throws: CLIError.editorOpenFailed) {
            try CLIRenderer.openInEditor(options, stage: { _, _ in handoff }, open: { _ in false })
        }
        #expect(throws: CLIError.self) {
            try CLIArguments.parse([
                "render", input, "--edit", "--out",
                directory.appendingPathComponent("forbidden.png").path,
            ])
        }
    }

    @Test(arguments: [false, true])
    func documentationAndTerminalRenderingUseExplicitPathsAndPreserveAuthorization(
        _ terminal: Bool
    ) throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let example = repoFile(
            "docs", "examples", "agents", terminal ? "terminal.ansi" : "example.swift")
        let output = directory.appendingPathComponent("snapshot.png")
        var arguments = [
            "render", example.path, "--out", output.path, "--format", "png", "--no-overwrite",
            "--sidecars", "all", "--alt-text", "An explicitly authored synthetic example", "--json",
        ]
        if terminal {
            arguments += [
                "--language", "terminal", "--terminal-width", "80", "--redact-lines", "2",
            ]
        } else {
            arguments += [
                "--recipe", repoFile("docs", "examples", "documentation.vitrine-recipe.json").path,
            ]
        }
        let options = try CLIArguments.parse(arguments)
        #expect(throws: CLIError.proRequired) { try CLIEntitlement.authorize(options) { false } }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        // No production key or activation: authorize with a freshly signed token at a private path.
        let key = Curve25519.Signing.PrivateKey()
        let token = try LicenseSigner.sign(
            LicenseToken(licenseID: "synthetic-cookbook", issuedAt: Date()), with: key)
        let tokenURL = directory.appendingPathComponent("synthetic.token")
        try token.write(to: tokenURL, atomically: true, encoding: .utf8)
        try CLIEntitlement.authorize(options) {
            CLIEntitlement.isProUnlocked(
                tokenURL: tokenURL, verifier: LicenseVerifier(publicKey: key.publicKey),
                environment: [:])
        }
        let summary = try object(CLIRenderer.run(options))
        #expect(summary["status"] as? String == "rendered")
        #expect(summary["output"] as? String == output.path)
        #expect(summary["copied"] as? Bool == false)
        #expect((try decodePNG(at: output.path)).width > 0)
        let expected = ["md", "html", "txt"].map {
            output.deletingPathExtension().appendingPathExtension($0)
        }
        #expect(Set(summary["sidecars"] as? [String] ?? []) == Set(expected.map(\.path)))
        for file in expected {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.isEmpty)
            #expect(!text.contains("PRIVATE_REDACTED_SENTINEL"))
        }
        let before = try Data(contentsOf: output)
        #expect(throws: CLIError.self) { try CLIRenderer.run(options) }
        #expect(try Data(contentsOf: output) == before)
    }

    private func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }
}
