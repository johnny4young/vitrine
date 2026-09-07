import Foundation
import Testing

@testable import Vitrine

/// The canvas resolves an image reference synchronously inside its `body`, and it has to:
/// the same view renders an export, where an image arriving a frame later would silently
/// produce the fallback gradient instead of the user's photo. The cost of that choice
/// lands on the first pass after launch, which decodes on the main actor — measured at
/// 207 ms for a 24 MB photo background.
///
/// Warming the process-wide cache off the main actor at launch turns that pass into a
/// lookup. Nothing depends on it finishing, so a regression here is silent: the app still
/// works, it just stalls again. That is what this guard is for.
@Suite("Persisted image prewarm")
struct BackgroundImagePrewarmTests {
    private static func appDelegateSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return sourceCodeWithoutLineComments(
            try String(
                contentsOf: root.appendingPathComponent("Vitrine/App/AppDelegate.swift"),
                encoding: .utf8))
    }

    @Test func launchWarmsThePersistedBackgroundAndForeground() throws {
        let source = try Self.appDelegateSource()
        #expect(
            source.contains("prewarmPersistedImages"),
            "launch must warm the images the first canvas would otherwise decode on the main actor")
        #expect(
            source.contains("BackgroundImageStore.container.preloadImage"),
            "the persisted background must be warmed")
        #expect(
            source.contains("BackgroundImageStore.foregroundContainer.preloadImage"),
            "the persisted foreground must be warmed through its own container")
        #expect(
            source.contains("Task(priority: .utility) { await self.prewarmPersistedImages() }"),
            "warming must stay off the launch critical path")
    }
}
