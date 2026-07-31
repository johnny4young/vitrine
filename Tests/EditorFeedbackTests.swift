import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Editor feedback composition")
struct EditorFeedbackTests {
    private final class DisplaySpy {
        var feedback: [Notifier.CaptureFeedback] = []

        var display: FeedbackDisplay {
            FeedbackDisplay { [weak self] feedback, _ in
                self?.feedback.append(feedback)
            }
        }
    }

    @Test func editorSessionUsesTheInjectedDisplayWhenPromotingItsStyle() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "VitrineEditorFeedback-\(UUID().uuidString)"))
        let environment = AppEnvironment(defaults: defaults)
        let display = DisplaySpy()
        let session = EditorSession(
            identity: .primary,
            environment: environment,
            feedback: display.display)
        defer { session.discard() }
        session.settings.config.theme = .dracula

        session.makeDefault()

        #expect(environment.appSettings.config.theme.id == Theme.dracula.id)
        #expect(
            display.feedback == [
                Notifier.confirmation(String(localized: "Set as the default style"))
            ])
    }

    @Test func appMenuSuppliesThePresentersDisplayToEditorCommands() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "VitrineEditorFeedback-\(UUID().uuidString)"))
        let environment = AppEnvironment(defaults: defaults)
        let display = DisplaySpy()
        let presenter = CaptureFeedbackPresenter(display: display.display)
        let menu = AppMenu(environment: environment, feedback: presenter)
        let expected = Notifier.confirmation("Editor feedback")

        menu.editorCommands.feedback(expected)

        #expect(display.feedback == [expected])
    }

    @Test func editorSurfacesContainNoHUDGlobalLookups() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for relativePath in [
            "Vitrine/App/EditorCommandResponder.swift",
            "Vitrine/App/EditorWindowController.swift",
            "Vitrine/Editor/EditorView+Stage.swift",
            "Vitrine/Editor/EditorView+Toolbar.swift",
        ] {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8)
            let code = sourceCodeWithoutLineComments(source)

            #expect(
                !code.contains("CaptureHUDController.shared"),
                "\(relativePath) must receive transient feedback as an operation")
        }
    }
}
