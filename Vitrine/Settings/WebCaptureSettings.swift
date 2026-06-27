import Foundation
import Observation

/// The web URL-capture viewport, capture-mode, wait, and consent settings (CS-044),
/// extracted from `AppSettings` into a focused sub-store (audit P2-1) so the main
/// settings object stays cohesive rather than accreting every feature's knobs. It is
/// held by `AppSettings`; because both are `@Observable`, SwiftUI surfaces that read
/// `settings.webCapture.<field>` observe the nested store directly, so a web-capture
/// edit refreshes them without any manual change-forwarding.
///
/// Persistence is unchanged from when these lived on `AppSettings`: every property reads
/// and writes the same `SettingsCodec.Keys` through the same defensively-clamped
/// `WebDefaults` helpers (CS-050), so a store written by an older build loads identically
/// and the settings schema/migration is untouched. The `web`/`url` prefixes the properties
/// carried as members of the god object are dropped here — the `webCapture` namespace now
/// supplies that context (`settings.webCapture.viewportKind`).
///
/// URL capture is a Product Phase 2 feature gated on the network entitlement, so these
/// settings have no effect in a Phase 1 build; they are still persisted with the same
/// discipline as every other setting so the choice survives across launches.
@Observable
final class WebCaptureSettings {
    private typealias Keys = SettingsCodec.Keys

    /// The viewport preset a URL capture lays the page out in (CS-044). Stored as a
    /// flat discriminant; the custom size rides in `customViewportWidth/Height`.
    var viewportKind: WebSnapshotConfig.ViewportPreset.Kind {
        didSet { defaults.set(viewportKind.rawValue, forKey: Keys.webViewportKind) }
    }

    /// The set of viewports a multi-resolution capture renders, ordered and
    /// de-duplicated (CS-044). An empty set falls back to the single `viewportKind`
    /// on read, so the multi-select degrades to today's single-viewport capture.
    var viewports: [WebSnapshotConfig.ViewportPreset.Kind] {
        didSet { defaults.set(viewports.map(\.rawValue), forKey: Keys.webViewports) }
    }

    /// The custom viewport width in points, used only when `viewportKind` is
    /// `.custom` (CS-044). Clamped into the safe range on read.
    var customViewportWidth: Int {
        didSet { defaults.set(customViewportWidth, forKey: Keys.webCustomViewportWidth) }
    }

    /// The custom viewport height in points, used only when `viewportKind` is
    /// `.custom` (CS-044). Clamped into the safe range on read.
    var customViewportHeight: Int {
        didSet { defaults.set(customViewportHeight, forKey: Keys.webCustomViewportHeight) }
    }

    /// Whether a URL capture grabs the visible viewport or the full scrollable page
    /// (CS-044). The default is the deterministic visible viewport.
    var captureMode: WebSnapshotConfig.CaptureMode {
        didSet { defaults.set(captureMode.rawValue, forKey: Keys.webCaptureMode) }
    }

    /// Which wait strategy a URL capture uses before snapshotting (CS-044). Stored
    /// as a flat discriminant; the post-load delay rides in `waitSeconds`.
    var waitKind: WebSnapshotConfig.WaitStrategy.Kind {
        didSet { defaults.set(waitKind.rawValue, forKey: Keys.webWaitKind) }
    }

    /// The post-load wait, in seconds, for the fixed-delay and network-quiet
    /// strategies (CS-044). Ignored by `.domContentLoaded`. Clamped non-negative.
    var waitSeconds: Int {
        didSet { defaults.set(waitSeconds, forKey: Keys.webWaitSeconds) }
    }

    /// Whether the user has confirmed the first-use URL-capture privacy disclosure
    /// (CS-045). URL capture loads a webpage over the network, so the first attempt
    /// shows `WebPrivacyDisclosureView` and only proceeds once this is set. The
    /// Settings transparency row revokes it (back to `false`), re-arming the
    /// disclosure. Defaults off so a fresh install always discloses before the first
    /// network capture.
    var consentGiven: Bool {
        didSet { defaults.set(consentGiven, forKey: Keys.urlCaptureConsent) }
    }

    /// The composed viewport preset for a URL capture (CS-044): the persisted
    /// discriminant resolved with the stored custom size, defensively clamped so a
    /// custom preset is always a usable, memory-safe size.
    var viewportPreset: WebSnapshotConfig.ViewportPreset {
        .resolve(
            kind: viewportKind,
            customWidth: customViewportWidth,
            customHeight: customViewportHeight)
    }

    /// The composed viewport presets for a multi-resolution capture (CS-044): each
    /// selected kind resolved with the stored custom size (so a selected `.custom`
    /// carries the user's width/height). Falls back to the single `viewportPreset`
    /// when the selection is empty, so a batch capture always has at least one size.
    var selectedViewportPresets: [WebSnapshotConfig.ViewportPreset] {
        // De-duplicate by kind (stable, keep-first) before resolving: `viewports` is an
        // unconstrained stored array, and a repeated kind would otherwise render — and
        // compose into the responsive board — the same viewport twice. The UI toggle already
        // avoids duplicates, so this enforces the documented invariant defensively and keeps a
        // batch capture deterministic.
        var seen = Set<WebSnapshotConfig.ViewportPreset.Kind>()
        let presets =
            viewports
            .filter { seen.insert($0).inserted }
            .map {
                WebSnapshotConfig.ViewportPreset.resolve(
                    kind: $0,
                    customWidth: customViewportWidth,
                    customHeight: customViewportHeight)
            }
        return presets.isEmpty ? [viewportPreset] : presets
    }

    /// The composed wait strategy for a URL capture (CS-044): the persisted
    /// discriminant resolved with the stored post-load delay.
    var waitStrategy: WebSnapshotConfig.WaitStrategy {
        .resolve(kind: waitKind, extraWaitSeconds: waitSeconds)
    }

    private let defaults: UserDefaults

    /// Seeds every property from `defaults` through the defensive `WebDefaults` reads
    /// (CS-050): a missing or garbage value falls back to the documented default and
    /// numeric values are clamped into the safe range, so loading from empty, partial,
    /// or corrupt defaults always yields a usable configuration.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        viewportKind = WebDefaults.viewportKind(from: defaults)
        viewports = WebDefaults.viewports(from: defaults)
        customViewportWidth = WebDefaults.customViewportWidth(from: defaults)
        customViewportHeight = WebDefaults.customViewportHeight(from: defaults)
        captureMode = WebDefaults.captureMode(from: defaults)
        waitKind = WebDefaults.waitKind(from: defaults)
        waitSeconds = WebDefaults.waitSeconds(from: defaults)
        // Off on a fresh suite, so the first URL capture always shows the privacy
        // disclosure before reaching the network (CS-045).
        consentGiven = defaults.object(forKey: Keys.urlCaptureConsent) as? Bool ?? false
    }

    /// Restores every web-capture setting to its factory default (CS-050), driven by
    /// `AppSettings.resetToDefaults()`. The persisted keys are cleared by that caller's
    /// key sweep; this resets the live published state so the UI updates at once. A full
    /// reset returns consent to the pre-disclosure state, re-arming the disclosure.
    func resetToDefaults() {
        viewportKind = WebDefaults.viewportKind
        viewports = WebDefaults.viewports
        customViewportWidth = WebDefaults.customViewportWidth
        customViewportHeight = WebDefaults.customViewportHeight
        captureMode = WebDefaults.captureMode
        waitKind = WebDefaults.waitKind
        waitSeconds = WebDefaults.waitSeconds
        consentGiven = false
    }
}
