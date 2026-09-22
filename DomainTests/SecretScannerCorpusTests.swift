import Foundation
import Testing
import VitrineDomain

/// Synthetic corpus: no live credentials or provider requests.
struct SecretScannerCorpusTests {
    @Test(arguments: [
        "tokenizer = WordPieceTokenizer()",
        "passwordField = NSSecureTextField()",
        "let secretStore = ApplicationSecretStorage()",
        "let accessToken = SecureTokenProviderFactory (configuration)",
        "let bearer = AuthenticationTokenProvider(argument: 1)",
        "let value = ordinaryLongIdentifierWithoutCredentials",
        "// token: short-example",
    ])
    func ignoresCodeExpressions(_ source: String) {
        #expect(SecretScanner.scan(source).isEmpty)
    }

    @Test(arguments: [
        "API_KEY", "myApiKey", "client-secret", "secret_key", "ACCESS_TOKEN", "password", "passwd",
        "pwd", "bearer",
    ])
    func preservesQuotedAndBareAssignedValues(_ name: String) {
        let secret = String(repeating: "a", count: 24)
        for source in [
            "\(name)=\(secret)", "\"\(name)\": \"\(secret)\"", "\(name) = '\(secret)()'",
        ] {
            #expect(SecretScanner.scan(source).contains { $0.kind == "assigned-secret" })
        }
    }

    @Test func rejectedExpressionDoesNotHideALaterAssignmentOrProviderToken() {
        let secret = String(repeating: "a", count: 24)
        #expect(
            SecretScanner.secretLines(in: "tokenizer = WordPieceTokenizer(); password = \(secret)")
                == [1])
        #expect(
            SecretScanner.secretLines(in: "password = EnvironmentPasswordProvider(\"\(secret)\")")
                == [1])
        // This generated punctuation-only fixture is never used for authentication.
        // Even a short quoted argument must prevent the constructor exemption.
        let shortLiteral = String(repeating: "!", count: 4)
        #expect(
            SecretScanner.secretLines(
                in: "password = EnvironmentPasswordProvider(\"\(shortLiteral)\")") == [1]
        )
        let provider = "gh" + "p_" + String(repeating: "x", count: 36)
        #expect(
            SecretScanner.scan("passwordField = NSSecureTextField(\"\(provider)\")").contains {
                $0.kind == "github-token"
            })
    }

    @Test func punctuationAndNumericValuesAreNotMistakenForCalls() {
        for value in [
            String(repeating: "1", count: 24), String(repeating: "a-", count: 12),
            String(repeating: "a/", count: 12),
        ] {
            #expect(SecretScanner.secretLines(in: "API_KEY=" + value + "()") == [1])
        }
    }

    @Test func providerMinimumLengthsAndWordBoundariesRemainIntact() {
        let github = "gh" + "p_"
        #expect(SecretScanner.scan(github + String(repeating: "a", count: 35)).isEmpty)
        #expect(SecretScanner.scan("x" + github + String(repeating: "a", count: 36)).isEmpty)
        #expect(SecretScanner.scan(github + String(repeating: "a", count: 36) + "_suffix").isEmpty)
        let aws = "AK" + "IA"
        #expect(SecretScanner.scan(aws + String(repeating: "A", count: 17)).isEmpty)
    }

    @Test func unicodeAndCRLFPreserveRowsAndPEMCoverage() {
        let header = "-----BEGIN " + "RSA PRIVATE KEY-----"
        let footer = "-----END " + "RSA PRIVATE KEY-----"
        let source = [
            "let emoji = \"🔐 café\"", "密码: password = " + String(repeating: "a", count: 24), header,
            String(repeating: "b", count: 64), "", footer, "safe",
        ].joined(separator: "\r\n")
        #expect(SecretScanner.secretLines(in: source) == [2, 3, 4, 5, 6])
    }
}

/// Generous wall-clock ceiling catches pathological regex growth, not microsecond
/// noise. Each megabyte-scale input must be scanned fully, including its tail.
struct SecretScannerPerformanceTests {
    @Test(arguments: ["identifier", "keywords", "assignments", "provider-near-match"])
    func adversarialLinesStayWithinBudget(_ shape: String) {
        let body: String
        switch shape {
        case "identifier": body = String(repeating: "a", count: 1_048_576)
        case "keywords": body = String(repeating: "secret", count: 174_763) + " = !"
        case "assignments":
            body = String(repeating: "tokenizer = WordPieceTokenizer(); ", count: 32_768)
        default: body = "eyJ" + String(repeating: "A", count: 1_048_576)
        }
        let source = body + "\npassword = " + String(repeating: "z", count: 24)
        _ = SecretScanner.scan("warmup")
        let start = ContinuousClock.now
        let lines = SecretScanner.secretLines(in: source)
        let elapsed = start.duration(to: .now)
        #expect(lines == [2], "scan the whole input; do not skip the secret after a long line")
        #expect(elapsed < .seconds(3), "scanner exceeded the 3-second hard ceiling: \(elapsed)")
        print("SECRET SCAN \(shape) bytes=\(source.utf8.count) elapsed=\(elapsed)")
    }

    @Test func secretsAtTheEndOfVeryLongLinesAreNotSkipped() {
        let prefix = String(repeating: "a", count: 1_048_576) + " "
        let generic = prefix + "API_KEY=" + String(repeating: "z", count: 24)
        let provider = prefix + "gh" + "p_" + String(repeating: "x", count: 36)
        #expect(SecretScanner.secretLines(in: generic) == [1])
        #expect(SecretScanner.scan(provider).contains { $0.kind == "github-token" && $0.line == 1 })
    }
    @Test func veryLongValuesRemainDetectable() {
        let value = String(repeating: "a", count: 1_048_576)
        #expect(SecretScanner.secretLines(in: "password = " + value) == [1])
        for (prefix, kind) in [
            ("gh" + "p_", "github-token"), ("github" + "_pat_", "github-token"),
            ("xoxb" + "-", "slack-token"), ("sk" + "_live_", "stripe-key"),
            ("sk" + "-proj-", "openai-key"),
        ] {
            #expect(SecretScanner.scan(prefix + value).contains { $0.kind == kind })
        }
        #expect(
            SecretScanner.scan("eyJ" + value + ".eyJ" + value + ".signature").contains {
                $0.kind == "jwt"
            })
    }
}
