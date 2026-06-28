import Foundation

/// Detects likely secrets — API keys, tokens, private keys — in captured code, so the
/// editor can offer one-click redaction (blur the lines) before a snapshot is shared.
///
/// Pure and deterministic: it scans text line by line and reports the 1-based line
/// numbers that contain a match plus a short `kind` label, so the result is trivial to
/// unit-test and maps directly onto the canvas's row-based rendering. It deliberately
/// errs toward catching things — a false positive only blurs an extra line (which the
/// user can adjust), while a miss leaks a credential.
enum SecretScanner {
    /// One detected secret: the 1-based line it sits on and a short kind label.
    struct Match: Equatable {
        let line: Int
        let kind: String
    }

    private struct Rule {
        let kind: String
        let regex: NSRegularExpression
    }

    /// High-confidence provider patterns first, then a broader `name = long-value`
    /// catch-all. Specific issuer prefixes (AKIA, ghp_, AIza, sk_live_, …) rarely
    /// false-positive; the catch-all requires a 16+ char unbroken value so it skips
    /// ordinary `name = functionCall(x)` assignments.
    private static let rules: [Rule] = [
        ("aws-access-key", #"\bAKIA[0-9A-Z]{16}\b"#),
        ("github-token", #"\bgh[pousr]_[A-Za-z0-9]{36,}\b"#),
        ("slack-token", #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#),
        ("google-api-key", #"\bAIza[0-9A-Za-z_\-]{35}\b"#),
        ("stripe-key", #"\b(?:sk|rk|pk)_(?:live|test)_[0-9A-Za-z]{16,}\b"#),
        ("openai-key", #"\bsk-[A-Za-z0-9]{20,}\b"#),
        ("jwt", #"\beyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\b"#),
        ("private-key", #"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----"#),
        (
            // The secret word may sit inside a larger identifier (`secret_key`, `myApiKey`,
            // `ACCESS_TOKEN`), so allow surrounding identifier chars rather than requiring
            // word boundaries; the 16+ char unbroken value still skips `name = call(x)`.
            "assigned-secret",
            #"(?i)[a-z0-9_]*(?:api[_-]?key|secret|token|password|passwd|pwd|access[_-]?key|client[_-]?secret|bearer)[a-z0-9_]*["']?\s*[:=]\s*["']?[A-Za-z0-9+/_\-]{16,}"#
        ),
    ].compactMap { kind, pattern in
        (try? NSRegularExpression(pattern: pattern)).map { Rule(kind: kind, regex: $0) }
    }

    /// Every detected secret in line order (a line may match more than one rule).
    static func scan(_ text: String) -> [Match] {
        var matches: [Match] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for rule in rules where rule.regex.firstMatch(in: line, range: range) != nil {
                matches.append(Match(line: index + 1, kind: rule.kind))
            }
        }
        return matches
    }

    /// The 1-based line numbers that contain at least one likely secret, sorted + unique.
    static func secretLines(in text: String) -> [Int] {
        Array(Set(scan(text).map(\.line))).sorted()
    }
}
