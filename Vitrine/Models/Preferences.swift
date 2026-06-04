import CoreGraphics
import Foundation

/// What the global hotkey triggers (CS-002).
enum HotkeyAction: String, CaseIterable, Identifiable, Codable {
    case quickCapture
    case openEditor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quickCapture: "Quick capture from clipboard"
        case .openEditor: "Open the editor"
        }
    }

    /// The value used when nothing is persisted or a stored string no longer
    /// maps to a case (CS-050 documented fallback).
    static let fallback: HotkeyAction = .quickCapture

    /// Decodes a persisted raw value, tolerating `nil` or an unrecognized
    /// string by returning `fallback`.
    static func resolve(_ rawValue: String?) -> HotkeyAction {
        HotkeyAction(rawValue: rawValue ?? "") ?? fallback
    }
}

/// Exported image format (CS-010 · Output).
enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case png
    case pdf

    var id: String { rawValue }
    var displayName: String { self == .png ? "PNG" : "PDF" }

    /// The value used when nothing is persisted or a stored string no longer
    /// maps to a case (CS-050 documented fallback).
    static let fallback: ExportFormat = .png

    /// Decodes a persisted raw value, tolerating `nil` or an unrecognized
    /// string by returning `fallback`.
    static func resolve(_ rawValue: String?) -> ExportFormat {
        ExportFormat(rawValue: rawValue ?? "") ?? fallback
    }
}

/// The ICC color profile a PNG export is rendered and tagged with (CS-024).
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
    /// predictable across displays, apps, and social platforms (CS-024).
    static let fallback: ColorProfile = .sRGB

    /// Decodes a persisted raw value, tolerating `nil` or an unrecognized
    /// string by returning `fallback` (CS-050 documented fallback).
    static func resolve(_ rawValue: String?) -> ColorProfile {
        ColorProfile(rawValue: rawValue ?? "") ?? fallback
    }
}
