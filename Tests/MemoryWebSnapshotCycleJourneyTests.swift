import Testing

@testable import Vitrine

@MainActor
@Suite("Web snapshot memory journey")
struct MemoryWebSnapshotCycleJourneyTests {
    @Test func rendersTenDistinctSessionsSequentially() async throws {
        var rendered: [Int] = []
        let journey = MemoryWebSnapshotCycleJourney(
            render: {
                rendered.append($0)
                return "snapshot-\($0)"
            },
            sleep: { _ in })

        let result = try await journey.run()

        #expect(result == .init(completedIterations: 10, uniqueSnapshots: 10))
        #expect(rendered == Array(0..<10))
    }

    @Test func propagatesCancellationBetweenSessions() async {
        let journey = MemoryWebSnapshotCycleJourney(
            render: { "snapshot-\($0)" },
            sleep: { _ in throw CancellationError() })
        await #expect(throws: CancellationError.self) {
            try await journey.run(iterations: 2)
        }
    }

    @Test func rejectsEmptyAndDuplicateJourneys() async {
        let journey = MemoryWebSnapshotCycleJourney(
            render: { _ in "same" }, sleep: { _ in })
        await #expect(throws: MemoryWebSnapshotCycleJourney.JourneyError.invalidIterationCount) {
            try await journey.run(iterations: 0)
        }
        await #expect(throws: MemoryWebSnapshotCycleJourney.JourneyError.duplicateSnapshot) {
            try await journey.run(iterations: 2)
        }
    }
}
