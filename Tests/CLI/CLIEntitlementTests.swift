import CryptoKit
import Foundation
import Testing

@testable import Vitrine

/// Offline CLI license verification and the compile-time boundary around local Debug unlocking.
@Suite("CLI entitlement")
struct CLIEntitlementTests: CLITestSupport {
    @Test func aSignatureValidTokenUnlocksAndTamperingIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = LicenseVerifier(publicKey: key.publicKey)
        let token = try LicenseSigner.sign(
            LicenseToken(licenseID: "CLI-1", issuedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            with: key)

        let dir = try makeTempDirectory()
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

    @Test func aMissingTokenIsLocked() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("absent.token")
        #expect(!CLIEntitlement.isProUnlocked(tokenURL: url, environment: [:]))
    }

    #if DEBUG
        @Test func theDebugEnvBypassUnlocksLocally() throws {
            // VITRINE_PRO_UNLOCK=1 unlocks for local development even with no token —
            // Debug only, so a release CLI never has this path.
            let directory = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("absent.token")
            #expect(
                CLIEntitlement.isProUnlocked(
                    tokenURL: url, environment: ["VITRINE_PRO_UNLOCK": "1"]))
        }
    #endif

    /// Guardrail: the env bypass must be inside `#if DEBUG` so a release CLI can only be
    /// unlocked by a signature-valid token (mirrors the `DebugUnlockProvider` guard).
    @Test func theEnvBypassIsCompiledOutOfRelease() throws {
        let source = try String(
            contentsOf: repoFile("Vitrine", "CLI", "CLIEntitlement.swift"), encoding: .utf8)
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

    @Test func proRequiredReportsAClearMessageAndFailureExitCode() {
        #expect(!CLIError.proRequired.message.isEmpty)
        #expect(CLIError.proRequired.exitCode == 1)
    }
}
