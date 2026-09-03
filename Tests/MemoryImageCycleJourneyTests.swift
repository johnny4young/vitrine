import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Image memory journey")
struct MemoryImageCycleJourneyTests {
    private static func temporaryStore() -> BackgroundImageStore {
        BackgroundImageStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                "VitrineMemoryImageJourney-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func importsDecodesSnapshotsAndClearsDistinctImages() async throws {
        let settings = AppSettings(defaults: testDefaults())
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var capturedTicks: [Int] = []
        var observedIterations: [Int] = []
        let journey = MemoryImageCycleJourney(
            settings: settings,
            store: store,
            sleep: { _ in },
            capture: {
                capturedTicks.append($0)
                return "snapshot-\($0)"
            },
            observe: { observedIterations.append($0) })

        let result = try await journey.run(iterations: 8)

        #expect(result.completedIterations == 8)
        #expect(result.uniqueReferences == 8)
        #expect(result.uniqueSnapshots == 8)
        #expect(capturedTicks == Array(0..<8))
        #expect(observedIterations == Array(1...8))
        #expect(settings.config.foregroundImage == nil)
        let storedFiles = try FileManager.default.contentsOfDirectory(
            at: store.directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        #expect(storedFiles.count == 8)
    }

    @Test func cancellationClearsTheCurrentEditorReference() async {
        let settings = AppSettings(defaults: testDefaults())
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let journey = MemoryImageCycleJourney(
            settings: settings,
            store: store,
            sleep: { _ in throw CancellationError() },
            capture: { "snapshot-\($0)" })

        await #expect(throws: CancellationError.self) {
            try await journey.run(iterations: 4)
        }
        #expect(settings.config.foregroundImage == nil)
    }

    @Test func refusesAnEmptyJourney() async {
        let journey = MemoryImageCycleJourney(
            settings: AppSettings(defaults: testDefaults()),
            store: Self.temporaryStore(),
            sleep: { _ in },
            capture: { "snapshot-\($0)" })

        await #expect(throws: MemoryImageCycleJourney.JourneyError.invalidIterationCount) {
            try await journey.run(iterations: 0)
        }
    }

    @Test func duplicateLiveSnapshotsFailAndClearTheEditorReference() async {
        let settings = AppSettings(defaults: testDefaults())
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let journey = MemoryImageCycleJourney(
            settings: settings,
            store: store,
            sleep: { _ in },
            capture: { _ in "unchanged-window" })

        await #expect(throws: MemoryImageCycleJourney.JourneyError.duplicateSnapshot) {
            try await journey.run(iterations: 2)
        }
        #expect(settings.config.foregroundImage == nil)
    }

    @Test func debugIsolationRequiresBothExplicitMarkers() {
        let temporaryRoot = URL(fileURLWithPath: "/tmp/vitrine-memory-tests", isDirectory: true)

        #expect(
            BackgroundImageStore.debugIsolatedContainerRoot(
                environment: ["VITRINE_MEMORY_IMAGE_STORE_ISOLATED": "1"],
                temporaryDirectory: temporaryRoot) == nil)
        #expect(
            BackgroundImageStore.debugIsolatedContainerRoot(
                environment: ["VITRINE_USER_DEFAULTS_SUITE": "isolated-suite"],
                temporaryDirectory: temporaryRoot) == nil)

        let first = BackgroundImageStore.debugIsolatedContainerRoot(
            environment: [
                "VITRINE_MEMORY_IMAGE_STORE_ISOLATED": "1",
                "VITRINE_USER_DEFAULTS_SUITE": "isolated-suite",
            ],
            temporaryDirectory: temporaryRoot)
        let repeated = BackgroundImageStore.debugIsolatedContainerRoot(
            environment: [
                "VITRINE_MEMORY_IMAGE_STORE_ISOLATED": "1",
                "VITRINE_USER_DEFAULTS_SUITE": "isolated-suite",
            ],
            temporaryDirectory: temporaryRoot)
        let different = BackgroundImageStore.debugIsolatedContainerRoot(
            environment: [
                "VITRINE_MEMORY_IMAGE_STORE_ISOLATED": "1",
                "VITRINE_USER_DEFAULTS_SUITE": "another-suite",
            ],
            temporaryDirectory: temporaryRoot)

        #expect(first == repeated)
        #expect(first != different)
        #expect(first?.deletingLastPathComponent() == temporaryRoot)
        #expect(first?.lastPathComponent.contains("isolated-suite") == false)
    }
}
