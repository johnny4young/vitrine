import Foundation

/// Opt-in lifecycle journey for documents above the interactive-highlighting ceiling.
///
/// Every iteration publishes one distinct large Swift source through the production
/// editor model, captures the live window, restores the baseline document, and only
/// then records a settled footprint sample. It exercises large-document fallback and
/// SwiftUI text teardown without retaining the generated sources as evidence.
struct MemoryLargeDocumentCycleJourney {
    struct Result: Equatable {
        let completedIterations: Int
        let uniqueSnapshots: Int
    }

    enum JourneyError: Error, Equatable {
        case invalidIterationCount
        case snapshotCaptureFailed
        case duplicateSnapshot
    }

    static let journeyID = "large-document-cycle"
    static let completionMarker = "VITRINE_MEMORY_LARGE_DOCUMENT_CYCLE_COMPLETE"
    static let defaultIterationCount = 20

    let settings: AppSettings
    let sleep: (Duration) async throws -> Void
    let capture: (Int) throws -> String
    let observe: (Int) async throws -> Void

    init(
        settings: AppSettings,
        sleep: @escaping (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        capture: @escaping (Int) throws -> String,
        observe: @escaping (Int) async throws -> Void = { _ in }
    ) {
        self.settings = settings
        self.sleep = sleep
        self.capture = capture
        self.observe = observe
    }

    func run(iterations: Int = defaultIterationCount) async throws -> Result {
        guard iterations > 0 else { throw JourneyError.invalidIterationCount }
        let baseline = settings.config
        var snapshots = Set<String>()
        var completedIterations = 0
        defer { settings.config = baseline }

        for tick in 0..<iterations {
            try Task.checkCancellation()
            var document = baseline
            document.code = Self.fixture(index: tick)
            document.language = .swift
            settings.config = document

            try await sleep(.milliseconds(250))
            let fingerprint = try capture(tick)
            guard !fingerprint.isEmpty else {
                throw JourneyError.snapshotCaptureFailed
            }
            guard snapshots.insert(fingerprint).inserted else {
                throw JourneyError.duplicateSnapshot
            }

            settings.config = baseline
            try await sleep(.milliseconds(150))
            completedIterations += 1
            try await observe(completedIterations)
        }

        return Result(
            completedIterations: completedIterations,
            uniqueSnapshots: snapshots.count)
    }

    private static func fixture(index: Int) -> String {
        let targetBytes = HighlightPolicy.maximumHighlightedByteCount * 2
        let line =
            "let value\(index) = compute(\(index)) // "
            + String(repeating: Character("x"), count: 220) + "\n"
        let repetitions = targetBytes / line.utf8.count + 1
        return "// Vitrine large-document memory cycle \(index)\n"
            + String(repeating: line, count: repetitions)
    }
}
