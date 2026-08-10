import Foundation

/// Owns cancellable provider resources outside the generic waiter.
///
/// Xcode 26.6's Swift 6.3 optimizer crashes in `EarlyPerfInliner` when compiling the
/// generic waiter's actor-isolated destructor. Keeping cancellation in a small,
/// non-generic owner lets the generic container use a side-effect-free, nonisolated
/// destructor without relying on underscored optimization attributes.
private final class ItemProviderLoadLifetime {
    var timeoutTask: Task<Void, Never>?
    var progress: Progress?

    isolated deinit {
        cancel()
    }

    func cancel() {
        timeoutTask?.cancel()
        timeoutTask = nil
        progress?.cancel()
        progress = nil
    }
}

/// A one-shot, main-actor bridge for callback-based `NSItemProvider` loads.
///
/// Item providers are external process boundaries: a broken provider can omit its
/// completion callback, report after cancellation, or race the timeout. This state
/// machine keeps exactly one checked continuation and makes the first terminal event
/// authoritative, while cancelling the provider's `Progress` when the caller leaves.
final class ItemProviderLoadWaiter<Value: Sendable> {
    enum LoadError: Error, Equatable {
        /// The provider did not settle within the editor's bounded drop window.
        case timedOut
    }

    enum UsageError: Error, Equatable {
        /// A second caller tried to replace the continuation already being awaited.
        case alreadyWaiting
        /// The one-shot result was already consumed by an earlier caller.
        case alreadyCompleted
    }

    typealias Completion = @Sendable (Result<Value, Error>) -> Void

    private enum State {
        case idle
        /// `wait` reserved the waiter but has not installed its continuation yet.
        case starting
        /// An outcome arrived before the continuation was installed.
        case settled(Result<Value, Error>)
        case waiting(CheckedContinuation<Value, Error>)
        case completed
    }

    private var state: State = .idle
    private let lifetime = ItemProviderLoadLifetime()

    nonisolated deinit {}

    /// Starts one provider request and waits for its callback, cancellation, or timeout.
    ///
    /// `start` runs only after the continuation is installed and returns the provider's
    /// cancellable progress. Its callback may arrive on any executor; the bridge hops
    /// back to the main actor before changing state.
    func wait(
        timeout: Duration,
        start: (_ completion: @escaping Completion) -> Progress?
    ) async throws -> Value {
        switch state {
        case .idle:
            state = .starting
        case .settled(let result):
            state = .completed
            return try result.get()
        case .starting, .waiting:
            throw UsageError.alreadyWaiting
        case .completed:
            throw UsageError.alreadyCompleted
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Value, Error>) in
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
                    lifetime.timeoutTask = Task { @MainActor [weak self] in
                        do {
                            try await Task.sleep(for: timeout)
                        } catch {
                            return
                        }
                        self?.complete(.failure(LoadError.timedOut))
                    }
                    lifetime.progress = start { [weak self] result in
                        Task { @MainActor [weak self] in
                            self?.complete(result)
                        }
                    }
                case .idle, .waiting, .completed:
                    continuation.resume(throwing: UsageError.alreadyCompleted)
                }
            }
        } onCancel: {
            // Cancellation handlers are not actor-isolated. Hop back before touching
            // state; `complete` is idempotent if the provider or timeout already won.
            Task { @MainActor [weak self] in
                self?.complete(.failure(CancellationError()))
            }
        }
    }

    /// Supplies the first provider outcome. Later callbacks are ignored.
    func complete(_ result: Result<Value, Error>) {
        lifetime.cancel()

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
