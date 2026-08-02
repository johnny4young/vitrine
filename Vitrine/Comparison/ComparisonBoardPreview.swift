import Foundation
import Observation

/// Tracks asynchronous preview rendering without treating a renderer failure as an
/// indefinitely running operation.
@MainActor
@Observable
final class ComparisonBoardPreview {
    enum Phase: Equatable {
        case rendering
        case ready
        case invalid
        case failed
    }

    private(set) var asset: RenderedAsset?
    private(set) var phase: Phase = .rendering

    func refresh(
        isValid: Bool,
        debounce: Duration = .milliseconds(80),
        render: () throws -> RenderedAsset
    ) async {
        guard isValid else {
            asset = nil
            phase = .invalid
            return
        }

        phase = .rendering
        do {
            try await Task.sleep(for: debounce)
            try Task.checkCancellation()
            asset = try render()
            phase = .ready
        } catch is CancellationError {
            return
        } catch {
            asset = nil
            phase = .failed
        }
    }
}
