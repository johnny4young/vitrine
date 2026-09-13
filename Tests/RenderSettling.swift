import Foundation

/// Bounded re-rendering for the pixel-strict suites in both unit-test bundles.
///
/// A strict, pinned-image check re-renders on a settled run loop before it treats a
/// mismatch as a genuine regression. Each scenario renders identically in isolation, but a
/// full `make test` run rasterizes while hundreds of other tests share the process.
/// Registering or unregistering a font anywhere in that process posts an **asynchronous**
/// Core Text fonts-changed notification. If the run loop services it while a scenario is
/// rasterizing, it invalidates the glyph caches mid-render and can nudge a content-hugging
/// layout by a sub-point: a 1px height drift, or a band of anti-aliased edge pixels. That is
/// contention, not a render bug.
///
/// Each retry first delivers any in-flight notification while no render is running, then
/// renders again against rebuilt caches. The check stays strict: a real regression shifts
/// every frame and still fails, and only an environment-perturbed frame clears on a settled
/// re-render.
enum RenderSettling {
    /// How many renders a strict check tries before it reports the last frame as a mismatch.
    static let strictRenderAttempts = 5

    /// Delivers any in-flight Core Text fonts-changed notification by briefly spinning the
    /// main run loop, so the next render rasterizes against stable glyph caches.
    static func settleFontCaches() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
}
