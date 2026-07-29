import Testing

@testable import Vitrine

@MainActor
@Suite("URL load coordination")
struct URLLoadCoordinatorTests {
    @Test func aLoadWithoutADelegateOutcomeTimesOut() async {
        let coordinator = URLLoadCoordinator(allowsLoopbackCapture: false)

        await #expect(throws: WebSnapshotError.timedOut) {
            try await coordinator.waitForLoad(timeout: .milliseconds(1))
        }
    }

    @Test func taskCancellationResumesThePendingLoad() async {
        let coordinator = URLLoadCoordinator(allowsLoopbackCapture: false)
        let task = Task {
            try await coordinator.waitForLoad(timeout: .seconds(10))
        }

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
