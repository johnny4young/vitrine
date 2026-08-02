import CoreGraphics
import Foundation

/// A portable, presentation-only configuration for a folder or repository.
///
/// A recipe contains only values needed to reproduce a render: style, optional
/// header metadata, and output defaults. It deliberately contains no workspace
/// path, source text, output path, history, or credentials. The app stores the
/// machine-local `workspace -> recipe` association separately, while the CLI reads
/// a recipe only when the caller passes `--recipe <path>`.
struct WorkspaceRecipe: Codable, Equatable {
    /// Human-readable name shown by the app and diagnostics.
    var name: String
    /// The complete portable presentation snapshot.
    var style: StyleSnapshot
    /// An embedded palette when `style.themeID` identifies a custom theme.
    var customTheme: StoredCustomTheme?
    /// Optional static context for captures produced with the recipe.
    var metadata: Metadata
    /// Output defaults that can still be overridden explicitly by the CLI.
    var output: Output

    init(
        name: String,
        style: StyleSnapshot,
        customTheme: StoredCustomTheme? = nil,
        metadata: Metadata = Metadata(),
        output: Output = Output()
    ) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.style = style
        self.customTheme = customTheme
        self.metadata = metadata
        self.output = output
    }

    /// Context that is safe to carry between the app and explicit CLI workflows.
    struct Metadata: Codable, Equatable {
        var windowTitle: String?
        var header: SnapshotMetadata

        init(windowTitle: String? = nil, header: SnapshotMetadata = SnapshotMetadata()) {
            self.windowTitle = SnapshotMetadata.normalized(windowTitle)
            self.header = Self.portableHeader(header)
        }

        private enum CodingKeys: String, CodingKey { case windowTitle, header }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            windowTitle = SnapshotMetadata.normalized(
                try container.decodeIfPresent(String.self, forKey: .windowTitle))
            header = Self.portableHeader(
                try container.decodeIfPresent(SnapshotMetadata.self, forKey: .header)
                    ?? SnapshotMetadata())
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(windowTitle, forKey: .windowTitle)
            try container.encode(Self.portableHeader(header), forKey: .header)
        }

        /// Keeps a useful filename chip while stripping directory components from
        /// hand-built or older documents. No workspace path should travel with a
        /// portable recipe, regardless of platform path syntax.
        private static func portableHeader(_ header: SnapshotMetadata) -> SnapshotMetadata {
            let leaf = header.filename?.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last
            return SnapshotMetadata(
                filename: leaf.map(String.init), title: header.title, caption: header.caption,
                showLanguageBadge: header.showLanguageBadge)
        }
    }

    /// Portable output defaults. Paths are intentionally absent.
    struct Output: Codable, Equatable {
        var destinationPresetID: String?
        var canvasSize: CanvasSize?
        var scale: Int?
        var format: ExportFormat?
        var colorProfile: ColorProfile?

        init(
            destinationPresetID: String? = nil,
            canvasSize: CanvasSize? = nil,
            scale: Int? = nil,
            format: ExportFormat? = nil,
            colorProfile: ColorProfile? = nil
        ) {
            self.destinationPresetID = destinationPresetID
            self.canvasSize = canvasSize
            self.scale = scale
            self.format = format
            self.colorProfile = colorProfile
        }
    }

    /// A JSON-friendly logical canvas size.
    struct CanvasSize: Codable, Equatable {
        /// The safe logical-dimension limits for a custom canvas. This is the single
        /// source both surfaces enforce — `CLIOptions.canvasDimensionRange` refers here —
        /// so recipe validation and `--canvas-size` can never accept different bounds.
        static let dimensionRange = 64...2_048

        var width: Int
        var height: Int

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        var cgSize: CGSize { CGSize(width: width, height: height) }
    }

    /// Resolves a recipe theme without consulting app defaults or user storage.
    func theme(withID id: String) -> Theme {
        if let customTheme, customTheme.id == id { return customTheme.theme }
        return Theme.theme(withID: id)
    }
}

/// The versioned JSON envelope used to exchange one workspace recipe.
struct WorkspaceRecipeDocument: Codable, Equatable {
    static let formatMarker = "vitrine.workspace-recipe"
    static let currentSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var recipe: WorkspaceRecipe

    init(recipe: WorkspaceRecipe) {
        self.format = Self.formatMarker
        self.schemaVersion = Self.currentSchemaVersion
        self.recipe = recipe
    }

    /// Structural and cross-catalog validation failures.
    enum ValidationError: Error, Equatable {
        case emptyName
        case unknownDestinationPreset(String)
        case unknownTheme(String)
        case unusedCustomTheme(String)
        case customThemeIDMismatch(expected: String, actual: String)
        case invalidScale(Int)
        case invalidCanvasSize(width: Int, height: Int)

