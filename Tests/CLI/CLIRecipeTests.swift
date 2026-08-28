import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("CLI workspace recipes")
struct CLIRecipeTests: CLITestSupport {
    @Test func documentedRecipeRemainsValid() throws {
        let path = repoFile("docs", "examples", "documentation.vitrine-recipe.json").path
        let recipe = try CLIRecipeLoader.load(path: path)

        #expect(recipe.name == "Documentation")
        #expect(recipe.style.themeID == Theme.nord.id)
        #expect(recipe.output.destinationPresetID == "opengraph")
    }

    @Test func recipeInspectionCommandsAreStrictAndMachineReadable() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = try writeRecipe(
            WorkspaceRecipe(
                name: "Inspection",
                style: StyleSnapshot(
                    themeID: Theme.nord.id, background: .gradient(.forest)),
                output: .init(
                    destinationPresetID: "opengraph", scale: 1, format: .png,
                    colorProfile: .sRGB)),
            in: directory)

        #expect(
            CLIRecipeCommand.invocation(for: ["validate", path, "--json"])
                == .run(.validate, path: path, format: .json))
        #expect(
            CLIRecipeCommand.invocation(for: ["show", path])
                == .run(.show, path: path, format: .text))
        #expect(CLIRecipeCommand.invocation(for: ["import"]) == .unknownAction("import"))
        #expect(
            CLIRecipeCommand.invocation(for: ["show", path, "extra"]) == .extraArguments(["extra"]))

        let validation = try CLIRecipeCommand.output(
            action: .validate, path: path, format: .json)
        #expect(validation.contains("\"valid\" : true"))
        #expect(validation.contains("\"name\" : \"Inspection\""))

        let canonical = try CLIRecipeCommand.output(action: .show, path: path, format: .json)
        #expect(canonical.contains("\"format\" : \"vitrine.workspace-recipe\""))
        #expect(canonical.contains("\"destinationPresetID\" : \"opengraph\""))
    }

    @Test func explicitRecipeSeedsStyleMetadataAndExportDefaults() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = try writeRecipe(
            WorkspaceRecipe(
                name: "Docs",
                style: StyleSnapshot(
                    themeID: Theme.nord.id,
                    fontName: "Fira Code",
                    fontSize: 16,
                    padding: 48,
                    showChrome: false,
                    showShadow: false,
                    showLineNumbers: true,
                    background: .gradient(.forest)),
                metadata: .init(
                    windowTitle: "Vitrine",
                    header: SnapshotMetadata(
                        filename: "Example.swift", title: "Workspace recipe",
                        caption: "Explicit local configuration", showLanguageBadge: true)),
                output: .init(
                    destinationPresetID: "opengraph",
                    canvasSize: .init(width: 900, height: 500),
                    scale: 1,
                    format: .pdf,
                    colorProfile: .displayP3)),
            in: directory)

        let options = try CLIArguments.parse([
            "render", "in.swift", "--out", directory.appendingPathComponent("render").path,
            "--recipe", path,
        ])
        let config = options.makeConfig(code: "let value = 42", language: .swift)

        #expect(options.recipe?.name == "Docs")
        #expect(options.presetID == "opengraph")
        #expect(options.canvasSize == .init(width: 900, height: 500))
        #expect(options.effectiveScale == 1)
        #expect(options.format == .pdf)
        #expect(options.profile == .displayP3)
        #expect(config.theme.id == Theme.nord.id)
        #expect(config.fontName == "Fira Code")
        #expect(config.padding == 48)
        #expect(!config.showChrome)
        #expect(!config.showShadow)
        #expect(config.showLineNumbers)
        #expect(config.background == .gradient(.forest))
        #expect(config.windowTitle == "Vitrine")
        #expect(config.metadata.filename == "Example.swift")
        #expect(config.metadata.title == "Workspace recipe")
        #expect(config.metadata.caption == "Explicit local configuration")
        #expect(config.metadata.showLanguageBadge)
        #expect(config.code == "let value = 42")
    }

    @Test func explicitCLIValuesOverrideRecipeDefaults() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = try writeRecipe(
            WorkspaceRecipe(
                name: "Base",
                style: StyleSnapshot(
                    themeID: Theme.nord.id, padding: 48,
                    background: .gradient(.forest)),
                metadata: .init(
                    header: SnapshotMetadata(
                        title: "Recipe title", showLanguageBadge: true)),
                output: .init(
                    destinationPresetID: "opengraph",
                    canvasSize: .init(width: 900, height: 500),
                    scale: 1,
                    format: .pdf,
                    colorProfile: .displayP3)),
            in: directory)

        let options = try CLIArguments.parse([
            "render", "in.swift", "--out", directory.appendingPathComponent("render.png").path,
            "--recipe", path,
            "--preset", "twitter",
            "--style-preset", "builtin.minimal",
            "--theme", "dracula",
            "--background", "night",
            "--canvas-size", "800x600",
            "--scale", "3",
            "--profile", "srgb",
            "--title", "CLI title",
            "--no-language-badge",
        ])
        let config = options.makeConfig(code: "X", language: .swift)

        #expect(options.presetID == "twitter")
        #expect(options.canvasSize == .init(width: 800, height: 600))
        #expect(options.effectiveScale == 3)
        #expect(options.format == .png)
        #expect(options.profile == .sRGB)
        #expect(config.theme.id == Theme.dracula.id)
        #expect(config.background == .gradient(.night))
        #expect(config.padding == StylePreset.minimal.style.padding)
        #expect(config.metadata.title == "CLI title")
        #expect(!config.metadata.showLanguageBadge)
    }

    @Test func recipeIsNeverDiscoveredImplicitly() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try writeRecipe(
            WorkspaceRecipe(
                name: "Nearby",
                style: StyleSnapshot(
                    themeID: Theme.dracula.id, background: .gradient(.sunset))),
            in: directory)

        let options = try CLIArguments.parse([
            "render", directory.appendingPathComponent("in.swift").path,
            "--out", directory.appendingPathComponent("out.png").path,
        ])

        #expect(options.recipe == nil)
        #expect(options.makeConfig(code: "X", language: .swift).theme.id == Theme.oneDark.id)
    }

    @Test func rejectsUnreadableInvalidAndOversizedRecipes() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let missing = directory.appendingPathComponent("missing.json").path
        #expect(throws: CLIError.recipeUnreadable(path: missing)) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--recipe", missing,
            ])
        }

        let invalid = directory.appendingPathComponent("invalid.json")
        try Data("{}".utf8).write(to: invalid)
        #expect(
            throws: CLIError.invalidRecipe(
                WorkspaceRecipeDocument.ImportError.notARecipeFile.message)
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--recipe", invalid.path,
            ])
        }

        let oversized = directory.appendingPathComponent("oversized.json")
        try Data(repeating: 0x20, count: CLIRecipeLoader.maximumByteCount + 1)
            .write(to: oversized)
        #expect(
            throws: CLIError.invalidRecipe(
                "The workspace recipe is larger than 1 MB and was not read.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--recipe", oversized.path,
            ])
        }

        #expect(
            throws: CLIError.recipeUnreadable(path: directory.path)
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--recipe", directory.path,
            ])
        }
    }

    @Test func recipeRejectsImageAndConflictingMultiSizeOutputDefaults() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = try writeRecipe(
            WorkspaceRecipe(
                name: "Sized",
                style: StyleSnapshot(
                    themeID: Theme.nord.id, background: .gradient(.forest)),
                output: .init(canvasSize: .init(width: 800, height: 600))),
            in: directory)

        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --image with --recipe; workspace recipes configure code captures."
            )
        ) {
            try CLIArguments.parse([
                "render", "--image", "image.png", "--out", "out.png", "--recipe", path,
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot use recipe canvas-size or scale defaults with multi-size; destination presets pin their dimensions."
            )
        ) {
            try CLIArguments.parse([
                "multi-size", "in.swift", "--out", "out", "--recipe", path,
            ])
        }
    }

    @Test func recipeRejectsEditorHandoffWithAnAccurateCapabilityError() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let styleOnlyPath = try writeRecipe(
            WorkspaceRecipe(
                name: "Style only",
                style: StyleSnapshot(
                    themeID: Theme.nord.id, background: .gradient(.forest))),
            in: directory)

        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "--edit", "--recipe", styleOnlyPath,
            ])
        }

        let metadataPath = try writeRecipe(
            WorkspaceRecipe(
                name: "Header",
                style: StyleSnapshot(
                    themeID: Theme.nord.id, background: .gradient(.forest)),
                metadata: .init(header: SnapshotMetadata(title: "Documentation"))),
            named: "metadata.vitrine-recipe.json",
            in: directory)
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with metadata header options.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "--edit", "--recipe", metadataPath,
            ])
        }
    }

    private func writeRecipe(
        _ recipe: WorkspaceRecipe,
        named filename: String = "workspace.vitrine-recipe.json",
        in directory: URL
    ) throws -> String {
        let url = directory.appendingPathComponent(filename)
        try WorkspaceRecipeDocument(recipe: recipe).jsonData().write(to: url, options: .atomic)
        return url.path
    }
}
