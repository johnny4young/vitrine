import CoreGraphics
import Foundation

/// One-click image-size/style presets for the surfaces developers actually post
/// to.
///
/// A preset is **presentation/output only**: applying one mutates the snapshot's
/// look (padding, background) and pins an exact output size and scale, but it
/// never touches `code` or `language`. The user's source is sacred; a preset
/// only reframes how it is rendered. This keeps switching presets a safe,
/// reversible operation that never risks the thing being captured. Every shipped
/// destination pins a `.fixed` canvas at its platform's native pixels, so the
/// export is exactly the shape its name promises (e.g. X / Twitter is 1600×900);
/// the code card is centered and the background fills the frame (see SnapshotCanvas).
struct ExportPreset: Identifiable, Hashable {
    /// Stable identifier persisted in preferences and used for menu tags.
    let id: String
    /// Human-readable name shown in the picker (e.g. "X / Twitter").
    let displayName: String
    /// One-line guidance shown as help text next to the picker.
    let summary: String
    /// How the rendered canvas should be sized for this destination.
    let sizing: Sizing
    /// Export resolution multiplier the destination expects. Fixed-size presets
    /// (OpenGraph) pin this to `1` so the logical and pixel sizes match.
    let scale: Int
    /// Background guidance: the canvas background a preset suggests, or `nil`
    /// to leave the user's current background untouched.
    let background: BackgroundStyle?
    /// Canvas padding guidance, in points, applied to `SnapshotConfig.padding`.
    let padding: Double

    /// How a preset constrains the rendered canvas size.
    enum Sizing: Hashable {
        /// Render at an exact logical-pixel canvas (width × height). The exporter
        /// fills this frame precisely; OpenGraph uses 1200×630.
        case fixed(width: Double, height: Double)
        /// Recommend an aspect ratio (width:height) without forcing a size; the
        /// canvas still hugs its content. The content-hugging alternative to
        /// `.fixed`. No shipped destination uses it because current destinations pin
        /// exact pixels, but imported presets can still express a content-hugging shape.
        case aspect(width: Double, height: Double)

        /// The exact logical pixel size to render, when the preset pins one.
        var fixedSize: CGSize? {
            if case .fixed(let width, let height) = self {
                return CGSize(width: width, height: height)
            }
            return nil
        }

        /// The width:height ratio this preset targets, for both fixed and
        /// aspect sizing. Never zero (every preset declares positive dimensions).
        var aspectRatio: Double {
            switch self {
            case .fixed(let width, let height), .aspect(let width, let height):
                height == 0 ? 1 : width / height
            }
        }
    }

    /// Applies this preset's presentation/output guidance to `config` in place.
    ///
    /// Only presentation fields are written: padding and (when the preset
    /// declares one) the background. `code` and `language` are never read or
    /// modified, so applying a preset can never alter the user's source.
    func apply(to config: inout SnapshotConfig) {
        config.padding = SettingsDefaults.clampPadding(padding)
        if let background {
            config.background = background
        }
    }

    /// Whether `config` already matches everything this preset would apply, so
    /// the picker can reflect the active preset (and fall back to "Custom" once
    /// the user diverges). Scale is compared by the caller, which owns it.
    func matches(_ config: SnapshotConfig) -> Bool {
        guard config.padding == SettingsDefaults.clampPadding(padding) else { return false }
        if let background, config.background != background { return false }
        return true
    }
}

extension ExportPreset {
    /// X / Twitter timeline image — the 16:9 in-stream card at its native
    /// 1600×900 pixels, so the export is exactly the shape the timeline shows.
    static let twitter = ExportPreset(
        id: "twitter",
        displayName: "X / Twitter",
        summary: "1600×900 (16:9) in-stream card.",
        sizing: .fixed(width: 1600, height: 900),
        scale: 1,
        background: .gradient(.aurora),
        padding: 40
    )

    /// LinkedIn feed image — the platform's 1.91:1 link-card shape at 1200×628.
    static let linkedIn = ExportPreset(
        id: "linkedin",
        displayName: "LinkedIn",
        summary: "1200×628 (1.91:1) feed image.",
        sizing: .fixed(width: 1200, height: 628),
        scale: 1,
        background: .gradient(.ocean),
        padding: 40
    )

    /// Keynote / slide deck — a full 1920×1080 (16:9) surface for presentations.
    static let keynote = ExportPreset(
        id: "keynote",
        displayName: "Keynote",
        summary: "1920×1080 (16:9) slide with generous padding.",
        sizing: .fixed(width: 1920, height: 1080),
        scale: 1,
        background: .gradient(.night),
        padding: 56
    )

    /// Docs / blog — a tighter image that drops into prose without dominating it.
    /// Leaves the background as-is so it can match a site's theme.
    static let docs = ExportPreset(
        id: "docs",
        displayName: "Docs / Blog",
        summary: "1200×800 (3:2) image for inline docs and blog posts.",
        sizing: .fixed(width: 1200, height: 800),
        scale: 1,
        background: nil,
        padding: 24
    )

    /// Transparent slide — real alpha for dropping onto any deck background.
    /// Pairs transparency with no drop shadow downstream guidance.
    static let transparentSlide = ExportPreset(
        id: "transparent-slide",
        displayName: "Transparent Slide",
        summary: "1920×1080 (16:9) transparent layer for any slide.",
        sizing: .fixed(width: 1920, height: 1080),
        scale: 1,
        background: .transparent,
        padding: 48
    )

    /// OpenGraph card — exactly 1200×630 logical pixels at 1×. The
    /// canonical link-preview size for X, Slack, Discord, and most CMSs.
    static let openGraph = ExportPreset(
        id: "opengraph",
        displayName: "OpenGraph 1200×630",
        summary: "Exact 1200×630 link-preview card at 1×.",
        sizing: .fixed(width: 1200, height: 630),
        scale: 1,
        background: .gradient(.aurora),
        padding: 56
    )

    /// Instagram Story / Reels cover — the 9:16 vertical canvas at 1080×1920.
    static let instagramStory = ExportPreset(
        id: "instagram-story",
        displayName: "Instagram Story",
        summary: "1080×1920 (9:16) vertical story.",
        sizing: .fixed(width: 1080, height: 1920),
        scale: 1,
        background: .gradient(.sunset),
        padding: 64
    )

    /// GitHub README banner — a wide 2:1 header image at 1280×640.
    static let githubBanner = ExportPreset(
        id: "github-banner",
        displayName: "GitHub Banner",
        summary: "1280×640 (2:1) README header image.",
        sizing: .fixed(width: 1280, height: 640),
        scale: 1,
        background: .gradient(.carbon),
        padding: 48
    )

    /// All presets, in picker order.
    static let all: [ExportPreset] = [
        .twitter, .linkedIn, .keynote, .docs, .transparentSlide, .openGraph,
        .instagramStory, .githubBanner,
    ]

    /// Looks up a preset by id, returning `nil` for an unknown or absent id so
    /// the caller can present "Custom" (no preset applied).
    static func preset(withID id: String?) -> ExportPreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
