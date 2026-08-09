import Foundation
import Testing

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

        #expect(controller.environment === environment)
        #expect(root.environment === environment)
        #expect(root.recents === environment.recents)
        #expect(root.settings === environment.appSettings)
        #expect(display.feedback == [expectedFeedback])
        #expect(navigation.editorPresentationCount == 1)
        #expect(navigation.loadedConfigs.map(\.code) == ["print(\"recents\")"])
        #expect(navigation.comparisonBoards.map { $0.map(\.code) } == [["before", "after"]])
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
        #expect(code.contains("UUID().uuidString"))
        #expect(!code.contains("?? UserDefaults()"))
    }
}
