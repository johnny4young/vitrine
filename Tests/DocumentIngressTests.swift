import AppKit
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Document ingress")
struct DocumentIngressTests {
    private func markedDocument() -> SnapshotConfig {
        var config = SnapshotConfig(code: "old\nsource", language: .python)
        config.fontSize = 19
        config.padding = 37
        config.metadata.title = "Reusable title"
        config.annotations = [Annotation(kind: .blur, start: .zero, end: CGPoint(x: 1, y: 1))]
        config.highlightedLineRanges = [1...1]
        config.redactedLineRanges = [1...1]
        config.foregroundImage = ImageReference(fileName: "previous-document.png")
        config.terminalColumns = 120
        return config
    }

    private func expectFresh(_ document: SnapshotConfig, source: SnapshotConfig, code: String) {
        #expect(document.code == code)
        #expect(document.annotations.isEmpty)
        #expect(document.highlightedLineRanges.isEmpty)
        #expect(document.redactedLineRanges.isEmpty)
        #expect(document.foregroundImage == nil)
        #expect(document.terminalColumns == nil)
        #expect(document.fontSize == source.fontSize)
        #expect(document.padding == source.padding)
        #expect(document.metadata == source.metadata)
        #expect(document.theme == source.theme)
    }

    @Test func replacementKeepsStyleWithoutMutatingOriginal() {
        let source = markedDocument()
        let document = source.replacingContent(with: "new", language: .swift)
        expectFresh(document, source: source, code: "new")
        #expect(document.language == .swift)
        #expect(source.code == "old\nsource")
        #expect(!source.annotations.isEmpty)
        #expect(source.replacingContent(with: "new").language == .python)
    }

    @Test func editHandoffReplacesContentButSharedLinkRestoresItsOwnAnnotations() throws {
        let environment = AppEnvironment(
            defaults: testDefaults(), entitlements: Entitlements(provider: FreeProvider()))
        let source = markedDocument()
        environment.appSettings.config = source
        var documents: [SnapshotConfig] = []
        let delegate = AppDelegate(
            environment: environment, feedback: CaptureFeedbackPresenter(display: .noOp),
            editorPresentation: .noOp, loadEditor: { documents.append($0) })
        let url = try #require(EditorHandoff.stage(content: "new", language: .swift))
        delegate.openHandoff(url)
        let document = try #require(documents.first)
        expectFresh(document, source: source, code: "new")
        #expect(document.language == .swift)
        delegate.openHandoff(url)
        #expect(documents.count == 1)

        var shared = source
        shared.foregroundImage = nil
        shared.redactedLineRanges = []
        delegate.openHandoff(try SnapshotShareLink.url(for: SharedSnapshot(capturing: shared)))
        let restored = try #require(documents.last)
        #expect(documents.count == 2)
        #expect(restored.annotations == shared.annotations)
        #expect(restored.highlightedLineRanges == shared.highlightedLineRanges)
        #expect(restored.terminalColumns == shared.terminalColumns)
        #expect(restored.code == shared.code)
    }

    @Test func freeOpenIntentUsesItsActualSettingsSource() throws {
        let environment = AppEnvironment(
            defaults: testDefaults(), entitlements: Entitlements(provider: FreeProvider()))
        let source = markedDocument()
        environment.appSettings.config = source
        var result: SnapshotConfig?
        let intent = OpenCodeInEditorIntent()
        intent.code = "let answer = 42"
        intent.language = .automatic
        intent.loadCode(environment: environment, loadEditor: { result = $0 })
        let document = try #require(result)
        expectFresh(document, source: source, code: intent.code)
        #expect(document.language == LanguageDetector.interpret(intent.code).language)
        #expect(environment.appSettings.config == source)
    }

    @Test func urlAsTextRecoveryExportsNewTextInsteadOfOldImageOrRedactions() throws {
        let settings = AppSettings(
            defaults: testDefaults(), entitlements: Entitlements(provider: FreeProvider()))
        let source = markedDocument()
        settings.config = source
        settings.export.autoCopy = true
        settings.export.alsoSaveToFile = false
        settings.export.textSidecar = true
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recents = RecentsStore(
            defaults: testDefaults(), thumbnails: RecentsThumbnailCache(directory: directory),
            renderThumbnail: { _ in nil })
        let text = "https://example.com/new-document"
        let result = QuickCapture.renderText(
            text, settings: settings, recents: recents, pasteboard: pasteboard)
        #expect(result.copiedToClipboard)
        #expect(pasteboard.data(forType: .png)?.isEmpty == false)
        #expect(pasteboard.string(forType: .string) == text)
        #expect(recents.captures.first?.code == text)
        #expect(settings.config == source)
    }

    @Test func quickCaptureDeferralStartsANewDocument() throws {
        let environment = AppEnvironment(
            defaults: testDefaults(), entitlements: Entitlements(provider: FreeProvider()))
        let source = markedDocument()
        environment.appSettings.config = source
        let text = "```swift\nlet first = 1\n```\n```swift\nlet second = 2\n```"
        let result = QuickCapture.capture(
            settings: environment.appSettings, recents: environment.recents, clipboard: { text })
        #expect(result.outcome == .deferredToEditor(blocks: 2))
        expectFresh(
            environment.appSettings.config, source: source,
            code: LanguageDetector.interpret(text).code)
        #expect(environment.recents.captures.isEmpty)
    }
}
