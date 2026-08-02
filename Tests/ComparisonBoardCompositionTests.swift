import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Comparison board composition")
struct ComparisonBoardCompositionTests {
    @Test func controllerSuppliesOneDependencyGraphToItsRoot() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "VitrineComparisonComposition-\(UUID().uuidString)"))
        let environment = AppEnvironment(defaults: defaults)
        let feedback = FeedbackDisplay { _, _ in }
        let presentation = ComparisonBoardPresentation.noOp
        let controller = ComparisonBoardWindowController(
            environment: environment,
            feedback: feedback,
            presentation: presentation)
        let captures = [
            Capture(code: "before", languageID: "swift", themeID: "one-dark"),
            Capture(code: "after", languageID: "swift", themeID: "one-dark"),
        ]

        let draft = try controller.makeDraft(captures: captures)
        let root = controller.makeRootView(draft: draft)

        #expect(controller.environment === environment)
        #expect(root.environment === environment)
        #expect(root.draft === draft)
    }

    @Test func editorViewContainsNoProcessGlobalCompositionLookups() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Vitrine/Comparison/ComparisonBoardEditorView.swift"),
            encoding: .utf8)
        let code = sourceCodeWithoutLineComments(source)

        for forbiddenDependency in [
            "AppEnvironment.shared",
            "AppSettings.shared",
            "ComparisonBoardWindowController.shared",
            "CaptureHUDController.shared",
            "NSApp.keyWindow",
        ] {
            #expect(
                !code.contains(forbiddenDependency),
                "ComparisonBoardEditorView must receive \(forbiddenDependency) from its controller")
        }
    }
}
