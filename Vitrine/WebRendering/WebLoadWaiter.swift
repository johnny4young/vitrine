import Foundation

/// A one-shot, main-actor state machine for waiting on a WebKit navigation.
///
/// WebKit can report an outcome before the caller starts waiting, after a timeout, or
/// while cancellation races a delegate callback. Keeping those transitions here gives
/// both HTML and URL capture the same exactly-once continuation and timeout policy.
final class WebLoadWaiter {
    enum UsageError: Error, Equatable {
        /// A second caller tried to replace the continuation already being awaited.
        case alreadyWaiting
        /// The one-shot result was already consumed by an earlier caller.
        case alreadyCompleted
    }

    private enum State {
        case idle
        /// `wait` reserved the waiter but has not installed its continuation yet.
        case starting
        /// WebKit settled before the continuation was installed.
        case settled(Result<Void, Error>)
        case waiting(CheckedContinuation<Void, Error>)
        case completed
    }

    private var state: State = .idle
    private var timeoutTask: Task<Void, Never>?

    isolated deinit {
        timeoutTask?.cancel()
    }

    /// Waits once for a delegate result, task cancellation, or the supplied timeout.
    ///
    /// A programming error never overwrites a live checked continuation: concurrent and
    /// repeated waits fail immediately with ``UsageError`` instead of hanging a caller.
    func wait(timeout: Duration) async throws {
        switch state {
        case .idle:
            // Reserve synchronously before the first suspension so actor reentrancy
            // cannot let a second caller install another continuation.
            state = .starting
        case .settled(let result):
            state = .completed
            try result.get()
            return
        case .starting, .waiting:
            throw UsageError.alreadyWaiting
        case .completed:
            throw UsageError.alreadyCompleted
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                switch state {
                case .settled(let result):
                    state = .completed
                    continuation.resume(with: result)
                case .starting:
                    guard !Task.isCancelled else {
                        state = .completed
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    state = .waiting(continuation)
                    timeoutTask = Task { @MainActor [weak self] in
                        do {
                            try await Task.sleep(for: timeout)
                        } catch {
                            return
                        }
                        self?.complete(.failure(WebSnapshotError.timedOut))
                    }
                case .idle, .waiting, .completed:
                    // `wait` reserved `.starting` above. Reaching any other state would
                    // mean this continuation was no longer the active caller.
                    continuation.resume(throwing: UsageError.alreadyCompleted)
                }
            }
        } onCancel: {
            // Cancellation handlers are not actor-isolated. Hop back before touching
            // the state machine; `complete` is idempotent if WebKit or the timer won.
            Task { @MainActor [weak self] in
                self?.complete(.failure(CancellationError()))
            }
        }
    }

    /// Supplies the first navigation outcome. Later delegate callbacks are ignored.
    func complete(_ result: Result<Void, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        switch state {
        case .idle, .starting:
            state = .settled(result)
        case .waiting(let continuation):
            state = .completed
            continuation.resume(with: result)
        case .settled, .completed:
            break
        }
    }
}
