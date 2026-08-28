import Foundation

/// Opt-in dynamic-memory journey for repeated real local-HTML WebKit sessions.
///
/// Every iteration renders distinct HTML through a newly-created `WebSnapshotView`,
/// which owns one non-persistent `WKWebView` and tears it down after the capture. The
/// injected renderer keeps the loop and cancellation contract unit-testable.
struct MemoryWebSnapshotCycleJourney {
    struct Result: Equatable {
        let completedIterations: Int
        let uniqueSnapshots: Int
    }

    enum JourneyError: Error, Equatable {
        case invalidIterationCount
        case duplicateSnapshot
    }

    static let completionMarker = "VITRINE_MEMORY_WEB_SNAPSHOT_CYCLE_COMPLETE"
    static let defaultIterationCount = 10

    let render: (Int) async throws -> String
    let sleep: (Duration) async throws -> Void

    init(
        render: @escaping (Int) async throws -> String,
        sleep: @escaping (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.render = render
        self.sleep = sleep
    }

    func run(iterations: Int = defaultIterationCount) async throws -> Result {
        guard iterations > 0 else { throw JourneyError.invalidIterationCount }
        var snapshots = Set<String>()

        for tick in 0..<iterations {
            try Task.checkCancellation()
            guard snapshots.insert(try await render(tick)).inserted else {
                throw JourneyError.duplicateSnapshot
            }
            try await sleep(.milliseconds(150))
        }

        return Result(
            completedIterations: iterations,
            uniqueSnapshots: snapshots.count)
    }
}
