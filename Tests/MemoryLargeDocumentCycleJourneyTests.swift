import Testing

@testable import Vitrine

@MainActor
@Suite("Large-document memory journey")
struct MemoryLargeDocumentCycleJourneyTests {
    @Test func publishesCapturesTearsDownAndObservesDistinctDocuments() async throws {
        let settings = AppSettings(defaults: testDefaults())
        settings.config.code = "baseline"
        let baseline = settings.config
        var capturedByteCounts: [Int] = []
        var observed: [Int] = []
        let journey = MemoryLargeDocumentCycleJourney(
            settings: settings,
            sleep: { _ in },
            capture: { tick in
                capturedByteCounts.append(settings.config.code.utf8.count)
                return "document-\(tick)"
            },
            observe: {
                #expect(settings.config == baseline)
                observed.append($0)
            })

        let result = try await journey.run(iterations: 3)

        #expect(result == .init(completedIterations: 3, uniqueSnapshots: 3))
        #expect(capturedByteCounts.allSatisfy { $0 > HighlightPolicy.maximumHighlightedByteCount })
        #expect(observed == [1, 2, 3])
        #expect(settings.config == baseline)
    }

    @Test func cancellationRestoresTheBaselineDocument() async {
        let settings = AppSettings(defaults: testDefaults())
        settings.config.code = "keep me"
        let baseline = settings.config
        let journey = MemoryLargeDocumentCycleJourney(
            settings: settings,
            sleep: { _ in throw CancellationError() },
            capture: { "document-\($0)" })

        await #expect(throws: CancellationError.self) {
            try await journey.run(iterations: 2)
        }
        #expect(settings.config == baseline)
    }

    @Test func rejectsInvalidCountsAndDuplicateSnapshots() async {
        let settings = AppSettings(defaults: testDefaults())
        let journey = MemoryLargeDocumentCycleJourney(
            settings: settings,
            sleep: { _ in },
            capture: { _ in "same" })

        await #expect(throws: MemoryLargeDocumentCycleJourney.JourneyError.invalidIterationCount) {
            try await journey.run(iterations: 0)
        }
        await #expect(throws: MemoryLargeDocumentCycleJourney.JourneyError.duplicateSnapshot) {
            try await journey.run(iterations: 2)
        }
    }
}
