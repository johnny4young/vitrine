import CoreGraphics
import Foundation

/// Exported image format (Output).
///
/// The format menu lists only outputs the exporter can write **faithfully** from
/// the full code canvas: raster `png`/`heic`/`avif` and a true vector `pdf`. SVG is
/// deliberately absent: SwiftUI / `ImageRenderer` / AppKit expose no
/// faithful full-canvas SVG path, and Vitrine does not ship a fake `.svg` that is
/// merely a raster PNG wrapped in an `<image>` tag. PDF is therefore the supported
/// vector format. A hand-authored SVG exists only for the deterministic
/// simple-template subset (`VectorTemplateSVG`) and is intentionally not a
/// general export choice here. See `docs/ARCHITECTURE.md` ("Vector export").
enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case png
    case pdf
    case heic
    case avif

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: "PNG"
        case .pdf: "PDF"
        case .heic: "HEIC"
        case .avif: "AVIF"
        }
    }

    /// The lowercase file extension for this format. The raw values already spell the
    /// extensions, but naming it makes call sites (save panels, multi-size export)
    /// self-documenting and keeps them from hard-coding a literal.
    var fileExtension: String { rawValue }

    /// Whether this format is a scalable vector format (true for `pdf`).
    ///
    /// Drives the "vector" label/help shown next to the format picker so the menu
    /// states honestly which output is resolution-independent. Raster PNG,
    /// HEIC, and AVIF are `false`; PDF is `true`.
    var isVector: Bool {
        switch self {
        case .png, .heic, .avif: false
        case .pdf: true
        }
    }

    /// One-line guidance shown next to the format picker, naming the vector option
    /// so docs/slide workflows know which export scales.
    var summary: String {
        switch self {
        case .png: "Raster image at the chosen resolution. Best for posting and chat."
        case .pdf: "Scalable vector document. Best for docs, slides, and print."
        case .heic: "Compressed raster image, much smaller than PNG. Best for docs sites."
        case .avif: "Modern compressed raster image with alpha. Best for web publishing."
        }
    }

    /// The value used when nothing is persisted or a stored string no longer
    /// maps to a case (documented fallback).
    static let fallback: ExportFormat = .png

    /// Decodes a persisted raw value, tolerating `nil` or an unrecognized
    /// string by returning `fallback`.
    static func resolve(_ rawValue: String?) -> ExportFormat {
        ExportFormat(rawValue: rawValue ?? "") ?? fallback
    }
}

/// The ICC color profile a PNG export is rendered and tagged with.
///
/// `sRGB` is the default because it is the safe, universally understood space:
/// browsers, Slack, X, Keynote, and non–color-managed viewers all assume sRGB,
/// so a screenshot looks the same everywhere. `displayP3` is offered only as an
/// explicit advanced option — it keeps the wider gamut of a P3 display, but a
/// viewer that ignores the embedded profile renders P3 values as if they were
/// sRGB, which oversaturates the image. Both profiles preserve the alpha channel
/// on export; neither flattens transparency against a matte.
enum ColorProfile: String, CaseIterable, Identifiable, Codable {
    case sRGB
    case displayP3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sRGB: "sRGB"
        case .displayP3: "Display P3 (advanced)"
        }
    }

    /// One-line guidance shown next to the advanced picker.
    var summary: String {
        switch self {
        case .sRGB: "Best for the web, Slack, X, and slides. Looks the same everywhere."
        case .displayP3:
            "Wider gamut for P3 displays. Can oversaturate in apps that ignore the profile."
        }
    }

    /// The Core Graphics color space the rendered image is converted to and
    /// tagged with before PNG encoding. Both are device-independent ICC spaces,
    /// so the embedded profile travels with the file.
    var cgColorSpace: CGColorSpace? {
        switch self {
        case .sRGB: CGColorSpace(name: CGColorSpace.sRGB)
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)
        }
    }

    /// The default profile: sRGB. PNG export defaults to sRGB so output is
    /// predictable across displays, apps, and social platforms.
    static let fallback: ColorProfile = .sRGB

    /// Decodes a persisted raw value, tolerating `nil` or an unrecognized
    /// string by returning `fallback` (documented fallback).
    static func resolve(_ rawValue: String?) -> ColorProfile {
        ColorProfile(rawValue: rawValue ?? "") ?? fallback
    }
}
