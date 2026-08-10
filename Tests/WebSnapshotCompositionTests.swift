import AppKit
import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Web snapshot composition")
struct WebSnapshotCompositionTests {
    private final class DisplaySpy {
        var feedback: [Notifier.CaptureFeedback] = []

        var display: FeedbackDisplay {
            FeedbackDisplay { [weak self] feedback, _ in
                self?.feedback.append(feedback)
            }
        }
    }

    private final class PresentationSpy {
        var signInURLs: [URL] = []
        var sharedImages: [NSImage] = []
        var selectedDirectory: URL?
        var selectionMessages: [String] = []
        var revealedDirectories: [URL] = []

        var presentation: WebSnapshotPresentation {
            WebSnapshotPresentation(
                presentSignIn: { [weak self] url in
                    self?.signInURLs.append(url)
                },
                presentShare: { [weak self] image in
                    self?.sharedImages.append(image)
                },
                batchExport: BatchExportPresentation(
                    selectDirectory: { [weak self] message in
                        self?.selectionMessages.append(message)
                        return self?.selectedDirectory
                    },
                    revealDirectory: { [weak self] directory in
                        self?.revealedDirectories.append(directory)
                    }))
        }
    }

    @Test func controllerSuppliesOneDependencyGraphToItsRoot() throws {
        let defaults = testDefaults()
        let environment = AppEnvironment(defaults: defaults)
        let model = WebSnapshotModel()
        let display = DisplaySpy()
        let presentation = PresentationSpy()
        let controller = WebSnapshotWindowController(
            environment: environment,
            model: model,
            feedback: display.display,
            presentation: presentation.presentation)

        let root = controller.makeRootView()
        let expectedFeedback = Notifier.confirmation("Web feedback")
        let expectedURL = try #require(URL(string: "https://example.com/account"))
        let expectedImage = NSImage(size: NSSize(width: 1, height: 1))
        let expectedDirectory = URL(fileURLWithPath: "/tmp/vitrine-web-export")
        presentation.selectedDirectory = expectedDirectory
        root.feedback(expectedFeedback)
        root.presentation.showSignIn(for: expectedURL)
        root.presentation.share(expectedImage)
        let selectedDirectory = root.presentation.batchExport.chooseDirectory(
            message: "Choose a directory")
        root.presentation.batchExport.reveal(expectedDirectory)

        #expect(controller.environment === environment)
        #expect(controller.model === model)
        #expect(root.environment === environment)
        #expect(root.model === model)
        #expect(display.feedback == [expectedFeedback])
        #expect(presentation.signInURLs == [expectedURL])
        #expect(presentation.sharedImages.count == 1)
        #expect(presentation.sharedImages.first === expectedImage)
        #expect(selectedDirectory == expectedDirectory)
        #expect(presentation.selectionMessages == ["Choose a directory"])
        #expect(presentation.revealedDirectories == [expectedDirectory])
    }

    @Test func signInActionUsesTheInjectedPresentation() throws {
        let defaults = testDefaults()
        let environment = AppEnvironment(defaults: defaults)
        let model = WebSnapshotModel()
        let presentation = PresentationSpy()
        let root = WebSnapshotEditorView(
            model: model,
            environment: environment,
            feedback: .noOp,
            presentation: presentation.presentation)
        model.urlText = "https://example.com/login"

        root.signInToCaptureSite()

        #expect(presentation.signInURLs.map(\.absoluteString) == ["https://example.com/login"])
    }

    @Test func shareActionUsesTheInjectedPresentation() throws {
        let defaults = testDefaults()
        let environment = AppEnvironment(defaults: defaults)
        let model = WebSnapshotModel()
        model.renderedAsset = try Self.tinyRenderedAsset()
        let presentation = PresentationSpy()
        let root = WebSnapshotEditorView(
            model: model,
            environment: environment,
            feedback: .noOp,
            presentation: presentation.presentation)

        root.shareImage()

        #expect(presentation.sharedImages.map(\.size) == [NSSize(width: 1, height: 1)])
    }

