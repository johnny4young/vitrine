import Foundation
import VitrineDomain

/// The `$ command` header `vitrine run` draws. Vitrine composes it from argv, so by default
/// it shows only the program. With `--title-from-command` it shows every argument, treating
/// each as untrusted: credential-shaped values get a fixed-width mask and `SecretScanner`
/// runs on top.
enum CLIRunHeader {
    static let mask = "••••"

    private static let sensitiveWords = [
        "password", "passwd", "pass", "pwd", "token", "secret", "key", "auth", "credential",
        "cookie", "session", "bearer",
    ]

    /// Short options that commonly take a password, account or key as the next word.
    private static let valueFlags: Set<String> = ["-p", "-P", "-a", "-k"]

    /// What the next argument is, when `argument` is an option that takes one.
    private enum Expectation { case value, user, header }

    /// `npm …`: the program's name, and an ellipsis when arguments were left out.
    static func program(_ arguments: [String]) -> String {
        guard let executable = arguments.first else { return "" }
        let name = quoted(URL(fileURLWithPath: executable).lastPathComponent)
        return arguments.count > 1 ? name + " …" : name
    }

    /// Every argument, masked. Used only when the user opts in with `--title-from-command`.
    static func command(_ arguments: [String]) -> String {
        var expectation: Expectation?
        return arguments.map { argument in
            let shown = masked(argument, after: expectation)
            expectation = Self.expectation(after: argument)
            return quoted(shown)
        }.joined(separator: " ")
    }

    /// Whether an option, variable or header name suggests a credential. `author` alone is
    /// not one, so `git log --author alice` stays readable.
    static func isSensitive(_ name: some StringProtocol) -> Bool {
        let lowered = name.lowercased()
            .replacingOccurrences(of: "authoriz", with: "auth")
            .replacingOccurrences(of: "author", with: "")
        return sensitiveWords.contains { lowered.contains($0) }
    }

    private static func expectation(after argument: String) -> Expectation? {
        guard argument.hasPrefix("-"), !argument.contains("=") else { return nil }
        if valueFlags.contains(argument) { return .value }
        switch argument {
        case "-u", "--user": return .user
        case "-H", "--header": return .header
        default:
            // `-password x` and `-token x` take the next word; masking it when the name only
            // looks sensitive (`-psecret db`) shows less, never more.
            let name = argument.drop { $0 == "-" }
            return name.count > 1 && isSensitive(name) ? .value : nil
        }
    }

    private static func masked(_ argument: String, after expectation: Expectation?) -> String {
        // A value may itself start with `-`, so an expected value is masked whatever it looks like.
        switch expectation {
        case .value: return mask
        case .user where argument.contains(":"): return mask
        case .header: return maskingHeader(argument)
        default: break
        }
        let text = maskingURLUserinfo(argument)
        if text.hasPrefix("-"), !text.hasPrefix("--"), text.count > 2 {
            let flag = String(text.prefix(2))
            let rest = text.dropFirst(2)
            if flag == "-p" || flag == "-P" { return flag + mask }
            if flag == "-u", rest.contains(":") { return flag + mask }
            if flag == "-H" { return flag + maskingHeader(String(rest)) }
        }
        if let equals = text.firstIndex(of: "="), equals != text.startIndex {
            let name = text[..<equals].drop { $0 == "-" }
            let value = text[text.index(after: equals)...]
            let plainName =
                !name.isEmpty
                && name.allSatisfy { $0.isLetter || $0.isNumber || "_-.".contains($0) }
            if plainName {
                let prefix = String(text[...equals])
                if name == "header" { return prefix + maskingHeader(String(value)) }
                if isSensitive(name) || (name == "user" && value.contains(":")) {
                    return prefix + mask
                }
                if !SecretScanner.scan(String(value)).isEmpty { return prefix + mask }
            }
        }
        return SecretScanner.scan(text).isEmpty ? text : mask
    }

    /// `Authorization: Basic …` becomes `Authorization: ••••`; other headers stay as typed.
    private static func maskingHeader(_ header: String) -> String {
        if let colon = header.firstIndex(of: ":") {
            let name = header[..<colon].trimmingCharacters(in: .whitespaces)
            if isSensitive(name) { return "\(name): \(mask)" }
        }
        return SecretScanner.scan(header).isEmpty ? header : mask
    }

    /// Masks a URL's whole userinfo, the user name included, whatever its length.
    private static func maskingURLUserinfo(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"([A-Za-z][A-Za-z0-9+.-]*://)[^/\s@]*@"#, with: "$1\(mask)@",
            options: .regularExpression)
    }

    /// Quotes as the reproduction command does, treating the mask and a non-leading `=` as
    /// plain text, since only a leading `=` expands in zsh.
    private static func quoted(_ text: String) -> String {
        let masked = text.replacingOccurrences(of: mask, with: "x")
        let bare =
            String(masked.prefix(1)) + masked.dropFirst().replacingOccurrences(of: "=", with: "x")
        let quotedBare = CLIReproductionCommand.shellQuoted(bare)
        return quotedBare == bare ? text : CLIReproductionCommand.shellQuoted(text)
    }
}
