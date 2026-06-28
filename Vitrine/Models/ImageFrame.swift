import Foundation

/// The frame drawn around a beautified image — the "beautify any image" feature.
///
/// When `SnapshotConfig.foregroundImage` is set, the canvas renders that image as the
/// card body wrapped in one of these frames, on the same background / padding / shadow
/// the code path uses. `none` and `macOSWindow` are free; `browser` (and future device
/// mockups) are PRO.
///
/// Raw values are stable strings so the choice round-trips through the editor window
/// state, and an unknown value (a hand-edited store, or a frame added in a newer build)
/// decodes back to `.none` rather than failing.
enum ImageFrame: String, Codable, CaseIterable, Identifiable, Sendable {
    /// No frame — just the image on the background.
    case none
    /// A macOS window: traffic-light dots and an optional title bar (free).
    case macOSWindow
    /// A browser window: traffic-light dots plus a faux address bar (PRO).
    case browser

    var id: String { rawValue }

    /// Whether this frame is gated behind Vitrine PRO. The plain image and the macOS
    /// window are free (fidelity to "the free tier loses nothing"); the richer browser
    /// frame is the gentle upsell.
    var isPro: Bool {
        switch self {
        case .none, .macOSWindow: false
        case .browser: true
        }
    }
}
