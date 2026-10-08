import Foundation

/// Decides when a page has gone network-quiet from periodic samples: loaded, no
/// fetch/XHR in flight, and no new resource started, held for a full idle window.
struct NetworkQuietTracker {
    struct Sample: Equatable {
        var isComplete: Bool
        var pendingRequests: Int
        var resourceCount: Int
    }

    let idleWindow: Duration
    private var settledSince: ContinuousClock.Instant?
    private var lastResourceCount: Int?

    init(idleWindow: Duration) {
        self.idleWindow = idleWindow
    }

    /// Records `sample` taken at `now` and returns whether the page has stayed quiet
    /// for the whole idle window.
    mutating func record(_ sample: Sample, at now: ContinuousClock.Instant) -> Bool {
        let resourcesSettled = lastResourceCount == sample.resourceCount
        lastResourceCount = sample.resourceCount
        guard sample.isComplete, sample.pendingRequests == 0, resourcesSettled else {
            settledSince = nil
            return false
        }
        let since = settledSince ?? now
        settledSince = since
        return since.duration(to: now) >= idleWindow
    }
}
