import Foundation
import ImageIO
import VitrineDomain

/// Which export formats the running Mac can actually encode.
///
/// This lives in the rendering layer on purpose. Encodability is a runtime property of
/// the host's ImageIO writers — macOS Sequoia recognizes `public.avif` as a type but
/// ships no AVIF destination writer, Tahoe does — so it is neither portable nor
/// deterministic. Keeping the probe out of `VitrineDomain` leaves the value type pure
/// and lets hostless domain tests run without depending on the host's codec set.
extension ExportFormat {
    /// Whether the active OS ImageIO stack can faithfully produce this format.
    ///
    /// A declared `UTType` is not enough: querying the actual destination identifiers
    /// keeps the UI and persisted settings aligned with the codec available on the
    /// running Mac without brittle OS-version checks.
    public nonisolated var isEncodingAvailable: Bool {
        switch self {
        case .png, .pdf:
            true
        case .heic:
            Self.imageIODestinationIdentifiers.contains("public.heic")
        case .avif:
            Self.imageIODestinationIdentifiers.contains("public.avif")
        }
    }

    /// Formats safe to offer in interactive pickers on the running Mac.
    public nonisolated static var availableCases: [ExportFormat] {
        allCases.filter(\.isEncodingAvailable)
    }

    /// Keeps a persisted or imported choice usable on the active OS.
    public nonisolated var availableOrFallback: ExportFormat {
        isEncodingAvailable ? self : .png
    }

    /// Decodes a persisted value and falls back when this Mac cannot encode it.
    public nonisolated static func resolveAvailable(_ rawValue: String?) -> ExportFormat {
        resolve(rawValue).availableOrFallback
    }

    /// ImageIO registers writers once for the process; cache the immutable capability
    /// set instead of rebuilding it on every SwiftUI picker evaluation.
    private nonisolated static let imageIODestinationIdentifiers = Set(
        CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
}
