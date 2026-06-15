import CryptoKit
import Foundation
import Testing

@testable import Vitrine

/// CS-094 — PRO gating for automation plus the folder `batch` command. Covers the
/// CLI's offline token verification (the acceptance "the CLI accepts only a
/// signature-valid token"), the `batch` parsing + directory loop, the clear
/// PRO-required error, and the guardrail that the local Debug bypass can never ship.
@MainActor
@Suite("CLI automation gating · CS-094")
struct CLIAutomationTests {
    // MARK: - Offline token verification (the CLI entitlement)

    @Test func aSignatureValidTokenUnlocksAndTamperingIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = LicenseVerifier(publicKey: key.publicKey)
        let token = try LicenseSigner.sign(
            LicenseToken(licenseID: "CLI-1", issuedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            with: key)

        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tokenURL = dir.appendingPathComponent("pro.token")
        try token.write(to: tokenURL, atomically: true, encoding: .utf8)

        // A signature-valid token at the path unlocks, with no env bypass.
        #expect(
            CLIEntitlement.isProUnlocked(
                tokenURL: tokenURL, verifier: verifier, environment: [:]))

        // A tampered token is refused.
        try ("x." + token).write(to: tokenURL, atomically: true, encoding: .utf8)
        #expect(
            !CLIEntitlement.isProUnlocked(
                tokenURL: tokenURL, verifier: verifier, environment: [:]))

        // A token signed by a different key is refused by this verifier.
        try token.write(to: tokenURL, atomically: true, encoding: .utf8)
        let otherVerifier = LicenseVerifier(publicKey: Curve25519.Signing.PrivateKey().publicKey)
        #expect(
            !CLIEntitlement.isProUnlocked(
                tokenURL: tokenURL, verifier: otherVerifier, environment: [:]))
    }

    @Test func aMissingTokenIsLocked() {
        let url = tempDirectory().appendingPathComponent("absent.token")
        #expect(!CLIEntitlement.isProUnlocked(tokenURL: url, environment: [:]))
    }

    #if DEBUG
        @Test func theDebugEnvBypassUnlocksLocally() {
            // VITRINE_PRO_UNLOCK=1 unlocks for local development even with no token —
            // Debug only, so a release CLI never has this path.
            let url = tempDirectory().appendingPathComponent("absent.token")
            #expect(
                CLIEntitlement.isProUnlocked(
                    tokenURL: url, environment: ["VITRINE_PRO_UNLOCK": "1"]))
        }
    #endif

    /// Guardrail: the env bypass must be inside `#if DEBUG` so a release CLI can only be
    /// unlocked by a signature-valid token (mirrors the `DebugUnlockProvider` guard).
    @Test func theEnvBypassIsCompiledOutOfRelease() throws {
        let source = try String(
            contentsOf: Self.repoFile("Vitrine", "CLI", "CLIEntitlement.swift"), encoding: .utf8)
        let lines = source.components(separatedBy: "\n")
        // Match the bypass *code* (the environment read), not the doc-comment mention
        // that precedes it — the comment carries no `#if` and would defeat the scan.
        let index = try #require(
            lines.firstIndex { $0.contains("environment[\"VITRINE_PRO_UNLOCK\"]") },
            "the env bypass should be present in the source")
        let nearestConditional = lines[..<index].last {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#if")
        }
        #expect(
            nearestConditional?.contains("#if DEBUG") == true,
            "the CLI env bypass must be inside #if DEBUG so it never ships")
    }

    // MARK: - Batch command

    @Test func parsesTheBatchCommandAndItsStyleFlags() throws {
        let options = try CLIArguments.parse(
            ["batch", "in-dir", "--out", "out-dir", "--theme", "dracula"])
        #expect(options.command == .batch)
        #expect(options.inputPath == "in-dir")
        #expect(options.outputPath == "out-dir")
        #expect(options.themeID == "dracula")
    }

    @Test func batchRendersEveryTextFileInTheFolder() throws {
        let input = tempDirectory()
        let output = tempDirectory()
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }
        try "let a = 1".write(
            to: input.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "x = 1\n".write(
            to: input.appendingPathComponent("b.py"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse(["batch", input.path, "--out", output.path])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 2 image"))
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("A.png").path))
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("b.png").path))
    }

    @Test func proRequiredReportsAClearMessageAndFailureExitCode() {
        #expect(!CLIError.proRequired.message.isEmpty)
        #expect(CLIError.proRequired.exitCode == 1)
    }

    // MARK: - Helpers

    private func tempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineCLIAuto-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func repoFile(_ components: String...) -> URL {
        components.reduce(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // repo root
        ) { $0.appendingPathComponent($1) }
    }
}
