import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Recents gallery composition")
struct RecentsGalleryCompositionTests {
    private final class DisplaySpy {
        var feedback: [Notifier.CaptureFeedback] = []

        var display: FeedbackDisplay {
            FeedbackDisplay { [weak self] feedback, _ in
                self?.feedback.append(feedback)
            }
        }
    }

    private final class NavigationSpy {
        var editorPresentationCount = 0
        var loadedConfigs: [SnapshotConfig] = []
        var comparisonBoards: [[Capture]] = []
        var themeVariants: [Capture] = []

        var navigation: RecentsGalleryNavigation {
            RecentsGalleryNavigation(
                presentEditor: { [weak self] in
                    self?.editorPresentationCount += 1
                },
                loadPrimaryEditor: { [weak self] config in
                    self?.loadedConfigs.append(config)
                },
                presentComparisonBoard: { [weak self] captures in
                    self?.comparisonBoards.append(captures)
                },
                presentThemeVariants: { [weak self] capture in
                    self?.themeVariants.append(capture)
                })
        }
    }

    @Test func controllerSuppliesOneDependencyGraphToItsRoot() throws {
        let defaults = testDefaults()
        let environment = AppEnvironment(defaults: defaults)
        let display = DisplaySpy()
        let navigation = NavigationSpy()
        let controller = RecentsGalleryWindowController(
            environment: environment,
            feedback: display.display,
            navigation: navigation.navigation)

        let root = controller.makeRootView()
        let expectedFeedback = Notifier.confirmation("Recents feedback")
        var config = environment.appSettings.config
        config.code = "print(\"recents\")"
        root.feedback(expectedFeedback)
        root.navigation.showEditor()
        root.navigation.loadIntoPrimaryEditor(config)
        let captures = [
            Capture(code: "before", languageID: "swift", themeID: "one-dark"),
            Capture(code: "after", languageID: "swift", themeID: "one-dark"),
        ]
        root.navigation.showComparisonBoard(captures)
        root.navigation.showThemeVariants(of: captures[1])

        #expect(controller.environment === environment)
        #expect(root.environment === environment)
        #expect(root.recents === environment.recents)
        #expect(root.settings === environment.appSettings)
        #expect(display.feedback == [expectedFeedback])
        #expect(navigation.editorPresentationCount == 1)
        #expect(navigation.loadedConfigs.map(\.code) == ["print(\"recents\")"])
        #expect(navigation.comparisonBoards.map { $0.map(\.code) } == [["before", "after"]])
        #expect(navigation.themeVariants.map(\.code) == ["after"])
    }

    @Test func boardControllerRendersAVariantPerThemeWithTheCaptureThemeFirst() throws {
        let environment = AppEnvironment(defaults: testDefaults())
        let controller = ComparisonBoardWindowController(
            environment: environment, feedback: .noOp, presentation: .noOp)
        let capture = Capture(code: "let x = 1", languageID: "swift", themeID: "nord")

        let draft = try controller.makeVariantDraft(of: capture)

        #expect(
            draft.variants.map(\.theme.id) == [
                "nord", "one-dark", "one-light", "dracula", "github", "github-dark",
            ])
        #expect(draft.items.map(\.label) == ["Nord", "One Dark", "One Light", "Dracula"])
        #expect(draft.items.allSatisfy { $0.asset.pixelWidth > 0 })
        #expect(draft.isValid)
    }

    @Test func galleryViewContainsNoProcessGlobalCompositionLookups() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Vitrine/Recents/RecentsGalleryView.swift"),
            encoding: .utf8)
        let code = sourceCodeWithoutLineComments(source)

        for forbiddenDependency in [
            "AppEnvironment.shared",
            "RecentsStore.shared",
            "AppSettings.shared",
            "EditorWindowController.shared",
            "CaptureHUDController.shared",
            "final class RecentsGalleryWindowController",
        ] {
            #expect(
                !code.contains(forbiddenDependency),
                "RecentsGalleryView must receive \(forbiddenDependency) from its controller")
        }
        let persistentSuiteConstructor = "UserDefaults(" + "suiteName:"
        #expect(code.contains("AppEnvironment(defaults: InMemoryUserDefaults())"))
        #expect(!code.contains(persistentSuiteConstructor))
        #expect(!code.contains("preconditionFailure"))
        #expect(!code.contains("?? UserDefaults()"))
    }
}
