import CoreGraphics
import Foundation
import Observation
import VitrineRendering

/// Tracks asynchronous preview rendering without treating a renderer failure as an
/// indefinitely running operation.
@Observable
final class ComparisonBoardPreview {
    enum Phase: Equatable {
        case rendering
        case ready
        case invalid
        case failed
    }

    private(set) var asset: RenderedAsset?
    /// Where the captions sit in `asset`, in its pixels. Set with the asset so a click on
    /// the preview always targets what is drawn, not a newer layout still rendering.
    private(set) var captionFrames: [UUID: CGRect] = [:]
    /// The divider `asset` draws, set with it for the same reason.
    private(set) var wipe: ComparisonBoardComposer.Wipe?
    private(set) var phase: Phase = .rendering
    @ObservationIgnored private var lastDividerPercent: Int?

    static let debounce: Duration = .milliseconds(80)

    /// A held-down drag would keep resetting the debounce, so only a divider move skips it.
    func debounce(dividerPercent: Int) -> Duration {
        defer { lastDividerPercent = dividerPercent }
        guard let lastDividerPercent, lastDividerPercent != dividerPercent else {
            return Self.debounce
        }
        return .zero
    }

    func refresh(
        isValid: Bool,
        keepsLastFrame: Bool = false,
        debounce: Duration = ComparisonBoardPreview.debounce,
        captionFrames: () -> [UUID: CGRect] = { [:] },
        wipe: () -> ComparisonBoardComposer.Wipe? = { nil },
        render: () throws -> RenderedAsset
    ) async {
        guard isValid else {
            // Clearing a caption inline must not pull the field out from under the typing.
            if !keepsLastFrame { clear() }
            phase = .invalid
            return
        }

        phase = .rendering
        do {
            try await Task.sleep(for: debounce)
            try Task.checkCancellation()
            asset = try render()
            self.captionFrames = captionFrames()
            self.wipe = wipe()
            phase = .ready
        } catch is CancellationError {
            return
        } catch {
            clear()
            phase = .failed
        }
    }

    private func clear() {
        asset = nil
        captionFrames = [:]
        wipe = nil
    }
}
