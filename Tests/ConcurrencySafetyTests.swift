import Foundation
import Testing

@testable import Vitrine

@Suite("Concurrency source safety")
struct ConcurrencySafetyTests {
    /// Swift 6.2's `@concurrent` functions express executor hops without shedding
    /// actor context, priority, and cancellation through detached tasks. Keep the
    /// production targets on that actor-aware boundary as new background work appears.
    @Test func productionSourcesContainNoDetachedTasks() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let roots = ["Vitrine", "VitrineCLI"].map {
            repositoryRoot.appendingPathComponent($0, isDirectory: true)
        }
        var offenders: [String] = []

        for root in roots {
            let enumerator = try #require(
                FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                if try String(contentsOf: url, encoding: .utf8).contains("Task.detached") {
                    offenders.append(
                        url.path.replacingOccurrences(of: repositoryRoot.path, with: ""))
                }
            }
        }

        #expect(
            offenders.isEmpty,
            "Production code must use actor-aware @concurrent work, not detached tasks: \(offenders)"
        )
    }

    /// AppKit item providers are external callback boundaries and are allowed to omit
    /// their callback. Keep every editor representation behind the tested timeout /
    /// exactly-once bridge, and keep the owning SwiftUI task cancellable on replacement
    /// or teardown instead of reintroducing fire-and-forget drop work.
    @Test func editorItemProvidersUseTheBoundedOwnedBridge() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dragDrop = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Vitrine/Editor/EditorView+DragDrop.swift"),
            encoding: .utf8)
        let stage = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Vitrine/Editor/EditorView+Stage.swift"),
            encoding: .utf8)

        #expect(!dragDrop.contains("withCheckedContinuation"))
        #expect(dragDrop.components(separatedBy: "ItemProviderLoadWaiter<").count - 1 == 3)
        #expect(dragDrop.contains("itemProviderLoadTimeout"))
        #expect(stage.contains("dropTask?.cancel()"))
        #expect(stage.contains(".onDisappear"))
    }

    /// OCR and network image imports update view-bound state after suspension. Keep
    /// those operations owned and cancelled on teardown, and prevent a batch-export
    /// sheet from disappearing while its file writes are still in flight.
    @Test func viewBoundLongRunningTasksHaveLifecycleOwnership() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editor = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Vitrine/Editor/EditorView.swift"),
            encoding: .utf8)
        let stage = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Vitrine/Editor/EditorView+Stage.swift"), encoding: .utf8)
        let background = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Vitrine/Canvas/BackgroundEditor.swift"), encoding: .utf8)
        let carousel = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Vitrine/Export/CarouselExportView.swift"), encoding: .utf8)

        #expect(editor.contains("@State var imageProcessingTask: Task<Void, Never>?"))
        #expect(stage.contains("imageProcessingTask?.cancel()"))
        #expect(stage.contains("catch is CancellationError"))
        #expect(background.contains("@State private var importTask: Task<Void, Never>?"))
        #expect(background.contains("importTask?.cancel()"))
        #expect(background.contains("@State private var downloadTask: Task<Void, Never>?"))
        #expect(background.contains("downloadTask?.cancel()"))
        #expect(background.contains("try Task.checkCancellation()"))
        #expect(background.components(separatedBy: "guard !Task.isCancelled").count - 1 == 4)
        #expect(carousel.contains(".interactiveDismissDisabled(isExporting)"))
    }

    /// Living files combine blocking descriptor reads with window-bound state. Keep filesystem
    /// work behind an async Sendable client, and keep each picker/poll operation owned, cancelled,
    /// and generation-guarded so a late result cannot mutate a different or closed editor.
    @Test func livingSnapshotReadsHaveLifecycleOwnership() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let session = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Vitrine/Editor/LivingSnapshotSession.swift"),
            encoding: .utf8)
        let loader = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Vitrine/Editor/FileInputLoader.swift"),
            encoding: .utf8)
        let picker = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Vitrine/Editor/EditorView+DragDrop.swift"),
            encoding: .utf8)

        #expect(session.contains("nonisolated struct FileClient: Sendable"))
        #expect(session.contains("@concurrent"))
        #expect(session.contains("private var fileReadTask: Task<Bool, Never>?"))
        #expect(
            session.contains("private var openingTask: Task<FileInputLoader.LoadedFile, Error>?"))
        #expect(session.contains("fileReadTask?.cancel()"))
        #expect(session.contains("openingTask?.cancel()"))
        #expect(session.contains("generation == readGeneration"))
        #expect(session.contains("generation == openingGeneration"))
        #expect(loader.contains("static func loadConcurrently(from url: URL) async throws"))
        #expect(picker.contains("session.livingSnapshot.loadForOpening(from: url)"))
    }
}
