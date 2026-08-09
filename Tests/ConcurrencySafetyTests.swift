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
}
