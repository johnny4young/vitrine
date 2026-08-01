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

    /// A JSON-friendly logical canvas size with the same safe limits as the CLI.
    struct CanvasSize: Codable, Equatable {
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
        case invalid(ValidationError)

        var message: String {
            switch self {
            case .notARecipeFile:
                "This file is not a Vitrine workspace recipe."
            case .unsupportedSchemaVersion(let version):
                "This workspace recipe uses unsupported schema version \(version)."
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

    /// Decodes and validates a complete recipe document.
    static func recipe(from data: Data) throws -> WorkspaceRecipe {
        let document: WorkspaceRecipeDocument
        do {
            document = try JSONDecoder().decode(WorkspaceRecipeDocument.self, from: data)
        } catch {
            throw ImportError.notARecipeFile
        }
        guard document.format == formatMarker else { throw ImportError.notARecipeFile }
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
