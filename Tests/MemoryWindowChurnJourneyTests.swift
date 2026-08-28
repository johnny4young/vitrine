import Testing

@testable import Vitrine

@MainActor
@Suite("Window churn memory journey")
struct MemoryWindowChurnJourneyTests {
    @Test func opensCapturesAndClosesEveryAdditionalWindow() async throws {
        var live = Set([1])
        var nextIdentity = 2
        var captured: [Int] = []
        var closed: [Int] = []
        let journey = MemoryWindowChurnJourney(
            liveWindowCount: { live.count },
            openWindow: {
                let identity = nextIdentity
                nextIdentity += 1
                live.insert(identity)
                return identity
            },
            capture: { identity, tick in
                #expect(live.contains(identity))
                captured.append(identity)
                return "window-\(identity)-\(tick)"
            },
            closeWindow: {
                closed.append($0)
                live.remove($0)
            },
            sleep: { _ in })

        let result = try await journey.run(iterations: 20)

        #expect(result == .init(completedIterations: 20, capturedSnapshots: 20))
        #expect(captured.count == 20)
        #expect(closed == captured)
        #expect(live == [1])
    }

    @Test func cancellationClosesTheInflightWindow() async {
        var live = Set([1])
        var closed: [Int] = []
        let journey = MemoryWindowChurnJourney(
            liveWindowCount: { live.count },
            openWindow: {
                live.insert(2)
                return 2
            },
            capture: { _, _ in "snapshot" },
            closeWindow: {
                closed.append($0)
                live.remove($0)
            },
            sleep: { _ in throw CancellationError() })

        await #expect(throws: CancellationError.self) {
            try await journey.run(iterations: 1)
        }
        #expect(closed == [2])
        #expect(live == [1])
    }

    @Test func rejectsInvalidCountsAndMissingCaptures() async {
        let invalid = MemoryWindowChurnJourney(
            liveWindowCount: { 1 }, openWindow: { 2 },
            capture: { _, _ in "snapshot" }, closeWindow: { _ in }, sleep: { _ in })
        await #expect(throws: MemoryWindowChurnJourney.JourneyError.invalidIterationCount) {
            try await invalid.run(iterations: 0)
        }

        var live = Set([1])
        let missing = MemoryWindowChurnJourney(
            liveWindowCount: { live.count },
            openWindow: {
                live.insert(2)
                return 2
            },
            capture: { _, _ in "" },
            closeWindow: { live.remove($0) },
            sleep: { _ in })
        await #expect(throws: MemoryWindowChurnJourney.JourneyError.snapshotCaptureFailed) {
            try await missing.run(iterations: 1)
        }
        #expect(live == [1])
    }
}