        var message: String {
            switch self {
            case .emptyName:
                "The recipe name cannot be empty."
            case .unknownDestinationPreset(let id):
                "The recipe uses an unknown destination preset \"\(id)\"."
            case .unknownTheme(let id):
                "The recipe uses an unknown theme \"\(id)\" without embedding its palette."
            case .unusedCustomTheme(let id):
                "The recipe embeds custom theme \"\(id)\" but does not use it."
            case .customThemeIDMismatch(let expected, let actual):
                "The recipe theme id \"\(expected)\" does not match embedded theme \"\(actual)\"."
            case .invalidScale(let scale):
                "The recipe export scale \(scale) must be between 1 and 3."
            case .invalidCanvasSize(let width, let height):
                "The recipe canvas \(width)x\(height) must use dimensions between 64 and 2048."
            }
        }
    }

    /// Errors surfaced by the versioned document boundary.
    enum ImportError: Error, Equatable {
        case notARecipeFile
        case unsupportedSchemaVersion(Int)
        case unknownField(String)
        case invalidDocument(String)
        case invalid(ValidationError)

        var message: String {
            switch self {
            case .notARecipeFile:
                "This file is not a Vitrine workspace recipe."
            case .unsupportedSchemaVersion(let version):
                "This workspace recipe uses unsupported schema version \(version)."
            case .unknownField(let path):
                "The workspace recipe contains unknown field \"\(path)\"."
            case .invalidDocument(let detail):
                "The workspace recipe is invalid: \(detail)"
            case .invalid(let error):
                error.message
            }
        }
    }

    /// Produces stable, human-readable bytes suitable for source control when the
    /// user explicitly chooses to store a recipe in a repository.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Produces bytes only after checking the same contract the import boundary
    /// enforces. User-facing exporters use this path so they cannot create a recipe
    /// that a later CLI or app invocation would reject.
    func validatedJSONData() throws -> Data {
        do {
            try Self.validate(recipe)
        } catch let error as ValidationError {
            throw ImportError.invalid(error)
        }
        return try jsonData()
    }

    /// Decodes and validates a complete recipe document.
    static func recipe(from data: Data) throws -> WorkspaceRecipe {
        let root: [String: Any]
        do {
            guard
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["format"] as? String == formatMarker
            else {
                throw ImportError.notARecipeFile
            }
            root = object
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.notARecipeFile
        }

        if let path = RecipeJSONShape.firstUnknownField(in: root) {
            throw ImportError.unknownField(path)
        }

        let document: WorkspaceRecipeDocument
        do {
            document = try JSONDecoder().decode(WorkspaceRecipeDocument.self, from: data)
        } catch let error as DecodingError {
            throw ImportError.invalidDocument(Self.message(for: error))
        } catch {
            throw ImportError.invalidDocument("The document could not be decoded.")
        }
        guard document.schemaVersion == currentSchemaVersion else {
            throw ImportError.unsupportedSchemaVersion(document.schemaVersion)
        }
        do {
            try validate(document.recipe)
        } catch let error as ValidationError {
            throw ImportError.invalid(error)
        }
        return document.recipe
    }

    private static func message(for error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            let path = codingPath(context.codingPath)
            return path.isEmpty
                ? "The document contains an invalid value."
                : "The field \"\(path)\" contains an invalid value."
        case .keyNotFound(let key, let context):
            let path = codingPath(context.codingPath + [key])
            return "The required field \"\(path)\" is missing."
        case .typeMismatch(_, let context):
            let path = codingPath(context.codingPath)
            return path.isEmpty
                ? "The document has the wrong value type."
                : "The field \"\(path)\" has the wrong value type."
        case .valueNotFound(_, let context):
            let path = codingPath(context.codingPath)
            return path.isEmpty
                ? "The document contains a missing value."
                : "The field \"\(path)\" contains a missing value."
        @unknown default:
            return "The document could not be decoded."
        }
    }

    private static func codingPath(_ keys: [any CodingKey]) -> String {
        keys.map { key in
            if let index = key.intValue { return "[\(index)]" }
            return key.stringValue
        }
        .reduce(into: "") { path, component in
            if component.hasPrefix("[") {
                path += component
            } else {
                path += path.isEmpty ? component : ".\(component)"
            }
        }
    }

    private static func validate(_ recipe: WorkspaceRecipe) throws {
        guard !recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyName
        }
        if let id = recipe.output.destinationPresetID,
            ExportPreset.preset(withID: id) == nil
        {
            throw ValidationError.unknownDestinationPreset(id)
        }
        if let scale = recipe.output.scale,
            !SettingsDefaults.exportScaleRange.contains(scale)
        {
            throw ValidationError.invalidScale(scale)
        }
        if let canvas = recipe.output.canvasSize,
            !WorkspaceRecipe.CanvasSize.dimensionRange.contains(canvas.width)
                || !WorkspaceRecipe.CanvasSize.dimensionRange.contains(canvas.height)
        {
            throw ValidationError.invalidCanvasSize(width: canvas.width, height: canvas.height)
        }

        let themeID = recipe.style.themeID
        if Theme.builtInIDs.contains(themeID) {
            if let customTheme = recipe.customTheme {
                throw ValidationError.unusedCustomTheme(customTheme.id)
            }
            return
        }
        guard let customTheme = recipe.customTheme else {
            throw ValidationError.unknownTheme(themeID)
        }
        guard customTheme.id == themeID else {
            throw ValidationError.customThemeIDMismatch(
                expected: themeID, actual: customTheme.id)
        }
        guard !Theme.builtInIDs.contains(customTheme.id) else {
            throw ValidationError.unusedCustomTheme(customTheme.id)
        }
    }
}

