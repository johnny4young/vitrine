import CoreGraphics
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Workspace recipe gallery")
struct RecipeGalleryTests {
    @Test func chipsUseTheRecipeFilesOwnValues() {
        let recipe = WorkspaceRecipe(
            name: "Release notes",
            style: StyleSnapshot(themeID: Theme.dracula.id, background: .gradient(.sunset)),
            output: .init(
                destinationPresetID: "opengraph", canvasSize: .init(width: 1600, height: 900),
                scale: 2, format: .pdf, colorProfile: .displayP3))
        #expect(
            RecipeGalleryModel.chips(for: recipe) == [
                "dracula", "opengraph", "1600×900", "pdf", "displayP3", "2×",
            ])

        let bare = WorkspaceRecipe(
            name: "Bare", style: StyleSnapshot(themeID: Theme.nord.id, background: .transparent))
        #expect(RecipeGalleryModel.chips(for: bare) == ["nord"])
    }

    @Test func previewsShareTheSnippetAndTakeTheRecipesStyle() {
        let custom = StoredCustomTheme(
            id: "custom.gallery", name: "Gallery", palette: ThemeTestFixtures.samplePalette())
        let recipe = WorkspaceRecipe(
            name: "Custom",
            style: StyleSnapshot(themeID: custom.id, padding: 24, background: .gradient(.forest)),
            customTheme: custom)
        let config = RecipeGalleryModel.previewConfig(for: recipe)

        #expect(config.code == EditorPreview.sampleCode)
        #expect(config.language == .swift)
        #expect(config.theme.id == custom.id)
        #expect(config.padding == 24)
        #expect(config.background == .gradient(.forest))
    }

    @Test func nestedFoldersNameWhichRecipeWins() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = WorkspaceRecipeStore(defaults: testDefaults())
        let parent = try store.associate(
            workspaceURL: try fixture.folder("app"),
            recipeURL: try fixture.recipe("parent.json", name: "PR review"))
        let nested = try store.associate(
            workspaceURL: try fixture.folder("app/docs"),
            recipeURL: try fixture.recipe("docs.json", name: "Documentation"))
        let deeper = try store.associate(
            workspaceURL: try fixture.folder("app/docs/api"),
            recipeURL: try fixture.recipe("api.json", name: "API"))
        let sibling = try store.associate(
            workspaceURL: try fixture.folder("notes"),
            recipeURL: try fixture.recipe("notes.json", name: "Notes"))

        #expect(
            store.enclosingAssociationIDs() == [nested.id: parent.id, deeper.id: nested.id])

        let model = RecipeGalleryModel(render: { _ in nil })
        model.reload(from: store)
        let cards = Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0) })
        #expect(model.cards.map(\.name) == ["PR review", "Documentation", "API", "Notes"])
        #expect(cards[parent.id]?.overrides == nil)
        #expect(cards[parent.id]?.nested == ["Documentation"])
        #expect(cards[nested.id]?.overrides == "PR review")
        #expect(cards[nested.id]?.nested == ["API"])
        #expect(cards[sibling.id]?.overrides == nil)
        #expect(cards[sibling.id]?.nested == [])
    }

    @Test func aMissingRecipeFileShowsUnavailableAndRendersNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = WorkspaceRecipeStore(defaults: testDefaults())
        let file = try fixture.recipe("gone.json", name: "Gone")
        try store.associate(workspaceURL: try fixture.folder("app"), recipeURL: file)
        try FileManager.default.removeItem(at: file)

        var renders = 0
        let model = RecipeGalleryModel(frameGap: .zero) { _ in
            renders += 1
            return nil
        }
        model.reload(from: store)
        await model.renderPreviews()

        #expect(model.cards.first?.recipe == nil)
        #expect(model.cards.first?.name == "gone.json")
        #expect(renders == 0)
    }

    @Test func previewsRenderOncePerChangedRecipe() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = WorkspaceRecipeStore(defaults: testDefaults())
        let first = try fixture.recipe("first.json", name: "First")
        let association = try store.associate(
            workspaceURL: try fixture.folder("first"), recipeURL: first)
        try store.associate(
            workspaceURL: try fixture.folder("second"),
            recipeURL: try fixture.recipe("second.json", name: "Second"))

        var rendered: [String] = []
        let image = try #require(Self.pixel())
        let model = RecipeGalleryModel(frameGap: .zero) { config in
            rendered.append(config.theme.id)
            return image
        }
        model.reload(from: store)
        await model.renderPreviews()
        #expect(rendered.count == 2)
        #expect(model.images.count == 2)

        model.reload(from: store)
        await model.renderPreviews()
        #expect(rendered.count == 2)

        let restyled = WorkspaceRecipe(
            name: "First",
            style: StyleSnapshot(themeID: Theme.dracula.id, background: .gradient(.night)))
        try WorkspaceRecipeDocument(recipe: restyled).jsonData().write(to: first)
        model.reload(from: store)
        await model.renderPreviews()
        #expect(rendered == [Theme.nord.id, Theme.nord.id, Theme.dracula.id])

        #expect(store.remove(id: association.id))
        model.reload(from: store)
        await model.renderPreviews()
        #expect(model.images.count == 1)
        #expect(model.images[association.id] == nil)
    }

    private static func pixel() -> CGImage? {
        CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }

    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "VitrineRecipeGallery-\(UUID().uuidString)", isDirectory: true)

        init() throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func folder(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func recipe(_ filename: String, name: String) throws -> URL {
            let url = root.appendingPathComponent(filename)
            let recipe = WorkspaceRecipe(
                name: name,
                style: StyleSnapshot(themeID: Theme.nord.id, background: .gradient(.forest)))
            try WorkspaceRecipeDocument(recipe: recipe).jsonData().write(to: url)
            return url
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
