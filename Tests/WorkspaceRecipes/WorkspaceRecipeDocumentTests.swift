import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Workspace recipe document")
struct WorkspaceRecipeDocumentTests {
    @Test func roundTripIsDeterministicAndContainsNoWorkspaceOrSource() throws {
        let recipe = WorkspaceRecipe(
            name: "Documentation",
            style: PresetTestFixtures.sampleStyle(),
            metadata: .init(
                windowTitle: "Vitrine",
                header: SnapshotMetadata(
                    filename: "/Users/example/private/Example.swift", title: "CLI example",
                    caption: "Local and repeatable",
                    showLanguageBadge: true)),
            output: .init(
                destinationPresetID: "opengraph",
                canvasSize: .init(width: 1_200, height: 630),
                scale: 1,
                format: .png,
                colorProfile: .sRGB))
        let document = WorkspaceRecipeDocument(recipe: recipe)

        let first = try document.jsonData()
        let decoded = try WorkspaceRecipeDocument.recipe(from: first)
        let second = try WorkspaceRecipeDocument(recipe: decoded).jsonData()

        #expect(decoded == recipe)
        #expect(first == second)
        let json = try #require(String(data: first, encoding: .utf8))
        #expect(json.contains("\"format\" : \"vitrine.workspace-recipe\""))
        #expect(!json.contains("workspacePath"))
        #expect(!json.contains("/Users/example/private"))
        #expect(decoded.metadata.header.filename == "Example.swift")
        #expect(!json.contains("source"))
        #expect(!json.contains("outputPath"))
    }

    @Test func envelopeRejectsWrongFormatAndUnsupportedVersions() throws {
        var wrongFormat = WorkspaceRecipeDocument(recipe: sampleRecipe())
        wrongFormat.format = "another.document"
        #expect(throws: WorkspaceRecipeDocument.ImportError.notARecipeFile) {
            try WorkspaceRecipeDocument.recipe(from: wrongFormat.jsonData())
        }

        var future = WorkspaceRecipeDocument(recipe: sampleRecipe())
        future.schemaVersion = WorkspaceRecipeDocument.currentSchemaVersion + 1
        #expect(
            throws: WorkspaceRecipeDocument.ImportError.unsupportedSchemaVersion(2)
        ) {
            try WorkspaceRecipeDocument.recipe(from: future.jsonData())
        }
    }

    @Test func validatesCatalogReferencesAndOutputBounds() throws {
        var unknownPreset = sampleRecipe()
        unknownPreset.output.destinationPresetID = "unknown"
        #expect(
            throws: WorkspaceRecipeDocument.ImportError.invalid(
                .unknownDestinationPreset("unknown"))
        ) {
            try parse(unknownPreset)
        }

        var invalidScale = sampleRecipe()
        invalidScale.output.scale = 4
        #expect(
            throws: WorkspaceRecipeDocument.ImportError.invalid(.invalidScale(4))
        ) {
            try parse(invalidScale)
        }

        var invalidCanvas = sampleRecipe()
        invalidCanvas.output.canvasSize = .init(width: 63, height: 800)
        #expect(
            throws: WorkspaceRecipeDocument.ImportError.invalid(
                .invalidCanvasSize(width: 63, height: 800))
        ) {
            try parse(invalidCanvas)
        }
    }

    @Test func customThemeTravelsWithTheRecipeAndResolvesByValue() throws {
        let background = try #require(HexColor("#10141C"))
        let foreground = try #require(HexColor("#E6EDF3"))
        let palette = ThemePalette(
            background: background, foreground: foreground,
            keyword: HexColor("#FF7B72"))
        let storedTheme = StoredCustomTheme(
            id: "custom.docs", name: "Docs", palette: palette)
        let recipe = WorkspaceRecipe(
            name: "Custom",
            style: StyleSnapshot(
                themeID: storedTheme.id, background: .gradient(.ocean)),
            customTheme: storedTheme)

        let decoded = try parse(recipe)
        let resolved = decoded.theme(withID: decoded.style.themeID)

        #expect(resolved.id == "custom.docs")
        #expect(resolved.palette == palette)
    }

    @Test func customThemeMustMatchTheStyleReferenceExactly() throws {
        var missing = sampleRecipe()
        missing.style.themeID = "custom.missing"
        #expect(
            throws: WorkspaceRecipeDocument.ImportError.invalid(
                .unknownTheme("custom.missing"))
        ) {
            try parse(missing)
        }

        let palette = ThemePalette(
            background: try #require(HexColor("#000000")),
            foreground: try #require(HexColor("#FFFFFF")))
        var mismatch = missing
        mismatch.customTheme = StoredCustomTheme(
            id: "custom.other", name: "Other", palette: palette)
        #expect(
            throws: WorkspaceRecipeDocument.ImportError.invalid(
                .customThemeIDMismatch(expected: "custom.missing", actual: "custom.other"))
        ) {
            try parse(mismatch)
        }
    }

    private func sampleRecipe() -> WorkspaceRecipe {
        WorkspaceRecipe(name: "Sample", style: PresetTestFixtures.sampleStyle())
    }

    private func parse(_ recipe: WorkspaceRecipe) throws -> WorkspaceRecipe {
        try WorkspaceRecipeDocument.recipe(
            from: WorkspaceRecipeDocument(recipe: recipe).jsonData())
    }
}
