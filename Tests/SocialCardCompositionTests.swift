import AppKit
import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Social card composition")
struct SocialCardCompositionTests {
    private final class DisplaySpy {
        var feedback: [Notifier.CaptureFeedback] = []

        var display: FeedbackDisplay {
            FeedbackDisplay { [weak self] feedback, _ in
                self?.feedback.append(feedback)
            }
        }
    }

    private final class PresentationSpy {
        var sharedImages: [NSImage] = []

        var presentation: SocialCardPresentation {
            SocialCardPresentation { [weak self] image in
                self?.sharedImages.append(image)
            }
        }
    }

    @Test func controllerSuppliesOneDependencyGraphToItsRoot() throws {
        let defaults = testDefaults()
        let environment = AppEnvironment(defaults: defaults)
        let display = DisplaySpy()
        let presentation = PresentationSpy()
        let controller = SocialCardWindowController(
            environment: environment,
            feedback: display.display,
            presentation: presentation.presentation)

        let root = controller.makeRootView()
        let expectedFeedback = Notifier.confirmation("Card feedback")
        let expectedImage = NSImage(size: NSSize(width: 1, height: 1))
        root.feedback(expectedFeedback)
        root.presentation.share(expectedImage)

        #expect(controller.environment === environment)
        #expect(root.environment === environment)
        #expect(root.settings === environment.appSettings)
        #expect(root.themes === environment.customThemes)
        #expect(root.brandKit === environment.brandKit)
        #expect(root.entitlements === environment.entitlements)
        #expect(display.feedback == [expectedFeedback])
        #expect(presentation.sharedImages.count == 1)
        #expect(presentation.sharedImages.first === expectedImage)
    }

    @Test func shareActionUsesTheInjectedPresentation() throws {
        let defaults = testDefaults()
        let environment = AppEnvironment(defaults: defaults)
        environment.appSettings.socialCard = SocialCardModel(title: "Share this card")
        environment.appSettings.export.scale = 1
        let presentation = PresentationSpy()
        let root = SocialCardEditorView(
            environment: environment,
            feedback: .noOp,
            presentation: presentation.presentation)

        root.shareCard()

        #expect(presentation.sharedImages.map(\.size) == [NSSize(width: 1200, height: 630)])
    }

    @Test func failedShareUsesTheInjectedFeedback() throws {
        let defaults = testDefaults()
        let environment = AppEnvironment(defaults: defaults)
        let display = DisplaySpy()
        let presentation = PresentationSpy()
        let root = SocialCardEditorView(
            environment: environment,
            feedback: display.display,
            presentation: presentation.presentation)

        root.shareCard()

        #expect(display.feedback == [ExportFeedback.renderFailure(.encodingFailed)])
        #expect(presentation.sharedImages.isEmpty)
    }

    @Test func editorAndRendererContainNoAppOwnedPresentationGlobals() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for relativePath in [
            "Vitrine/SocialCards/SocialCardEditorView.swift",
            "Vitrine/SocialCards/SocialCardRenderer.swift",
        ] {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8)
            let code = sourceCodeWithoutLineComments(source)

            for forbiddenDependency in [
                "AppEnvironment.shared",
                "CaptureHUDController.shared",
                "NSApp.keyWindow",
                "ShareManager.share",
                "ExportFeedback.present",
                "SocialCardRenderer.share",
            ] {
                #expect(
                    !code.contains(forbiddenDependency),
                    "\(relativePath) must receive \(forbiddenDependency) from its controller")
            }
        }
    }
}
