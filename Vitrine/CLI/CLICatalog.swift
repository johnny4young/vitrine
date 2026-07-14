import Foundation

/// Lists the local CLI catalogs used to validate themes, languages, export presets, formats,
/// and color profiles.
///
/// `vitrine list` is intentionally separate from `CLIArguments`: it does not render,
/// read user files, or need AppKit. The executable handles it before the PRO render
/// gate, giving docs and CI scripts a cheap way to discover valid ids from the same
/// source of truth the parser validates against.
@MainActor
enum CLICatalog {
    enum Catalog: Equatable, Sendable {
        case themes
        case languages
        case presets
        case formats
        case profiles

        init?(argument: String) {
            switch argument.lowercased() {
            case "theme", "themes": self = .themes
            case "language", "languages": self = .languages
            case "preset", "presets": self = .presets
            case "format", "formats": self = .formats
            case "profile", "profiles": self = .profiles
            default: return nil
            }
        }
    }

    enum Format: Equatable, Sendable {
        case text
        case json
    }

    enum Invocation: Equatable, Sendable {
        case help
        case listing(Catalog, format: Format)
        case unknownCatalog(String)
        case unknownFlag(String)
        case extraArguments([String])
    }

    struct Entry: Encodable, Equatable, Sendable {
        var id: String
        var name: String
    }

    static let usage = """
        vitrine list <themes|languages|presets|formats|profiles> [--json]

        Prints the local ids accepted by --theme, --language, --preset, --format, and --profile.
        Use --json for a machine-readable array of {id, name} entries.
        """

    static func invocation(for arguments: [String]) -> Invocation {
        var catalog: Catalog?
        var format: Format = .text
        var remaining = ArraySlice(arguments)

        while let token = remaining.first {
            remaining = remaining.dropFirst()
            switch token {
            case "--help", "-h":
                return .help
            case "--json":
                format = .json
            default:
                if token.hasPrefix("-") {
                    return .unknownFlag(token)
                }
                guard catalog == nil else {
                    return .extraArguments([token] + Array(remaining))
                }
                guard let resolved = Catalog(argument: token) else {
                    return .unknownCatalog(token)
                }
                catalog = resolved
            }
        }

        guard let catalog else { return .help }
        return .listing(catalog, format: format)
    }

    static func output(for catalog: Catalog, format: Format) -> String {
        let entries = entries(for: catalog)
        switch format {
        case .text:
            return entries.map { "\($0.id)\t\($0.name)" }.joined(separator: "\n") + "\n"
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = (try? encoder.encode(entries)) ?? Data("[]".utf8)
            return (String(data: data, encoding: .utf8) ?? "[]") + "\n"
        }
    }

    private static func entries(for catalog: Catalog) -> [Entry] {
        switch catalog {
        case .themes:
            Theme.builtIns.map { Entry(id: $0.id, name: $0.displayName) }
        case .languages:
            Language.allCases.map { Entry(id: $0.rawValue, name: $0.displayName) }
        case .presets:
            ExportPreset.all.map { Entry(id: $0.id, name: $0.displayName) }
        case .formats:
            ExportFormat.allCases.map { Entry(id: $0.rawValue, name: $0.displayName) }
        case .profiles:
            [
                Entry(id: "srgb", name: ColorProfile.sRGB.displayName),
                Entry(id: "p3", name: ColorProfile.displayP3.displayName),
            ]
        }
    }
}