    @Test func exportAllUsesTheInjectedDirectoryAndRevealsOnlyACompleteBatch() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = testDefaults()
        let environment = AppEnvironment(defaults: defaults)
        let model = WebSnapshotModel()
        let asset = try Self.tinyRenderedAsset()
        model.results = [CapturedViewport(kind: .desktop, preset: .desktop, asset: asset)]
        model.boardAsset = asset
        let display = DisplaySpy()
        let presentation = PresentationSpy()
        presentation.selectedDirectory = directory
        let root = WebSnapshotEditorView(
            model: model,
            environment: environment,
            feedback: display.display,
            presentation: presentation.presentation)

        root.exportAll()

        #expect(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("vitrine-web-desktop-1440x900.png").path))
        #expect(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("vitrine-web-responsive-board.png").path))
        #expect(
            presentation.selectionMessages
                == [String(localized: "Choose a folder for the exported images.")])
        #expect(presentation.revealedDirectories == [directory])
        #expect(
            display.feedback
                == [Notifier.confirmation(String(localized: "Images exported"))])
    }

    @Test func partialExportReportsFailureAndDoesNotRevealTheDirectory() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockedOutput = directory.appendingPathComponent("vitrine-web-responsive-board.png")
        try FileManager.default.createDirectory(
            at: blockedOutput,
            withIntermediateDirectories: false)
        let defaults = testDefaults()
        let environment = AppEnvironment(defaults: defaults)
        let model = WebSnapshotModel()
        let asset = try Self.tinyRenderedAsset()
        model.results = [CapturedViewport(kind: .desktop, preset: .desktop, asset: asset)]
        model.boardAsset = asset
        let display = DisplaySpy()
        let presentation = PresentationSpy()
        presentation.selectedDirectory = directory
        let root = WebSnapshotEditorView(
            model: model,
            environment: environment,
            feedback: display.display,
            presentation: presentation.presentation)
        let failure = try #require(
            BatchExportCompletion(written: 1, failed: 1, expected: 2).failureNote)

        root.exportAll()

        #expect(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("vitrine-web-desktop-1440x900.png").path))
        #expect(presentation.revealedDirectories.isEmpty)
        #expect(display.feedback == [Notifier.failure(failure)])
    }

    @Test func cancelledExportDoesNotWriteOrPresentFeedback() throws {
        let defaults = testDefaults()
        let environment = AppEnvironment(defaults: defaults)
        let model = WebSnapshotModel()
        let asset = try Self.tinyRenderedAsset()
        model.results = [CapturedViewport(kind: .desktop, preset: .desktop, asset: asset)]
        let display = DisplaySpy()
        let presentation = PresentationSpy()
        let root = WebSnapshotEditorView(
            model: model,
            environment: environment,
            feedback: display.display,
            presentation: presentation.presentation)

        root.exportAll()

        #expect(presentation.selectionMessages.count == 1)
        #expect(presentation.revealedDirectories.isEmpty)
        #expect(display.feedback.isEmpty)
    }

    @Test func editorSurfacesContainNoAppOwnedPresentationGlobals() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for relativePath in [
            "Vitrine/WebRendering/WebSnapshotEditorView.swift",
            "Vitrine/WebRendering/WebSnapshotEditorView+Actions.swift",
            "Vitrine/WebRendering/WebSnapshotEditorView+Inspector.swift",
            "Vitrine/WebRendering/WebSnapshotEditorView+Preview.swift",
            "Vitrine/WebRendering/WebSnapshotEditorView+Toolbar.swift",
        ] {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8)
            let code = sourceCodeWithoutLineComments(source)

            for forbiddenDependency in [
                "AppEnvironment.shared",
                "CaptureHUDController.shared",
                "WebSessionWindowController.shared",
                "ShareManager.share",
                "ExportFeedback.present",
                "NSOpenPanel",
                "NSWorkspace.shared",
            ] {
                #expect(
                    !code.contains(forbiddenDependency),
                    "\(relativePath) must receive \(forbiddenDependency) from its controller")
            }
        }
    }

    private static func tinyRenderedAsset() throws -> RenderedAsset {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = try #require(context.makeImage())
        return RenderedAsset(cgImage: image, profile: .sRGB)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineWebExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false)
        return directory
    }
}
