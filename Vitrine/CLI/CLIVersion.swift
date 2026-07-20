import Foundation

/// Prints the installed CLI version without initializing AppKit or touching the PRO gate.
///
/// The public command is exposed as `vitrine` even though the development build product is
/// named `vitrine-cli` to avoid a case-insensitive module collision. Version values come from
/// the main bundle or the enclosing app bundle when available, then fall back to constants that
/// are guarded by tests against `project.yml`.
nonisolated enum CLIVersion {
    enum Format: Equatable, Sendable {
        case text
        case json
    }

    enum Invocation: Equatable, Sendable {
        case help
        case version(format: Format)
        case unknownFlag(String)
        case extraArguments([String])
    }

    struct Values: Encodable, Equatable, Sendable {
        var product: String
        var version: String
        var build: String
    }

    static let publicCommandName = "vitrine"
    static let fallbackMarketingVersion = "0.22.0"
    static let fallbackBuildNumber = "23"

    static let usage = """
        vitrine --version [--json]
        vitrine -v [--json]
        vitrine version [--json]

        Prints the installed Vitrine CLI version. Use --json for a machine-readable object.
        """

    static func invocation(for arguments: [String]) -> Invocation? {
        guard let first = arguments.first else { return nil }
        guard first == "--version" || first == "-v" || first == "version" else { return nil }

        var format: Format = .text
        var remaining = ArraySlice(arguments.dropFirst())
        while let token = remaining.first {
            remaining = remaining.dropFirst()
            switch token {
            case "--help", "-h":
                return .help
            case "--json":
                format = .json
            default:
                if token.hasPrefix("-") { return .unknownFlag(token) }
                return .extraArguments([token] + Array(remaining))
            }
        }
        return .version(format: format)
    }

    static func output(
        format: Format,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary,
        executablePath: String = CommandLine.arguments.first ?? ""
    ) -> String {
        let values = values(infoDictionary: infoDictionary, executablePath: executablePath)
        switch format {
        case .text:
            return "\(values.product) \(values.version) (\(values.build))\n"
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = (try? encoder.encode(values)) ?? Data("{}".utf8)
            return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
        }
    }

    static func values(
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary,
        executablePath: String = CommandLine.arguments.first ?? ""
    ) -> Values {
        let dictionaries = [
            infoDictionary, enclosingAppInfoDictionary(executablePath: executablePath),
        ]
        let version =
            dictionaries.compactMap {
                resolvedString("CFBundleShortVersionString", in: $0)
            }.first ?? fallbackMarketingVersion
        let build =
            dictionaries.compactMap {
                resolvedString("CFBundleVersion", in: $0)
            }.first ?? fallbackBuildNumber
        return Values(product: publicCommandName, version: version, build: build)
    }

    private static func resolvedString(_ key: String, in dictionary: [String: Any]?) -> String? {
        guard let value = dictionary?[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }

    private static func enclosingAppInfoDictionary(executablePath: String) -> [String: Any]? {
        guard !executablePath.isEmpty else { return nil }
        let executableDirectory = URL(fileURLWithPath: executablePath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        let candidates = [
            executableDirectory.deletingLastPathComponent().appendingPathComponent("Info.plist"),
            executableDirectory.appendingPathComponent("Info.plist"),
        ]
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate),
                let dictionary = try? PropertyListSerialization.propertyList(
                    from: data, format: nil) as? [String: Any]
            else { continue }
            return dictionary
        }
        return nil
    }
}
