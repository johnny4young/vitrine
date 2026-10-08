import Foundation
import Testing
import VitrineDomain

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

    @Test func rejectsUnknownFieldsWithTheirCompleteJSONPath() throws {
        let data = try WorkspaceRecipeDocument(recipe: sampleRecipe()).jsonData()
        var root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        var recipe = try #require(root["recipe"] as? [String: Any])
        var output = try #require(recipe["output"] as? [String: Any])
        output["colourProfile"] = "sRGB"
        recipe["output"] = output
        root["recipe"] = recipe

        #expect(
            throws: WorkspaceRecipeDocument.ImportError.unknownField(
                "recipe.output.colourProfile")
        ) {
            try WorkspaceRecipeDocument.recipe(
                from: JSONSerialization.data(withJSONObject: root))
        }
    }

    @Test func reportsThePathOfInvalidTypedValues() throws {
        let data = try WorkspaceRecipeDocument(recipe: sampleRecipe()).jsonData()
        var root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        var recipe = try #require(root["recipe"] as? [String: Any])
        var output = try #require(recipe["output"] as? [String: Any])
        output["colorProfile"] = "AdobeRGB"
        recipe["output"] = output
        root["recipe"] = recipe

        #expect(
            throws: WorkspaceRecipeDocument.ImportError.invalidDocument(
                "The field \"recipe.output.colorProfile\" contains an invalid value.")
        ) {
            try WorkspaceRecipeDocument.recipe(
                from: JSONSerialization.data(withJSONObject: root))
        }
    }

    /// Style values are part of the checked contract too: a mistyped value must not
    /// silently fall back to a default the author never chose.
    @Test(arguments: [
        ("fontSize", #""18""#, "has the wrong value type."),
        ("showLineNumbers", #""true""#, "has the wrong value type."),
        ("background", #"{"kind":"gradiant","preset":"Ocean"}"#, "contains an invalid value."),
        ("background", #"{"kind":"gradient","preset":"Ocen"}"#, "contains an invalid value."),
    ])
    func rejectsMistypedStyleValues(_ key: String, _ json: String, _ problem: String) throws {
        let value = try JSONSerialization.jsonObject(
            with: Data(json.utf8), options: .fragmentsAllowed)
        let data = try WorkspaceRecipeDocument(recipe: sampleRecipe()).jsonData()
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var recipe = try #require(root["recipe"] as? [String: Any])
        var style = try #require(recipe["style"] as? [String: Any])
        style[key] = value
        recipe["style"] = style
        root["recipe"] = recipe

        do {
            _ = try WorkspaceRecipeDocument.recipe(
                from: JSONSerialization.data(withJSONObject: root))
            Issue.record("A mistyped \(key) was accepted.")
        } catch let WorkspaceRecipeDocument.ImportError.invalidDocument(message) {
            #expect(message.hasPrefix("The field \"recipe.style.\(key)"))
            #expect(message.hasSuffix(problem))
        }
    }

    /// Presets and preferences keep the tolerant decoder.
    @Test func presetStyleDecodingStaysTolerant() throws {
        let json = #"{"themeID":"dracula","fontSize":"18","background":{"kind":"gradiant"}}"#
        let style = try JSONDecoder().decode(StyleSnapshot.self, from: Data(json.utf8))
        #expect(style.fontSize == SettingsDefaults.fontSize)
        #expect(style.background == .gradient(.aurora))
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
