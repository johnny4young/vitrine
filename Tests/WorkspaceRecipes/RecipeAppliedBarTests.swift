import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Recipe applied bar")
struct RecipeAppliedBarTests {
    private let recipe = WorkspaceRecipe(
        name: "Docs",
        style: StyleSnapshot(
            themeID: Theme.nord.id, padding: 40, wrapColumns: 72, terminalPalette: .raw,
            background: .gradient(.forest)),
        metadata: .init(windowTitle: "Docs", header: SnapshotMetadata(title: "Header")),
        output: .init(destinationPresetID: "opengraph", scale: 2, format: .pdf))

    // MARK: Counting changes

    @Test func changedFieldsNameOnlyWhatDiffers() {
        let base = recipe.style
        var edited = base
        #expect(edited.changedFields(from: base).isEmpty)

        edited.padding = 64
        edited.themeID = Theme.dracula.id
        edited.wrapColumns = nil
        #expect(edited.changedFields(from: base) == ["padding", "themeID", "wrapColumns"])
        #expect(base.changedFields(from: edited) == ["padding", "themeID", "wrapColumns"])
    }

    @Test func codeEditsAndLanguageSwitchesAreNotStyleChanges() throws {
        let settings = AppSettings(defaults: testDefaults())
        settings.config.language = .swift
        settings.config.terminalPalette = .raw
        let applied = AppliedRecipe(
            associationID: UUID(), name: "Docs", workspaceName: "docs",
            baseline: settings.style, documentGeneration: settings.documentGeneration)

        settings.config.code = "let typed = true"
        settings.config.highlightedLineRanges = [1...1]
        settings.config.language = .terminal
        #expect(applied.changedFields(in: settings.style).isEmpty)

        settings.style.fontSize += 2
        settings.style.showChrome.toggle()
        #expect(applied.changedFields(in: settings.style) == ["fontSize", "showChrome"])
    }

    @Test func revertRestoresTheLookAndKeepsTheDocument() {
        let settings = AppSettings(defaults: testDefaults())
        settings.config.language = .terminal
        settings.config.terminalCursor = .block
        let baseline = settings.style
        let applied = AppliedRecipe(
            associationID: UUID(), name: "Docs", workspaceName: "docs",
            baseline: baseline, documentGeneration: settings.documentGeneration)

        settings.config.code = "echo hi"
        settings.config.highlightedLineRanges = [1...1]
        settings.style.theme = .dracula
        settings.style.padding = baseline.padding + 24
        settings.style.terminalCursor = .bar
        settings.style = applied.reverted(settings.style)

        #expect(applied.changedFields(in: settings.style).isEmpty)
        #expect(settings.style.theme.id == baseline.theme.id)
        #expect(settings.style.terminalCursor == .block)
        #expect(settings.config.code == "echo hi")
        #expect(settings.config.highlightedLineRanges == [1...1])
    }

    // MARK: Writing back

    @Test func savingRewritesOnlyTheChangedFields() throws {
        let original = try WorkspaceRecipeDocument(recipe: recipe).jsonData()
        var edited = recipe.style
        edited.padding = 64
        edited.wrapColumns = nil
        edited.terminalPalette = nil

        let data = try WorkspaceRecipeDocument.updatingStyle(
            in: original, to: edited, fields: ["padding", "wrapColumns"], customTheme: nil)
        let saved = try WorkspaceRecipeDocument.recipe(from: data)

        #expect(saved.style.padding == 64)
        #expect(saved.style.wrapColumns == nil)
        // Not in the changed set, so the file keeps it although `edited` dropped it.
        #expect(saved.style.terminalPalette == .raw)
        #expect(saved.name == recipe.name)
        #expect(saved.metadata == recipe.metadata)
        #expect(saved.output == recipe.output)
        #expect(saved.style.changedFields(from: recipe.style) == ["padding", "wrapColumns"])
    }

    @Test func aThemeChangeEmbedsOrDropsTheCustomPalette() throws {
        let original = try WorkspaceRecipeDocument(recipe: recipe).jsonData()
        let custom = StoredCustomTheme(
            id: "custom.team", name: "Team", palette: ThemeTestFixtures.samplePalette())
        var edited = recipe.style
        edited.themeID = custom.id

        let embedded = try WorkspaceRecipeDocument.updatingStyle(
            in: original, to: edited, fields: ["themeID"], customTheme: custom)
        #expect(try WorkspaceRecipeDocument.recipe(from: embedded).customTheme == custom)

        edited.themeID = Theme.dracula.id
        let builtIn = try WorkspaceRecipeDocument.updatingStyle(
            in: embedded, to: edited, fields: ["themeID"], customTheme: nil)
        let saved = try WorkspaceRecipeDocument.recipe(from: builtIn)
        #expect(saved.customTheme == nil)
        #expect(saved.style.themeID == Theme.dracula.id)
    }

    @Test func aFileThisBuildCannotReadIsNeverRewritten() throws {
        var root = try #require(
            try JSONSerialization.jsonObject(
                with: WorkspaceRecipeDocument(recipe: recipe).jsonData()) as? [String: Any])
        var body = try #require(root["recipe"] as? [String: Any])
        body["futureOption"] = true
        root["recipe"] = body
        let newer = try JSONSerialization.data(withJSONObject: root)

        #expect(throws: WorkspaceRecipeDocument.ImportError.unknownField("recipe.futureOption")) {
            try WorkspaceRecipeDocument.updatingStyle(
                in: newer, to: recipe.style, fields: ["padding"], customTheme: nil)
        }
        #expect(throws: WorkspaceRecipeDocument.ImportError.notARecipeFile) {
            try WorkspaceRecipeDocument.updatingStyle(
                in: Data("[]".utf8), to: recipe.style, fields: ["padding"], customTheme: nil)
        }
    }

    @Test func theStoreReadsTheAssociatedFileForSaving() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "VitrineRecipeBar-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recipeURL = root.appendingPathComponent("docs.vitrine-recipe.json")
        let bytes = try WorkspaceRecipeDocument(recipe: recipe).jsonData()
        try bytes.write(to: recipeURL)
        let store = WorkspaceRecipeStore(defaults: testDefaults())
        let association = try store.associate(workspaceURL: root, recipeURL: recipeURL)

        let file = try store.recipeFile(id: association.id)
        #expect(file.data == bytes)
        #expect(file.url == recipeURL.standardizedFileURL.resolvingSymlinksInPath())
        #expect(throws: WorkspaceRecipeStore.StoreError.associationUnavailable) {
            try store.recipeFile(id: UUID())
        }
    }
}
