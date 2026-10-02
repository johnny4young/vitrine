import CoreGraphics
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Workspace recipe app application")
struct WorkspaceRecipeApplicationTests {
    @Test func currentSettingsExportOnlyPortablePresentationAndOutput() throws {
        let defaults = try isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.config.code = "let secret = \"never exported\""
        settings.config.language = .swift
        settings.config.annotations = [
            Annotation(kind: .text, start: .zero, end: .zero, text: "Review")
        ]
        settings.config.metadata = SnapshotMetadata(
            filename: "/Users/example/private/Main.swift", title: "Docs")
        settings.config.theme = .nord
        settings.export.scale = 3
        settings.export.format = .pdf
        settings.export.colorProfile = .displayP3

        let recipe = settings.workspaceRecipe(named: "Documentation")
        let json = try #require(
            String(
                data: WorkspaceRecipeDocument(recipe: recipe).jsonData(), encoding: .utf8))

        #expect(recipe.name == "Documentation")
        #expect(recipe.metadata.header.filename == "Main.swift")
        #expect(recipe.output.scale == 3)
        #expect(recipe.output.format == .pdf)
        #expect(recipe.output.colorProfile == .displayP3)
        #expect(!json.contains("never exported"))
        #expect(!json.contains("/Users/example/private"))
        #expect(!json.contains("annotations"))
    }

    @Test func applicationPreservesDocumentAndKeepsDestinationSizing() throws {
        let settings = AppSettings(defaults: try isolatedDefaults())
        settings.config.code = "let value = 42"
        settings.config.language = .swift
        settings.config.annotations = [
            Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 0.5, y: 0.5))
        ]
        let recipe = WorkspaceRecipe(
            name: "OpenGraph",
            style: StyleSnapshot(
                themeID: Theme.nord.id, padding: 18,
                background: .gradient(.forest)),
            metadata: .init(
                windowTitle: "Vitrine",
                header: SnapshotMetadata(title: "Workspace", showLanguageBadge: true)),
            output: .init(
                destinationPresetID: "opengraph", scale: 1, format: .png,
                colorProfile: .sRGB))

        let ignoredCanvas = settings.applyWorkspaceRecipe(recipe, themes: CustomThemeStore(defaults: testDefaults()))

        #expect(!ignoredCanvas)
        #expect(settings.config.code == "let value = 42")
        #expect(settings.config.language == .swift)
        #expect(settings.config.annotations.count == 1)
        #expect(settings.config.theme.id == Theme.nord.id)
        #expect(settings.config.padding == 18)
        #expect(settings.config.windowTitle == "Vitrine")
        #expect(settings.config.metadata.title == "Workspace")
        #expect(settings.selectedPresetID == "opengraph")
        #expect(settings.effectiveFixedSize == ExportPreset.openGraph.sizing.fixedSize)
    }

    @Test func customCanvasBoundaryIsReportedRatherThanImplied() throws {
        let settings = AppSettings(defaults: try isolatedDefaults())
        let recipe = WorkspaceRecipe(
            name: "Custom canvas",
            style: StyleSnapshot(
                themeID: Theme.nord.id, background: .gradient(.forest)),
            output: .init(canvasSize: .init(width: 900, height: 500)))

        #expect(settings.applyWorkspaceRecipe(recipe, themes: CustomThemeStore(defaults: testDefaults())))
        #expect(settings.selectedPresetID == nil)
    }

    @Test func destinationRecommendedScaleIsUsedWhenRecipeOmitsScale() throws {
        let settings = AppSettings(defaults: try isolatedDefaults())
        settings.export.scale = 3
        let recipe = WorkspaceRecipe(
            name: "OpenGraph",
            style: StyleSnapshot(
                themeID: Theme.nord.id, background: .gradient(.forest)),
            output: .init(destinationPresetID: ExportPreset.openGraph.id))

        settings.applyWorkspaceRecipe(recipe, themes: CustomThemeStore(defaults: testDefaults()))

        #expect(settings.export.scale == ExportPreset.openGraph.scale)
    }

    @Test func embeddedCustomThemeSurvivesNewWindowsAndRelaunch() throws {
        let defaults = try isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        let themes = CustomThemeStore(defaults: defaults)
        let palette = ThemeTestFixtures.samplePalette()
        let embedded = StoredCustomTheme(id: "custom.teammate", name: "Team", palette: palette)
        let recipe = WorkspaceRecipe(
            name: "Team",
            style: StyleSnapshot(themeID: embedded.id, background: .gradient(.forest)),
            customTheme: embedded)

        settings.applyWorkspaceRecipe(recipe, themes: themes)
        settings.applyWorkspaceRecipe(recipe, themes: themes)

        #expect(settings.config.theme.id == embedded.id)
        #expect(themes.customThemes.map(\.id) == [embedded.id])
        let relaunched = AppSettings(defaults: defaults)
        #expect(relaunched.config.theme.id == embedded.id)
        #expect(relaunched.config.theme.palette == palette)
    }

    @Test func embeddedThemeNeverReplacesADifferentLocalTheme() throws {
        let defaults = try isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        let themes = CustomThemeStore(defaults: defaults)
        let local = themes.addTheme(named: "Local", palette: ThemeTestFixtures.samplePalette())
        var other = ThemeTestFixtures.samplePalette()
        other.background = HexColor("#FFFFFF")!
        let recipe = WorkspaceRecipe(
            name: "Collision",
            style: StyleSnapshot(themeID: local.id, background: .gradient(.forest)),
            customTheme: StoredCustomTheme(id: local.id, name: "Remote", palette: other))

        settings.applyWorkspaceRecipe(recipe, themes: themes)

        #expect(themes.theme(withID: local.id).palette == ThemeTestFixtures.samplePalette())
        #expect(settings.config.theme.id != local.id)
        #expect(settings.config.theme.palette == other)
    }

    @Test func appExportCannotWriteARecipeThatImportWouldReject() throws {
        let settings = AppSettings(defaults: try isolatedDefaults())
        let document = WorkspaceRecipeDocument(recipe: settings.workspaceRecipe(named: "   "))

        #expect(
            throws: WorkspaceRecipeDocument.ImportError.invalid(.emptyName)
        ) {
            try document.validatedJSONData()
        }
    }

    private func isolatedDefaults() throws -> UserDefaults {
        testDefaults()
    }
}
