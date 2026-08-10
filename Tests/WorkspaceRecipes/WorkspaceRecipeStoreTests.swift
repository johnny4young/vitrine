import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Workspace recipe associations")
struct WorkspaceRecipeStoreTests {
    @Test func associationPersistsAsBookmarksAndResolvesExplicitFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let defaults = try fixture.defaults()
        let store = WorkspaceRecipeStore(defaults: defaults)
        let recipeURL = try fixture.writeRecipe(named: "docs.json", recipeName: "Docs")

        let association = try store.associate(
            workspaceURL: fixture.workspace, recipeURL: recipeURL)
        let source = try fixture.writeSource("Sources/Feature.swift")

        #expect(association.workspaceName == fixture.workspace.lastPathComponent)
        #expect(association.recipeFilename == "docs.json")
        #expect(store.resolvedRecipe(for: source)?.recipe.name == "Docs")

        let reloaded = WorkspaceRecipeStore(defaults: defaults)
        #expect(reloaded.associations.count == 1)
        #expect(reloaded.resolvedRecipe(for: source)?.association.id == association.id)
        let persisted = try #require(defaults.data(forKey: WorkspaceRecipeStore.storageKey))
        let json = try #require(String(data: persisted, encoding: .utf8))
        #expect(!json.contains(fixture.root.path))
        #expect(!json.contains("workspacePath"))
    }

    @Test func nestedWorkspaceWinsAndUnavailableAssociationsFallBack() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = WorkspaceRecipeStore(defaults: try fixture.defaults())
        let parentRecipe = try fixture.writeRecipe(named: "parent.json", recipeName: "Parent")
        let nestedRecipe = try fixture.writeRecipe(named: "nested.json", recipeName: "Nested")
        let nested = fixture.workspace.appendingPathComponent("Packages/App", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try store.associate(workspaceURL: fixture.workspace, recipeURL: parentRecipe)
        let nestedAssociation = try store.associate(
            workspaceURL: nested, recipeURL: nestedRecipe)
        let source = try fixture.writeSource("Packages/App/Sources/Main.swift")

        #expect(store.resolvedRecipe(for: source)?.recipe.name == "Nested")
        try FileManager.default.removeItem(at: nestedRecipe)
        #expect(store.resolvedRecipe(for: source)?.recipe.name == "Parent")
        #expect(store.remove(id: nestedAssociation.id))
        #expect(store.associations.count == 1)
    }

    @Test func reassociatingAWorkspaceReplacesInsteadOfDuplicating() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = WorkspaceRecipeStore(defaults: try fixture.defaults())
        let firstRecipe = try fixture.writeRecipe(named: "first.json", recipeName: "First")
        let secondRecipe = try fixture.writeRecipe(named: "second.json", recipeName: "Second")

        let first = try store.associate(
            workspaceURL: fixture.workspace, recipeURL: firstRecipe)
        let second = try store.associate(
            workspaceURL: fixture.workspace, recipeURL: secondRecipe)

        #expect(store.associations.count == 1)
        #expect(second.id == first.id)
        #expect(try store.resolvedRecipe(id: first.id).recipe.name == "Second")
    }

    @Test func invalidInputsDoNotMutateTheStore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = WorkspaceRecipeStore(defaults: try fixture.defaults())
        let source = try fixture.writeSource("not-a-folder.swift")
        let recipeURL = try fixture.writeRecipe(named: "valid.json", recipeName: "Valid")

        #expect(throws: WorkspaceRecipeStore.StoreError.workspaceIsNotFolder) {
            try store.associate(workspaceURL: source, recipeURL: recipeURL)
        }

        let invalidRecipe = fixture.root.appendingPathComponent("invalid.json")
        try Data("{}".utf8).write(to: invalidRecipe)
        #expect(
            throws: WorkspaceRecipeStore.StoreError.recipe(
                .invalid(.notARecipeFile))
        ) {
            try store.associate(
                workspaceURL: fixture.workspace, recipeURL: invalidRecipe)
        }
        #expect(store.associations.isEmpty)
    }

    @Test func explicitFileApplicationChangesPresentationWithoutTouchingSource() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let defaults = try fixture.defaults()
        let store = WorkspaceRecipeStore(defaults: defaults)
        let recipe = WorkspaceRecipe(
            name: "Workspace",
            style: StyleSnapshot(
                themeID: Theme.nord.id, padding: 48,
                background: .gradient(.forest)),
            metadata: .init(
                header: SnapshotMetadata(title: "Repository", caption: "Local recipe")),
            output: .init(format: .pdf, colorProfile: .displayP3))
        let recipeURL = try fixture.writeRecipe(named: "workspace.json", recipe: recipe)
        try store.associate(workspaceURL: fixture.workspace, recipeURL: recipeURL)
        let source = try fixture.writeSource("Sources/Main.swift")
        let settings = AppSettings(defaults: defaults)
        settings.config.code = "let original = true"
        settings.config.language = .swift

        let resolved = store.applyRecipe(for: source, to: settings)

        #expect(resolved?.recipe.name == "Workspace")
        #expect(settings.config.code == "let original = true")
        #expect(settings.config.language == .swift)
        #expect(settings.config.theme.id == Theme.nord.id)
        #expect(settings.config.padding == 48)
        #expect(settings.config.metadata.title == "Repository")
        #expect(settings.export.format == .pdf)
        #expect(settings.export.colorProfile == .displayP3)
    }

    private struct Fixture {
        let root: URL
        let workspace: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "VitrineWorkspaceRecipes-\(UUID().uuidString)", isDirectory: true)
            workspace = root.appendingPathComponent("Example", isDirectory: true)
            try FileManager.default.createDirectory(
                at: workspace, withIntermediateDirectories: true)
        }

        func defaults() throws -> UserDefaults {
            testDefaults()
        }

        func writeRecipe(named filename: String, recipeName: String) throws -> URL {
            try writeRecipe(
                named: filename,
                recipe: WorkspaceRecipe(
                    name: recipeName,
                    style: StyleSnapshot(
                        themeID: Theme.nord.id, background: .gradient(.forest))))
        }

        func writeRecipe(named filename: String, recipe: WorkspaceRecipe) throws -> URL {
            let url = root.appendingPathComponent(filename)
            try WorkspaceRecipeDocument(recipe: recipe).jsonData().write(to: url)
            return url
        }

        func writeSource(_ relativePath: String) throws -> URL {
            let url = workspace.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("let value = 42\n".utf8).write(to: url)
            return url
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
