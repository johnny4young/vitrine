import Foundation

/// Lists the local CLI catalogs used to validate themes, languages, export presets, fonts,
/// backgrounds, image frames, frame appearances, watermark positions, formats, and
/// color profiles.
///
/// `vitrine list` is intentionally separate from `CLIArguments`: it does not render,
/// read user files, or need AppKit. The executable handles it before the PRO render
/// gate, giving docs and CI scripts a cheap way to discover valid ids from the same
/// source of truth the parser validates against.
@MainActor
enum CLICatalog {
    enum Catalog: Equatable, Sendable {
        case all
        case themes
        case languages
        case presets
        case fonts
        case backgrounds
        case frames
        case frameAppearances
        case watermarkPositions
        case formats
        case profiles

        init?(argument: String) {
            switch argument.lowercased() {
            case "all": self = .all
            case "theme", "themes": self = .themes
            case "language", "languages": self = .languages
            case "preset", "presets": self = .presets
            case "font", "fonts": self = .fonts
            case "background", "backgrounds": self = .backgrounds
            case "frame", "frames": self = .frames
            case "frame-appearance", "frame-appearances": self = .frameAppearances
            case "watermark-position", "watermark-positions": self = .watermarkPositions
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

    struct Bundle: Encodable, Equatable, Sendable {
        var themes: [Entry]
        var languages: [Entry]
        var presets: [Entry]
        var fonts: [Entry]
        var backgrounds: [Entry]
        var frames: [Entry]
        var frameAppearances: [Entry]
        var watermarkPositions: [Entry]
        var formats: [Entry]
        var profiles: [Entry]
    }

    static let usage = """
        vitrine list <all|themes|languages|presets|fonts|backgrounds|frames|frame-appearances|watermark-positions|formats|profiles> [--json]

        Prints the local ids accepted by render options, including --background,
        --frame, --frame-appearance, and --watermark-position.
        Use `all --json` for one machine-readable object with every catalog.
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
        switch (catalog, format) {
        case (.all, .text):
            allCatalogsText()
        case (.all, .json):
            encodedJSON(bundle())
        case (_, .text):
            entries(for: catalog).map { "\($0.id)\t\($0.name)" }.joined(separator: "\n") + "\n"
        case (_, .json):
            encodedJSON(entries(for: catalog))
        }
    }

    private static func allCatalogsText() -> String {
        concreteCatalogs.map { catalog, title in
            let lines = entries(for: catalog).map { "  \($0.id)\t\($0.name)" }
            return (["\(title):"] + lines).joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }

    private static func bundle() -> Bundle {
        Bundle(
            themes: entries(for: .themes),
            languages: entries(for: .languages),
            presets: entries(for: .presets),
            fonts: entries(for: .fonts),
            backgrounds: entries(for: .backgrounds),
            frames: entries(for: .frames),
            frameAppearances: entries(for: .frameAppearances),
            watermarkPositions: entries(for: .watermarkPositions),
            formats: entries(for: .formats),
            profiles: entries(for: .profiles))
    }

    private static func encodedJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
    }

    private static let concreteCatalogs: [(catalog: Catalog, title: String)] = [
        (.themes, "themes"),
        (.languages, "languages"),
        (.presets, "presets"),
        (.fonts, "fonts"),
        (.backgrounds, "backgrounds"),
        (.frames, "frames"),
        (.frameAppearances, "frame-appearances"),
        (.watermarkPositions, "watermark-positions"),
        (.formats, "formats"),
        (.profiles, "profiles"),
    ]

    private static func entries(for catalog: Catalog) -> [Entry] {
        switch catalog {
        case .all:
            []
        case .themes:
            Theme.builtIns.map { Entry(id: $0.id, name: $0.displayName) }
        case .languages:
            Language.allCases.map { Entry(id: $0.rawValue, name: $0.displayName) }
        case .presets:
            ExportPreset.all.map { Entry(id: $0.id, name: $0.displayName) }
        case .fonts:
            CodeFont.all.map { Entry(id: $0, name: $0) }
        case .backgrounds:
            GradientPreset.allCases.map {
                Entry(id: $0.rawValue.lowercased(), name: $0.rawValue)
            }
        case .frames:
            CLIOptions.ImageFrameOption.allCases.map {
                Entry(id: $0.rawValue, name: $0.displayName)
            }
        case .frameAppearances:
            CLIOptions.ImageFrameAppearance.allCases.map {
                Entry(id: $0.rawValue, name: $0.displayName)
            }
        case .watermarkPositions:
            CLIOptions.WatermarkPosition.allCases.map {
                Entry(id: $0.rawValue, name: $0.displayName)
            }
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
