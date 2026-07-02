import Testing

@testable import Vitrine

/// The secret scanner behind one-click redaction: it must catch common credential
/// shapes (so they can be blurred before sharing) without flagging ordinary code.
///
/// All secret-shaped fixtures are assembled at runtime via ``token(_:_:_:)`` so no
/// literal credential ever lands in this source file — GitHub push protection blocks
/// committed secrets, and these test patterns would trip it. The scanner sees the same
/// bytes it would in real code.
@Suite("Secret scanner")
struct SecretScannerTests {
    private func kinds(_ text: String) -> Set<String> {
        Set(SecretScanner.scan(text).map(\.kind))
    }

    /// `prefix` + `count` copies of `body` — e.g. `token("AKIA", "A", 16)`.
    private func token(_ prefix: String, _ body: Character, _ count: Int) -> String {
        prefix + String(repeating: body, count: count)
    }

    @Test func detectsCommonProviderTokens() {
        #expect(kinds("let k = \"\(token("AKIA", "A", 16))\"").contains("aws-access-key"))
        #expect(kinds("let k = \"\(token("ASIA", "A", 16))\"").contains("aws-access-key"))
        #expect(kinds("token: \(token("ghp" + "_", "a", 38))").contains("github-token"))
        #expect(kinds("token: \(token("github" + "_pat_", "b", 50))").contains("github-token"))
        #expect(kinds(token("AIza", "b", 35)).contains("google-api-key"))
        #expect(kinds("stripe = \(token("sk" + "_live_", "c", 20))").contains("stripe-key"))
        #expect(kinds("openai = \(token("sk" + "-proj-", "d", 40))").contains("openai-key"))
        #expect(kinds(token("xoxb" + "-", "d", 14)).contains("slack-token"))
        let jwt = "eyJ" + "AAAA" + "." + "eyJ" + "BBBB" + "." + "CCCC"
        #expect(kinds(jwt).contains("jwt"))
        #expect(kinds("-----BEGIN " + "RSA PRIVATE KEY-----").contains("private-key"))
        #expect(kinds("-----BEGIN " + "PRIVATE KEY-----").contains("private-key"))
    }

    @Test func detectsAssignedSecretsByName() {
        #expect(kinds("API_KEY = \"\(token("v", "x", 20))\"").contains("assigned-secret"))
        #expect(kinds("password: \(token("p", "w", 20))").contains("assigned-secret"))
        #expect(kinds("client_secret=\"\(token("c", "y", 20))\"").contains("assigned-secret"))
        // The secret word may sit inside a larger identifier.
        #expect(kinds("secret_key = \(token("s", "z", 18))").contains("assigned-secret"))
    }

    @Test func reportsTheCorrectLineNumbers() {
        let code = """
            import Foundation
            let user = "alice"
            let key = "\(token("AKIA", "A", 16))"
            print(user)
            let t = "\(token("ghp" + "_", "z", 38))"
            """
        #expect(SecretScanner.secretLines(in: code) == [3, 5])
    }

    @Test func flagsEveryLineOfAPEMPrivateKeyBlock() {
        // Only the BEGIN banner matches the private-key rule; the scanner must still
        // flag the key material and the END banner, or redaction blurs the banner and
        // leaves the key bytes legible.
        let code = """
            // deploy credentials
            -----BEGIN \("RSA ")PRIVATE KEY-----
            \(token("", "q", 32))
            \(token("", "r", 32))
            -----END \("RSA ")PRIVATE KEY-----
            let after = "ok"
            """
        #expect(SecretScanner.secretLines(in: code) == [2, 3, 4, 5])
    }

    @Test func unterminatedPrivateKeyBlockIsFlaggedThroughEndOfInput() {
        let lines = ["-----BEGIN " + "PRIVATE KEY-----", token("", "s", 32), token("", "t", 32)]
        let code = lines.joined(separator: "\n")
        #expect(SecretScanner.secretLines(in: code) == [1, 2, 3])
    }

    @Test func ignoresOrdinaryCode() {
        let code = """
            func add(_ a: Int, _ b: Int) -> Int { a + b }
            let name = "ContentView"
            let total = compute(values, scale: 2)
            // password rules: at least 8 characters
            let items = fetchItems(from: repository)
            """
        #expect(SecretScanner.scan(code).isEmpty, "plain code must not be flagged")
    }

    @Test func emptyAndBlankInputProduceNoMatches() {
        #expect(SecretScanner.scan("").isEmpty)
        #expect(SecretScanner.scan("\n\n   \n").isEmpty)
        #expect(SecretScanner.secretLines(in: "let x = 1").isEmpty)
    }

    @Test func secretLinesAreSortedAndDeduped() {
        // A line matching two rules (assignment + provider prefix) appears once.
        let code = "secret_key = \"\(token("AKIA", "A", 16))\"\nlet ok = 1"
        #expect(SecretScanner.secretLines(in: code) == [1])
        #expect(SecretScanner.scan(code).count >= 2, "both the assignment and the AWS rule match")
    }

    @Test func terminalRedactionScansTheResolvedVisibleText() {
        // For a terminal capture the canvas renders the ANSI-resolved screen
        // (`config.sidecarText`), so redaction scans that — not the raw code — to map onto
        // the rendered rows. A `\r` redraw makes raw vs resolved bytes differ; the secret
        // must still be found on the resolved line the canvas shows.
        var config = SnapshotConfig()
        config.language = .terminal
        config.terminalColumns = 80  // wide enough that the resolved line is a single row
        config.code = "fetching...\rexport API_KEY=" + token("", "k", 20)
        #expect(SecretScanner.secretLines(in: config.sidecarText) == [1])
    }
}
