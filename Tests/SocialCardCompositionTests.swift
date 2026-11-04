import AppKit
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

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

    @Test func useEditorCodeCopiesTheInjectedDocument() throws {
        let environment = AppEnvironment(defaults: testDefaults())
        let editor = environment.makeEditorSessionSettings()
        defer { editor.discardEphemeralStore() }
        editor.documentCode = "print(1)"
        editor.style.language = .python
        environment.appSettings.documentCode = "stale app-wide document"
        let root = SocialCardEditorView(
            environment: environment, feedback: .noOp, presentation: .noOp,
            editorDocument: { editor })

        root.useEditorCode()

        #expect(environment.appSettings.socialCard.codeExcerpt == "print(1)")
        #expect(environment.appSettings.socialCard.language == .python)
    }

    @Test(arguments: ["", "  \n\t\n"])
    func useEditorCodeKeepsTheExcerptWhenTheEditorIsBlank(code: String) throws {
        let environment = AppEnvironment(defaults: testDefaults())
        environment.appSettings.socialCard.codeExcerpt = "keep me"
        let editor = environment.makeEditorSessionSettings()
        defer { editor.discardEphemeralStore() }
        editor.documentCode = code
        let display = DisplaySpy()
        let root = SocialCardEditorView(
            environment: environment, feedback: display.display, presentation: .noOp,
            editorDocument: { editor })

        root.useEditorCode()

        #expect(environment.appSettings.socialCard.codeExcerpt == "keep me")
        #expect(display.feedback.count == 1)
    }

    @Test func useEditorCodeNeverCopiesARedactedLine() throws {
        let environment = AppEnvironment(defaults: testDefaults())
        let editor = environment.makeEditorSessionSettings()
        defer { editor.discardEphemeralStore() }
        var config = editor.config
        config.code = "let visible = 1\nlet secret = 2"
        config.redactedLineRanges = [2...2]
        editor.config = config
        let root = SocialCardEditorView(
            environment: environment, feedback: .noOp, presentation: .noOp,
            editorDocument: { editor })

        root.useEditorCode()

        let excerpt = environment.appSettings.socialCard.codeExcerpt
        #expect(excerpt.contains("visible"))
        #expect(!excerpt.contains("secret"))
    }

    @Test func useEditorCodeNormalizesLikeTheCardModel() throws {
        let environment = AppEnvironment(defaults: testDefaults())
        let editor = environment.makeEditorSessionSettings()
        defer { editor.discardEphemeralStore() }
        let long = (1...40).map { "    line \($0)" }.joined(separator: "\n")
        editor.documentCode = long
        let root = SocialCardEditorView(
            environment: environment, feedback: .noOp, presentation: .noOp,
            editorDocument: { editor })

        root.useEditorCode()

        #expect(
            environment.appSettings.socialCard.codeExcerpt
                == SocialCardModel.truncatedExcerpt(long))
    }

    @Test func useEditorCodeStripsTerminalEscapesAndPlainsTheLanguage() throws {
        let environment = AppEnvironment(defaults: testDefaults())
        let editor = environment.makeEditorSessionSettings()
        defer { editor.discardEphemeralStore() }
        editor.documentCode = "\u{1B}[32mready\u{1B}[0m"
        editor.style.language = .terminal
        let root = SocialCardEditorView(
            environment: environment, feedback: .noOp, presentation: .noOp,
            editorDocument: { editor })

        root.useEditorCode()

        #expect(environment.appSettings.socialCard.codeExcerpt == "ready")
        #expect(environment.appSettings.socialCard.language == .plaintext)
    }

    @Test func useEditorCodeCanBeUndone() throws {
        let environment = AppEnvironment(defaults: testDefaults())
        environment.appSettings.socialCard.codeExcerpt = "original"
        environment.appSettings.socialCard.language = .ruby
        let editor = environment.makeEditorSessionSettings()
        defer { editor.discardEphemeralStore() }
        editor.documentCode = "print(1)"
        editor.style.language = .python
        let root = SocialCardEditorView(
            environment: environment, feedback: .noOp, presentation: .noOp,
            editorDocument: { editor })
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()

        root.useEditorCode(undoManager: undo)
        undo.endUndoGrouping()
        #expect(environment.appSettings.socialCard.codeExcerpt == "print(1)")

        undo.undo()
        #expect(environment.appSettings.socialCard.codeExcerpt == "original")
        #expect(environment.appSettings.socialCard.language == .ruby)
    }

    @Test func frontmostDocumentPrefersThePrimaryDraftOverTheAppWideDocument() throws {
        let environment = AppEnvironment(defaults: testDefaults())
        let controller = EditorWindowController(
            environment: environment, feedback: .noOp, presentation: .noOp)

        #expect(controller.frontmostDocument === environment.appSettings)

        let primary = controller.session(for: .primary)
        defer { primary.discard() }
        #expect(controller.frontmostDocument === primary.settings)
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
