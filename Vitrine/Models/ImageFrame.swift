import Foundation

/// The frame drawn around a beautified image — the "beautify any image" feature.
///
/// When `SnapshotConfig.foregroundImage` is set, the canvas renders that image as the
/// card body wrapped in one of these frames, on the same background / padding / shadow
/// the code path uses. `none` and `macOSWindow` are free; `browser` and the device
/// mockups (`macBook`, `iPhone`) are PRO.
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
    /// A laptop mockup: the image as the screen, with a thin bezel and a hinge base (PRO).
    case macBook
    /// A phone mockup: the image as the screen, with a bezel and a Dynamic Island (PRO).
    case iPhone

    var id: String { rawValue }

    /// Whether this frame draws a hardware **device** mockup (vs. plain/window chrome).
    /// Device frames size themselves to the device aspect and fill the screen with the
    /// image, rather than sizing to the image.
    var isDevice: Bool {
        switch self {
        case .macBook, .iPhone: true
        case .none, .macOSWindow, .browser: false
        }
    }

    /// Whether this frame is gated behind Vitrine PRO. The plain image and the macOS
    /// window are free (fidelity to "the free tier loses nothing"); the richer browser
    /// and device frames are the gentle upsell.
    var isPro: Bool {
        switch self {
        case .none, .macOSWindow: false
        case .browser, .macBook, .iPhone: true
        }
    }
}

/// The chrome tint for a framed image. `auto` samples the image's top edge so the bar
/// "continues" the screenshot (no jarring light-bar-over-dark-content seam); `light` and
/// `dark` are fixed manual overrides. Drives the window/browser bar colors and the
/// device-mockup body tint.
enum FrameAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Derive the chrome from the image's own top-edge color (the default).
    case auto
    case light
    case dark

    var id: String { rawValue }
}
