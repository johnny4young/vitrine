import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Recipe applied bar")
struct RecipeAppliedBarTests {
    private func applied(_ settings: AppSettings) -> AppliedRecipe {
        AppliedRecipe(
            associationID: UUID(), name: "Docs", workspaceName: "docs",
            baseline: settings.style, documentGeneration: settings.documentGeneration)
    }

    @Test func changedFieldsNameOnlyWhatDiffers() {
        let base = StyleSnapshot(
            themeID: Theme.nord.id, padding: 40, wrapColumns: 72, background: .gradient(.forest))
        var edited = base
        #expect(edited.changedFields(from: base).isEmpty)

        edited.padding = 64
        edited.themeID = Theme.dracula.id
        edited.wrapColumns = nil
        #expect(edited.changedFields(from: base) == ["padding", "themeID", "wrapColumns"])
        #expect(base.changedFields(from: edited) == ["padding", "themeID", "wrapColumns"])
    }

    @Test func codeEditsAndLanguageSwitchesAreNotStyleChanges() {
        let settings = AppSettings(defaults: testDefaults())
        settings.config.language = .swift
        settings.config.terminalPalette = .raw
        let recipe = applied(settings)

        settings.config.code = "let typed = true"
        settings.config.highlightedLineRanges = [1...1]
        settings.config.language = .terminal
        #expect(recipe.changedFields(in: settings.style).isEmpty)

        settings.style.fontSize += 2
        settings.style.showChrome.toggle()
        #expect(recipe.changedFields(in: settings.style) == ["fontSize", "showChrome"])
    }

    @Test func anImageBackgroundIsCountedAndRevertedAsItIs() {
        let settings = AppSettings(defaults: testDefaults())
        let image = VitrineDomain.BackgroundStyle.image(
            ImageBackground(reference: ImageReference(fileName: "team.png")))
        settings.style.background = image
        let recipe = applied(settings)
        #expect(recipe.changedFields(in: settings.style).isEmpty)

        settings.style.background = .gradient(.forest)
        #expect(recipe.changedFields(in: settings.style) == ["background"])
        AppliedRecipe.restore(
            AppliedRecipe.Look(recipe.baseline), to: settings, undoManager: nil)
        #expect(settings.style.background == image)
    }

    @Test func revertRestoresTheLookAndKeepsTheDocument() {
        let settings = AppSettings(defaults: testDefaults())
        settings.config.language = .terminal
        settings.config.terminalCursor = .block
        let recipe = applied(settings)

        settings.config.code = "echo hi"
        settings.config.highlightedLineRanges = [1...1]
        settings.style.theme = .dracula
        settings.style.padding = recipe.baseline.padding + 24
        settings.style.terminalCursor = .bar
        AppliedRecipe.restore(
            AppliedRecipe.Look(recipe.baseline), to: settings, undoManager: nil)

        #expect(recipe.changedFields(in: settings.style).isEmpty)
        #expect(settings.style.theme.id == recipe.baseline.theme.id)
        #expect(settings.style.terminalCursor == .block)
        #expect(settings.config.code == "echo hi")
        #expect(settings.config.highlightedLineRanges == [1...1])
    }

    @Test func undoingARevertKeepsARedactionAddedAfterIt() {
        let settings = AppSettings(defaults: testDefaults())
        settings.config.code = "let token = 1\nlet other = 2"
        let recipe = applied(settings)
        let edited = recipe.baseline.padding + 24
        settings.style.padding = edited
        let undo = UndoManager()
        undo.groupsByEvent = false

        undo.beginUndoGrouping()
        AppliedRecipe.restore(
            AppliedRecipe.Look(recipe.baseline), to: settings, undoManager: undo)
        undo.endUndoGrouping()
        settings.style.redactedLineRanges = [1...1]

        undo.undo()
        #expect(settings.style.padding == edited)
        #expect(settings.style.redactedLineRanges == [1...1])
        undo.redo()
        #expect(settings.style.padding == recipe.baseline.padding)
        #expect(settings.style.redactedLineRanges == [1...1])
    }

    @Test func aLiveRefreshOfTheSameFileKeepsTheBar() {
        let environment = AppEnvironment(defaults: testDefaults())
        let settings = AppSettings(defaults: testDefaults())
        let session = EditorSession(
            identity: EditorWindowIdentity(index: 71), environment: environment,
            feedback: .noOp, presentation: .noOp, settings: settings)
        session.appliedRecipe = applied(settings)

        let refreshed = settings.documentGeneration
        settings.noteDocumentReplaced()
        session.livingSnapshot.onRefresh?(refreshed)
        #expect(session.appliedRecipe?.documentGeneration == settings.documentGeneration)

        // Another document replaced it first, so a later refresh doesn't bring the bar back.
        let replaced = settings.documentGeneration
        settings.noteDocumentReplaced()
        settings.noteDocumentReplaced()
        session.livingSnapshot.onRefresh?(settings.documentGeneration - 1)
        #expect(session.appliedRecipe?.documentGeneration == replaced)
    }
}
