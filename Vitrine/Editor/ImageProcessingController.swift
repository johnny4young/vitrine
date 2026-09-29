import Foundation
import Observation

/// Owns one editor's OCR operation. Cancellation releases the UI immediately;
/// a recognizer that finishes later cannot publish or clear a replacement job.
@Observable
final class ImageProcessingController {
    enum Operation: Equatable {
        case copyText
        case redactSecrets
    }

    private(set) var operation: Operation?
    var isProcessing: Bool { operation != nil }

    @ObservationIgnored private var identity = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    isolated deinit {
        task?.cancel()
    }

    /// The work may suspend, but publication is synchronous on the editor's actor.
    /// Returning the owned task also lets behavioral tests await its actual lifetime.
    @discardableResult
    func start<Value>(
        _ operation: Operation,
        work: @escaping @MainActor () async throws -> Value,
        publish: @escaping @MainActor (Value) -> Void,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> Task<Void, Never> {
        cancel()
        let current = identity
        self.operation = operation
        let task = Task { [weak self] in
            defer { self?.finish(current) }
            do {
                try Task.checkCancellation()
                let value = try await work()
                try Task.checkCancellation()
                guard self?.identity == current else { return }
                publish(value)
            } catch is CancellationError {
                // Cancelling is not a failed recognition and must not show an error.
            } catch {
                guard !Task.isCancelled, self?.identity == current else { return }
                onFailure(error)
            }
        }
        self.task = task
        return task
    }

    func cancel() {
        identity = UUID()
        task?.cancel()
        task = nil
        operation = nil
    }

    private func finish(_ completed: UUID) {
        guard identity == completed else { return }
        task = nil
        operation = nil
    }
}