/// The accepted JSON shape for a workspace recipe.
///
/// `Decodable` deliberately ignores unknown keys, which is useful for app preferences
/// but unsafe for a source-controlled automation contract: a misspelled option would
/// otherwise appear valid while silently doing nothing. This lightweight structural
/// pass rejects extra fields before the typed decoder applies value validation.
private enum RecipeJSONShape {
    static func firstUnknownField(in root: [String: Any]) -> String? {
        if let field = unknownKey(in: root, allowing: ["format", "schemaVersion", "recipe"]) {
            return field
        }
        guard let recipe = root["recipe"] as? [String: Any] else { return nil }
        if let field = unknownKey(
            in: recipe,
            allowing: ["name", "style", "customTheme", "metadata", "output"],
            path: "recipe")
        {
            return field
        }
        if let field = validateStyle(recipe["style"], path: "recipe.style") { return field }
        if let field = validateCustomTheme(recipe["customTheme"], path: "recipe.customTheme") {
            return field
        }
        if let field = validateMetadata(recipe["metadata"], path: "recipe.metadata") {
            return field
        }
        return validateOutput(recipe["output"], path: "recipe.output")
    }

    private static func validateStyle(_ value: Any?, path: String) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        if let field = unknownKey(
            in: object,
            allowing: [
                "themeID", "fontName", "fontSize", "fontLigatures", "padding",
                "cornerRadius", "showChrome", "showShadow", "showLineNumbers", "wrapColumns",
                "background",
            ],
            path: path)
        {
            return field
        }
        return validateBackground(object["background"], path: "\(path).background")
    }

    private static func validateBackground(_ value: Any?, path: String) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        if let field = unknownKey(
            in: object,
            allowing: ["kind", "color", "preset", "customGradient", "image"],
            path: path)
        {
            return field
        }
        if let field = validateColor(object["color"], path: "\(path).color") { return field }
        if let gradient = object["customGradient"] as? [String: Any] {
            if let field = unknownKey(
                in: gradient, allowing: ["stops", "angle"], path: "\(path).customGradient")
            {
                return field
            }
            if let stops = gradient["stops"] as? [Any] {
                for (index, stop) in stops.enumerated() {
                    guard let stop = stop as? [String: Any] else { continue }
                    let stopPath = "\(path).customGradient.stops[\(index)]"
                    if let field = unknownKey(
                        in: stop, allowing: ["color", "location"], path: stopPath)
                    {
                        return field
                    }
                    if let field = validateColor(stop["color"], path: "\(stopPath).color") {
                        return field
                    }
                }
            }
        }
        if let image = object["image"] as? [String: Any] {
            if let field = unknownKey(
                in: image, allowing: ["reference", "fit", "blur", "dimming"], path: "\(path).image")
            {
                return field
            }
            if let reference = image["reference"] as? [String: Any] {
                return unknownKey(
                    in: reference, allowing: ["fileName"], path: "\(path).image.reference")
            }
        }
        return nil
    }

    private static func validateColor(_ value: Any?, path: String) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        return unknownKey(
            in: object, allowing: ["red", "green", "blue", "opacity"], path: path)
    }

    private static func validateCustomTheme(_ value: Any?, path: String) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        if let field = unknownKey(in: object, allowing: ["id", "name", "palette"], path: path) {
            return field
        }
        guard let palette = object["palette"] as? [String: Any] else { return nil }
        return unknownKey(
            in: palette,
            allowing: [
                "background", "foreground", "keyword", "string", "comment", "number", "type",
                "function", "variable", "attribute",
            ],
            path: "\(path).palette")
    }

    private static func validateMetadata(_ value: Any?, path: String) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        if let field = unknownKey(in: object, allowing: ["windowTitle", "header"], path: path) {
            return field
        }
        guard let header = object["header"] as? [String: Any] else { return nil }
        return unknownKey(
            in: header,
            allowing: ["filename", "title", "caption", "showLanguageBadge"],
            path: "\(path).header")
    }

    private static func validateOutput(_ value: Any?, path: String) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        if let field = unknownKey(
            in: object,
            allowing: ["destinationPresetID", "canvasSize", "scale", "format", "colorProfile"],
            path: path)
        {
            return field
        }
        guard let canvas = object["canvasSize"] as? [String: Any] else { return nil }
        return unknownKey(in: canvas, allowing: ["width", "height"], path: "\(path).canvasSize")
    }

    private static func unknownKey(
        in object: [String: Any], allowing keys: Set<String>, path: String = ""
    ) -> String? {
        guard let key = object.keys.filter({ !keys.contains($0) }).sorted().first else {
            return nil
        }
        return path.isEmpty ? key : "\(path).\(key)"
    }
}
