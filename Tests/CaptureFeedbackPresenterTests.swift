import Foundation
import Testing
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Capture feedback presenter", .serialized)
struct CaptureFeedbackPresenterTests {
    private final class DisplaySpy {
        var feedback: [Notifier.CaptureFeedback] = []
        var actionHandler: ((Notifier.RecoveryAction) -> Void)?

        var port: FeedbackDisplay {
            FeedbackDisplay { [weak self] feedback, onAction in
                self?.feedback.append(feedback)
                self?.actionHandler = onAction
            }
        }
    }

    private final class RoutingSpy {
        var loadedConfigs: [SnapshotConfig] = []
        var editorPresentations = 0
        var webSnapshotURLs: [String?] = []

        var port: CaptureRecoveryRouting {
            CaptureRecoveryRouting(
                loadPrimaryEditor: { [weak self] in self?.loadedConfigs.append($0) },
                presentEditor: { [weak self] in self?.editorPresentations += 1 },
                presentWebSnapshot: { [weak self] in self?.webSnapshotURLs.append($0) })
        }
    }

    private func makeEnvironment() -> AppEnvironment {
        AppEnvironment(defaults: testDefaults())
    }

    @Test func presentsFeedbackAndRoutesOpenEditorThroughInjectedPorts() throws {
        let environment = makeEnvironment()
        environment.appSettings.config.code = "let answer = 42"
        let display = DisplaySpy()
        let routing = RoutingSpy()
        let presenter = CaptureFeedbackPresenter(
            display: display.port, routing: routing.port)

        presenter.present(.nonProducing(.empty), environment: environment)

        #expect(display.feedback == [Notifier.feedback(for: .empty)])
        #expect(presenter.lastFeedback == Notifier.feedback(for: .empty))
        let action = try #require(display.actionHandler)
        action(.openEditor)
        #expect(routing.editorPresentations == 1)
        #expect(routing.loadedConfigs.isEmpty)
    }

    @Test func urlFeedbackRoutesNowhere() {
        let environment = makeEnvironment()
        let display = DisplaySpy()
        let routing = RoutingSpy()
        let presenter = CaptureFeedbackPresenter(
            display: display.port, routing: routing.port)

        presenter.present(.nonProducing(.url("https://vitrineframe.app")), environment: environment)

        #expect(presenter.lastFeedback?.actions.isEmpty == true)
        #expect(routing.webSnapshotURLs.isEmpty)
    }

    @Test func resolvedFeedbackUpdatesTheHUDAndRetainedPanelStatus() {
        let display = DisplaySpy()
        let routing = RoutingSpy()
        let presenter = CaptureFeedbackPresenter(
            display: display.port,
            routing: routing.port)
        let feedback = Notifier.confirmation("Source copied")

        presenter.present(feedback)

        #expect(display.feedback == [feedback])
        #expect(presenter.lastFeedback == feedback)
        #expect(routing.loadedConfigs.isEmpty)
        #expect(routing.editorPresentations == 0)
        #expect(routing.webSnapshotURLs.isEmpty)
    }

    @Test func coordinatorContainsNoWindowSingletonReads() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Vitrine/Feedback/CaptureFeedbackPresenter.swift"),
            encoding: .utf8)
        let code = sourceCodeWithoutLineComments(source)

        for forbiddenDependency in [
            "CaptureHUDController.shared",
            "EditorWindowController.shared",
            "WebSnapshotWindowController.shared",
        ] {
            #expect(
                !code.contains(forbiddenDependency),
                "CaptureFeedbackPresenter must receive \(forbiddenDependency) as an operation")
        }
    }
}
