import Foundation

/// Detects likely secrets — API keys, tokens, private keys — in captured code, so the
/// editor can offer one-click opaque redaction before a snapshot is shared.
///
/// Pure and deterministic: it scans text line by line and reports the 1-based line
/// numbers that contain a match plus a short `kind` label, so the result is trivial to
/// unit-test and maps directly onto the canvas's row-based rendering. This is a
/// conservative heuristic, not proof that text contains no secrets. It never drops
/// long lines, and private-key blocks retain complete line coverage.
public enum SecretScanner {
    /// One detected secret: the 1-based line it sits on and a short kind label.
    public struct Match: Equatable {
        public let line: Int
        public let kind: String
    }

    private struct Rule {
        let kind: String
        let regex: NSRegularExpression
    }

    /// Provider shapes remain independent of assignment syntax: a token inside a
    /// constructor argument must still be detected even when the call is benign.
    /// Minimum-length runs use `{n}` + `*`, equivalent to `{n,}` but avoiding
    /// ICU's counted-loop stack exhaustion on very long token values.
    private static let rules: [Rule] = [
        ("aws-access-key", #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#),
        (
            "github-token",
            #"\b(?:gh[pousr]_[A-Za-z0-9]{36}[A-Za-z0-9]*|github_pat_[A-Za-z0-9_]{40}[A-Za-z0-9_]*)\b"#
        ),
        ("slack-token", #"\bxox[baprs]-[A-Za-z0-9-]{10}[A-Za-z0-9-]*\b"#),
        ("google-api-key", #"\bAIza[0-9A-Za-z_\-]{35}\b"#),
        ("stripe-key", #"\b(?:sk|rk|pk)_(?:live|test)_[0-9A-Za-z]{16}[0-9A-Za-z]*\b"#),
        ("openai-key", #"\bsk-[A-Za-z0-9_\-]{20}[A-Za-z0-9_\-]*\b"#),
        ("jwt", #"\beyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\b"#),
        ("private-key", #"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----"#),
    ].map { kind, pattern in
        Rule(kind: kind, regex: expression(pattern))
    }

    /// Tokenize an assignment before inspecting its name. The boundary and
    /// whole identifier prevent retries at every suffix of a long name; keyword
    /// matching must not nest inside overlapping greedy quantifiers. Keep the
    /// simple greedy quantifier: ICU's possessive form exhausts its matching stack
    /// on megabyte identifiers and can silently omit subsequent assignments.
    private static let assignment = expression(
        #"(?<![A-Za-z0-9_-])([A-Za-z0-9_-]+)["']?[^\S\r\n]*[:=][^\S\r\n]*(["']?)([A-Za-z0-9+/_-]{16}[A-Za-z0-9+/_-]*)"#
    )
    private static let secretName = expression(
        #"(?i)(?:api[_-]?key|secret|token|password|passwd|pwd|access[_-]?key|client[_-]?secret|bearer)"#
    )
    private static let callSuffix = expression(#"^[^\S\r\n]*\("#)
    private static let plainIdentifier = expression(#"^[A-Za-z_][A-Za-z0-9_]*$"#)

    private static func expression(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid built-in secret detection expression: \(error)")
        }
    }

    private static func containsAssignedSecret(_ line: String, range: NSRange) -> Bool {
        let source = line as NSString
        // A call may still contain a literal credential of any length. Find its
        // final quote once instead of rescanning every suffix on a dense line.
        let quote = source.rangeOfCharacter(
            from: CharacterSet(charactersIn: "\"'"), options: .backwards)
        let lastQuote = quote.location == NSNotFound ? -1 : quote.location
        var detected = false
        assignment.enumerateMatches(in: line, range: range) { match, _, stop in
            guard let match else { return }
            let name = source.substring(with: match.range(at: 1))
            guard
                secretName.firstMatch(
                    in: name, range: NSRange(location: 0, length: (name as NSString).length)) != nil
            else {
                return
            }
            let valueRange = match.range(at: 3)
            let value = source.substring(with: valueRange)
            let tail = NSRange(
                location: NSMaxRange(valueRange), length: source.length - NSMaxRange(valueRange))
            // A bare identifier followed by '(' is source code, not its runtime
            // value, unless later quoted content may need protection.
            // Never apply this exemption to quoted values or issuer patterns.
            if match.range(at: 2).length == 0,
                lastQuote < NSMaxRange(valueRange),
                plainIdentifier.firstMatch(
                    in: value, range: NSRange(location: 0, length: valueRange.length)) != nil,
                callSuffix.firstMatch(in: line, options: .withTransparentBounds, range: tail) != nil
            {
                return
            }
            detected = true
            stop.pointee = true
        }
        return detected
    }

    /// Every detected secret in line order (a line may match more than one rule).
    ///
    /// Per-line and stateless, with one deliberate exception: a PEM private key spans
    /// many lines but only its `-----BEGIN … PRIVATE KEY-----` banner matches the rule
    /// above, so the scanner carries a flag across lines and also reports every line of
    /// the block — the base64 key material and the `-----END …` banner (through EOF when
    /// the block is never closed). Without this, one-click redaction would cover the
    /// banner and leave the actual key bytes legible.
    public static func scan(_ text: String) -> [Match] {
        var matches: [Match] = []
        var insidePrivateKeyBlock = false
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            var matchedPrivateKeyBanner = false
            for rule in rules where rule.regex.firstMatch(in: line, range: range) != nil {
                matches.append(Match(line: index + 1, kind: rule.kind))
                if rule.kind == "private-key" { matchedPrivateKeyBanner = true }
            }
            if containsAssignedSecret(line, range: range) {
                matches.append(Match(line: index + 1, kind: "assigned-secret"))
            }
            let closesBlock = line.contains("-----END") && line.contains("PRIVATE KEY-----")
            if insidePrivateKeyBlock {
                if !matchedPrivateKeyBanner {
                    matches.append(Match(line: index + 1, kind: "private-key"))
                }
                if closesBlock { insidePrivateKeyBlock = false }
            } else if matchedPrivateKeyBanner && !closesBlock {
                insidePrivateKeyBlock = true
            }
        }
        return matches
    }

    /// The 1-based line numbers that contain at least one likely secret, sorted + unique.
    public static func secretLines(in text: String) -> [Int] {
        Array(Set(scan(text).map(\.line))).sorted()
    }
}
