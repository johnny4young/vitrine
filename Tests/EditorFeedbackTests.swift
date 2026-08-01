import AppKit
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

    private final class PresentationSpy {
        var pinnedImages: [NSImage] = []
        var sharedImages: [NSImage] = []
        var shareAnchors: [NSView] = []

        var presentation: EditorPresentation {
            EditorPresentation(
                presentPin: { [weak self] image in
                    self?.pinnedImages.append(image)
                },
                presentShare: { [weak self] image, view in
                    self?.sharedImages.append(image)
                    self?.shareAnchors.append(view)
                })
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
            feedback: display.display,
            presentation: .noOp)
        defer { session.discard() }
        session.settings.config.theme = .dracula

        session.makeDefault()

        #expect(environment.appSettings.config.theme.id == Theme.dracula.id)
        #expect(
            display.feedback == [
                Notifier.confirmation(String(localized: "Set as the default style"))
            ])
    }

    @Test func appMenuSuppliesFeedbackAndPresentationToEditorCommands() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "VitrineEditorFeedback-\(UUID().uuidString)"))
        let environment = AppEnvironment(defaults: defaults)
        let display = DisplaySpy()
        let presentation = PresentationSpy()
        let presenter = CaptureFeedbackPresenter(display: display.display)
        let menu = AppMenu(
            environment: environment,
            feedback: presenter,
            editorPresentation: presentation.presentation)
        let expected = Notifier.confirmation("Editor feedback")
        let pinnedImage = NSImage(size: NSSize(width: 2, height: 3))
        let sharedImage = NSImage(size: NSSize(width: 4, height: 5))
        let anchor = NSView()

        menu.editorCommands.feedback(expected)
        menu.editorCommands.presentation.pin(pinnedImage)
        menu.editorCommands.presentation.share(sharedImage, relativeTo: anchor)

        #expect(display.feedback == [expected])
        #expect(presentation.pinnedImages.first === pinnedImage)
        #expect(presentation.sharedImages.first === sharedImage)
        #expect(presentation.shareAnchors.first === anchor)
    }

    @Test func windowControllerSuppliesPresentationRoutesToEachSession() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "VitrineEditorFeedback-\(UUID().uuidString)"))
        let environment = AppEnvironment(defaults: defaults)
        let presentation = PresentationSpy()
        let controller = EditorWindowController(
            environment: environment,
            feedback: .noOp,
            presentation: presentation.presentation)
        let session = controller.session(for: .primary)
        defer { session.discard() }
        let pinnedImage = NSImage(size: NSSize(width: 2, height: 3))
        let sharedImage = NSImage(size: NSSize(width: 4, height: 5))
        let anchor = NSView()

        session.presentation.pin(pinnedImage)
        session.presentation.share(sharedImage, relativeTo: anchor)

        #expect(controller.environment === environment)
        #expect(session.environment === environment)
        #expect(presentation.pinnedImages.first === pinnedImage)
        #expect(presentation.sharedImages.first === sharedImage)
        #expect(presentation.shareAnchors.first === anchor)
    }

    @Test func presentationDoesNotShareWithoutAnAnchor() {
        let presentation = PresentationSpy()
        presentation.presentation.share(NSImage(), relativeTo: nil)

        #expect(presentation.sharedImages.isEmpty)
        #expect(presentation.shareAnchors.isEmpty)
    }

    @Test(arguments: [false, true])
    func failedCopyKeepsTheEditorOpen(preferenceEnabled: Bool) {
        #expect(
            !EditorView.shouldCloseAfterCopy(
                copied: false,
                preferenceEnabled: preferenceEnabled))
    }

    @Test(arguments: [false, true])
    func successfulCopyHonorsTheClosePreference(preferenceEnabled: Bool) {
        #expect(
            EditorView.shouldCloseAfterCopy(
                copied: true,
                preferenceEnabled: preferenceEnabled) == preferenceEnabled)
    }

    @Test func editorSurfacesContainNoAppOwnedPresentationLookups() throws {
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

            for forbiddenDependency in [
                "CaptureHUDController.shared",
                "PinnedSnapshotController.shared",
                "ShareManager.share",
                "ExportFeedback.present",
            ] {
                #expect(
                    !code.contains(forbiddenDependency),
                    "\(relativePath) must receive \(forbiddenDependency) as an operation")
            }
            if relativePath == "Vitrine/Editor/EditorView+Toolbar.swift" {
                #expect(
                    !code.contains("NSApp.keyWindow"),
                    "The editor toolbar must use its captured window")
            }
        }
    }
}
