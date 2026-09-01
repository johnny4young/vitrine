import Foundation

/// Coalesces rapid calls into a single trailing call after a quiet window,
/// using structured concurrency. Each `schedule` cancels the pending one.
final class Debouncer {
    private let interval: Duration
    private var task: Task<Void, Never>?

    init(interval: Duration = .milliseconds(100)) {
        self.interval = interval
    }

    /// Runs `action` after the configured interval (or an explicit override) of quiet; a new call
    /// restarts the timer. The override lets callers adapt the quiet window to bounded input cost
    /// without keeping multiple independent tasks alive.
    func schedule(after override: Duration? = nil, _ action: @escaping () -> Void) {
        task?.cancel()
        let delay = override ?? interval
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
