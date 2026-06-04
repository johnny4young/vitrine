import Foundation

/// Coalesces rapid calls into a single trailing call after a quiet window,
/// using structured concurrency (CS-003). Each `schedule` cancels the pending one.
final class Debouncer {
    private let interval: Duration
    private var task: Task<Void, Never>?

    init(interval: Duration = .milliseconds(100)) {
        self.interval = interval
    }

    /// Runs `action` after `interval` of quiet; a new call restarts the timer.
    func schedule(_ action: @escaping () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
