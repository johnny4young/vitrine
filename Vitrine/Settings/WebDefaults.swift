import Foundation

/// Canonical defaults and defensive reads for the web URL-capture viewport and wait
/// settings (CS-044), mirroring `SettingsDefaults` for the rest of the store.
///
/// URL capture is a Product Phase 2 feature gated on the network entitlement, so
/// these settings have no effect in a Phase 1 build; they are still persisted with
/// the same versioned, defensively-read discipline as every other setting (CS-050),
/// so the choice survives across launches and a corrupt or hand-edited value can
/// never reach the renderer as a degenerate viewport or a negative wait.
enum WebDefaults {
    /// The default viewport: OpenGraph's social-card size.
    static let viewportKind: WebSnapshotConfig.ViewportPreset.Kind = .openGraph

    /// The default custom viewport, used only when the kind is `.custom`. Seeds the
    /// width/height fields with a sensible desktop-ish size the first time a user
    /// switches to a custom viewport.
    static let customViewportWidth = 1280
    static let customViewportHeight = 800

    /// The default capture mode: the deterministic visible viewport.
    static let captureMode: WebSnapshotConfig.CaptureMode = .visibleViewport

    /// The default wait strategy: snapshot as soon as the load settles.
    static let waitKind: WebSnapshotConfig.WaitStrategy.Kind = .domContentLoaded

    /// The default post-load wait seconds for a timed strategy.
    static let waitSeconds = WebSnapshotConfig.WaitStrategy.defaultExtraWaitSeconds

    /// Reads the persisted viewport kind, falling back to the default for a missing
    /// or unrecognized raw value.
    static func viewportKind(
        from defaults: UserDefaults
    )
        -> WebSnapshotConfig.ViewportPreset.Kind
    {
        guard let raw = defaults.string(forKey: "webViewportKind"),
            let kind = WebSnapshotConfig.ViewportPreset.Kind(rawValue: raw)
        else { return viewportKind }
        return kind
    }

    /// Reads the persisted custom viewport width, clamped into the safe range and
    /// falling back to the default for a missing or non-integer value.
    static func customViewportWidth(from defaults: UserDefaults) -> Int {
        guard let value = defaults.object(forKey: "webCustomViewportWidth") as? Int else {
            return customViewportWidth
        }
        return WebSnapshotConfig.ViewportPreset.clampCustomDimension(value)
    }

    /// Reads the persisted custom viewport height, clamped into the safe range and
    /// falling back to the default for a missing or non-integer value.
    static func customViewportHeight(from defaults: UserDefaults) -> Int {
        guard let value = defaults.object(forKey: "webCustomViewportHeight") as? Int else {
            return customViewportHeight
        }
        return WebSnapshotConfig.ViewportPreset.clampCustomDimension(value)
    }

    /// Reads the persisted capture mode, falling back to the default for a missing
    /// or unrecognized raw value.
    static func captureMode(from defaults: UserDefaults) -> WebSnapshotConfig.CaptureMode {
        guard let raw = defaults.string(forKey: "webCaptureMode"),
            let mode = WebSnapshotConfig.CaptureMode(rawValue: raw)
        else { return captureMode }
        return mode
    }

    /// Reads the persisted wait kind, falling back to the default for a missing or
    /// unrecognized raw value.
    static func waitKind(from defaults: UserDefaults) -> WebSnapshotConfig.WaitStrategy.Kind {
        guard let raw = defaults.string(forKey: "webWaitKind"),
            let kind = WebSnapshotConfig.WaitStrategy.Kind(rawValue: raw)
        else { return waitKind }
        return kind
    }

    /// Reads the persisted post-load wait seconds, clamped non-negative and bounded
    /// by the wait cap, falling back to the default for a missing or non-integer value.
    static func waitSeconds(from defaults: UserDefaults) -> Int {
        guard let value = defaults.object(forKey: "webWaitSeconds") as? Int else {
            return waitSeconds
        }
        return min(max(value, 0), waitSecondsRange.upperBound)
    }

    /// The inclusive bounds the post-load wait seconds are clamped into. The ceiling
    /// keeps the total wait comfortably inside the hard timeout cap so the picker can
    /// never seed a wait that would always hit the safety ceiling.
    static let waitSecondsRange = 0...30
}
