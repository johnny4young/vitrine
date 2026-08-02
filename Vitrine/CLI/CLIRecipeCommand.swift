import Foundation

/// Pure inspection commands for explicit workspace-recipe files.
///
/// Recipes are intentionally stateless in the CLI: `show` and `validate` read the
/// path supplied by the caller, while render commands consume it through `--recipe`.
/// There is no import or discovery command that could create hidden machine state.
enum CLIRecipeCommand {
    enum Action: Equatable, Sendable { case show, validate }
    enum Format: Equatable, Sendable { case text, json }

    enum Invocation: Equatable, Sendable {
        case help
        case run(Action, path: String, format: Format)
        case unknownAction(String)
        case unknownFlag(String)
        case extraArguments([String])
    }

    struct ValidationSummary: Encodable, Equatable, Sendable {
        var format: String
        var name: String
        var schemaVersion: Int
        var valid: Bool
    }

    static let usage = """
        vitrine recipe validate <path> [--json]
        vitrine recipe show <path> [--json]

        Validates or prints one explicitly named workspace recipe. These commands
        never search parent folders, repositories, or Vitrine's app storage.
        """

    static func invocation(for arguments: [String]) -> Invocation {
        guard let first = arguments.first else { return .help }
        if first == "--help" || first == "-h" { return .help }

        let action: Action
        switch first {
        case "show": action = .show
        case "validate": action = .validate
        default: return first.hasPrefix("-") ? .unknownFlag(first) : .unknownAction(first)
        }

        var path: String?
        var format: Format = .text
        var remaining = ArraySlice(arguments.dropFirst())
        while let token = remaining.first {
            remaining = remaining.dropFirst()
            switch token {
            case "--help", "-h": return .help
            case "--json": format = .json
            default:
                if token.hasPrefix("-") { return .unknownFlag(token) }
                guard path == nil else { return .extraArguments([token] + Array(remaining)) }
                path = token
            }
        }
        guard let path else { return .help }
        return .run(action, path: path, format: format)
    }

    static func output(action: Action, path: String, format: Format) throws -> String {
        let recipe = try CLIRecipeLoader.load(path: path)
        switch (action, format) {
        case (.show, .json):
            let data = try WorkspaceRecipeDocument(recipe: recipe).jsonData()
            return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
        case (.show, .text):
            return textSummary(for: recipe)
        case (.validate, .json):
            let summary = ValidationSummary(
                format: WorkspaceRecipeDocument.formatMarker,
                name: recipe.name,
                schemaVersion: WorkspaceRecipeDocument.currentSchemaVersion,
                valid: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(summary)
            return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
        case (.validate, .text):
            return
                "Valid workspace recipe: \(recipe.name) (schema \(WorkspaceRecipeDocument.currentSchemaVersion))\n"
        }
    }

    private static func textSummary(for recipe: WorkspaceRecipe) -> String {
        var lines = [
            "name\t\(recipe.name)",
            "theme\t\(recipe.style.themeID)",
            "destination\t\(recipe.output.destinationPresetID ?? "default")",
            "format\t\(recipe.output.format?.rawValue ?? "default")",
            "profile\t\(recipe.output.colorProfile?.rawValue ?? "default")",
            "scale\t\(recipe.output.scale.map(String.init) ?? "default")",
        ]
        if let size = recipe.output.canvasSize {
            lines.append("canvas\t\(size.width)x\(size.height)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
