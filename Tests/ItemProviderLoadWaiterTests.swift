import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Item-provider load waiter")
struct ItemProviderLoadWaiterTests {
    private enum StubError: Error {
        case failed
    }

    @Test func aSynchronousProviderCallbackCompletesTheWait() async throws {
        let waiter = ItemProviderLoadWaiter<Int>()

        let value = try await waiter.wait(timeout: .seconds(10)) { completion in
            completion(.success(42))
            return Progress(totalUnitCount: 1)
        }

        #expect(value == 42)
    }

    @Test func consumesAnOutcomeThatArrivedBeforeTheWait() async throws {
        let waiter = ItemProviderLoadWaiter<Int>()
        waiter.complete(.success(7))

        #expect(try await waiter.wait(timeout: .seconds(10)) { _ in nil } == 7)
        await #expect(throws: ItemProviderLoadWaiter<Int>.UsageError.alreadyCompleted) {
            try await waiter.wait(timeout: .seconds(10)) { _ in nil }
        }
    }

    @Test func rejectsASecondWaitWithoutReplacingTheFirst() async throws {
        let waiter = ItemProviderLoadWaiter<Int>()
        let first = Task {
            try await waiter.wait(timeout: .seconds(10)) { _ in
                Progress(totalUnitCount: 1)
            }
        }
        await Task.yield()

        await #expect(throws: ItemProviderLoadWaiter<Int>.UsageError.alreadyWaiting) {
            try await waiter.wait(timeout: .seconds(10)) { _ in nil }
        }

        waiter.complete(.success(9))
        #expect(try await first.value == 9)
    }

    @Test func aMissingProviderCallbackTimesOutOnce() async {
        let waiter = ItemProviderLoadWaiter<Int>()
        let progress = Progress(totalUnitCount: 1)

        await #expect(throws: ItemProviderLoadWaiter<Int>.LoadError.timedOut) {
            try await waiter.wait(timeout: .milliseconds(1)) { _ in progress }
        }

        #expect(progress.isCancelled)
        waiter.complete(.success(1))
        await #expect(throws: ItemProviderLoadWaiter<Int>.UsageError.alreadyCompleted) {
            try await waiter.wait(timeout: .seconds(10)) { _ in nil }
        }
    }

    @Test func cancellationResumesOnceAndCancelsProviderProgress() async {
        let waiter = ItemProviderLoadWaiter<Int>()
        let progress = Progress(totalUnitCount: 1)
        let task = Task {
            try await waiter.wait(timeout: .seconds(10)) { _ in progress }
        }
        await Task.yield()

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(progress.isCancelled)
        waiter.complete(.success(1))
    }

    @Test func aTaskCancelledBeforeWaitingNeverStartsTheProvider() async {
        let waiter = ItemProviderLoadWaiter<Int>()
        var didStart = false
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await waiter.wait(timeout: .seconds(10)) { _ in
                didStart = true
                return Progress(totalUnitCount: 1)
            }
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(!didStart)
    }

    @Test func providerFailureWinsOnceAndCancelsItsProgress() async {
        let waiter = ItemProviderLoadWaiter<Int>()
        let progress = Progress(totalUnitCount: 1)

        await #expect(throws: StubError.failed) {
            try await waiter.wait(timeout: .seconds(10)) { completion in
                completion(.failure(StubError.failed))
                return progress
            }
        }

        #expect(progress.isCancelled)
        waiter.complete(.success(1))
    }
}
