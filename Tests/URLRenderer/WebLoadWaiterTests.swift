import Testing

@testable import Vitrine

@MainActor
@Suite("Web load waiter")
struct WebLoadWaiterTests {
    @Test func consumesAnOutcomeThatArrivedBeforeTheWait() async throws {
        let waiter = WebLoadWaiter()
        waiter.complete(.success(()))

        try await waiter.wait(timeout: .seconds(1))

        await #expect(throws: WebLoadWaiter.UsageError.alreadyCompleted) {
            try await waiter.wait(timeout: .seconds(1))
        }
    }

    @Test func preservesTheFirstEarlyOutcome() async {
        let waiter = WebLoadWaiter()
        waiter.complete(.failure(WebSnapshotError.loadFailed))
        waiter.complete(.success(()))

        await #expect(throws: WebSnapshotError.loadFailed) {
            try await waiter.wait(timeout: .seconds(1))
        }
    }

    @Test func rejectsASecondConcurrentWaitWithoutReplacingTheFirst() async throws {
        let waiter = WebLoadWaiter()
        let first = Task {
            try await waiter.wait(timeout: .seconds(10))
        }
        await Task.yield()

        await #expect(throws: WebLoadWaiter.UsageError.alreadyWaiting) {
            try await waiter.wait(timeout: .seconds(1))
        }

        waiter.complete(.success(()))
        try await first.value
    }

    @Test func aMissingDelegateOutcomeTimesOutOnce() async {
        let waiter = WebLoadWaiter()

        await #expect(throws: WebSnapshotError.timedOut) {
            try await waiter.wait(timeout: .milliseconds(1))
        }

        // A late WebKit callback cannot become a stale result for another wait.
        waiter.complete(.success(()))
        await #expect(throws: WebLoadWaiter.UsageError.alreadyCompleted) {
            try await waiter.wait(timeout: .seconds(1))
        }
    }

    @Test func cancellationResumesThePendingWaitExactlyOnce() async {
        let waiter = WebLoadWaiter()
        let task = Task {
            try await waiter.wait(timeout: .seconds(10))
        }
        await Task.yield()

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        waiter.complete(.success(()))
        await #expect(throws: WebLoadWaiter.UsageError.alreadyCompleted) {
            try await waiter.wait(timeout: .seconds(1))
        }
    }

    @Test func aTaskCancelledBeforeWaitingDoesNotInstallAContinuation() async {
        let waiter = WebLoadWaiter()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await waiter.wait(timeout: .seconds(10))
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        await #expect(throws: WebLoadWaiter.UsageError.alreadyCompleted) {
            try await waiter.wait(timeout: .seconds(1))
        }
    }
}
