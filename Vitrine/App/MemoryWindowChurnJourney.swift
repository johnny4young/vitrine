import Foundation

/// Opt-in dynamic-memory journey that repeatedly opens, renders, and closes an
/// additional editor window while keeping the primary editor alive.
///
/// The injected operations keep the lifecycle policy testable without creating real
/// AppKit windows in unit tests. The launch-argument handler supplies the production
/// `EditorWindowController` operations for release-QA captures.
struct MemoryWindowChurnJourney {
    struct Result: Equatable {
        let completedIterations: Int
        let capturedSnapshots: Int
    }

    enum JourneyError: Error, Equatable {
        case invalidIterationCount
        case windowDidNotOpen
        case windowDidNotClose
        case snapshotCaptureFailed
    }

    static let journeyID = "window-churn"
    static let completionMarker = "VITRINE_MEMORY_WINDOW_CHURN_COMPLETE"
    static let defaultIterationCount = 20

    let liveWindowCount: () -> Int
    let openWindow: () throws -> Int
    let capture: (Int, Int) throws -> String
    let closeWindow: (Int) -> Void
    let sleep: (Duration) async throws -> Void
    let observe: (Int) async throws -> Void

    init(
        liveWindowCount: @escaping () -> Int,
        openWindow: @escaping () throws -> Int,
        capture: @escaping (Int, Int) throws -> String,
        closeWindow: @escaping (Int) -> Void,
        sleep: @escaping (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        observe: @escaping (Int) async throws -> Void = { _ in }
    ) {
        self.liveWindowCount = liveWindowCount
        self.openWindow = openWindow
        self.capture = capture
        self.closeWindow = closeWindow
        self.sleep = sleep
        self.observe = observe
    }

    /// Runs the bounded lifecycle and closes an in-flight window on every exit.
    func run(iterations: Int = defaultIterationCount) async throws -> Result {
        guard iterations > 0 else { throw JourneyError.invalidIterationCount }
        let baselineWindowCount = liveWindowCount()
        var openIdentity: Int?
        var capturedSnapshots = 0
        var completedIterations = 0
        defer {
            if let openIdentity { closeWindow(openIdentity) }
        }

        for tick in 0..<iterations {
            try Task.checkCancellation()
            let identity = try openWindow()
            openIdentity = identity
            try await sleep(.milliseconds(250))
            guard liveWindowCount() == baselineWindowCount + 1 else {
                throw JourneyError.windowDidNotOpen
            }
            guard try !capture(identity, tick).isEmpty else {
                throw JourneyError.snapshotCaptureFailed
            }
            capturedSnapshots += 1

            closeWindow(identity)
            try await sleep(.milliseconds(150))
            guard liveWindowCount() == baselineWindowCount else {
                throw JourneyError.windowDidNotClose
            }
            openIdentity = nil
            completedIterations += 1
            try await observe(completedIterations)
        }

        return Result(
            completedIterations: completedIterations,
            capturedSnapshots: capturedSnapshots)
    }
}
