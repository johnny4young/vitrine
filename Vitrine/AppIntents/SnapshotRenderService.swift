import AppKit
import Foundation
import OSLog

/// Renders a `SnapshotRenderRequest` into image data or an `NSImage` through the
/// **unchanged** app render path, for every automation surface (App Intents and the
/// Services menu, CS-034).
///
/// Like the CLI's `CLIRenderer`, this is a thin shell around `ExportManager` over a
/// `SnapshotCanvas`: it adds only the request → config resolution and the
/// empty-input guard, never re-implementing rendering, so an automation render is
/// byte-for-byte the same pipeline the editor and quick capture use. Automation
/// therefore inherits the same privacy and sandbox posture as the app — rendering is
/// fully local, needs no network, screen recording, or Accessibility, and writes
/// nothing to disk on its own (CS-034 "automation does not bypass the same privacy
/// and sandbox constraints as the app").
///
/// `@MainActor` because `ImageRenderer` and Highlightr require AppKit on the main
/// actor; App Intents `perform()` and the Services provider both run there.
@MainActor
enum SnapshotRenderService {
    /// A reason a request could not be turned into an image, mapped to clear,
    /// user-facing copy for an App Intent error or a Services failure (CS-034).
    enum RenderError: Error, Equatable, CustomStringConvertible {
        /// The request carried no usable (non-empty) code to render.
        case emptyCode
        /// Rendering or encoding produced no image (an internal renderer failure).
        case renderFailed

        var description: String {
            switch self {
            case .emptyCode:
                "There is no code to render. Provide some text first."
            case .renderFailed:
                "Vitrine could not render an image from that code."
            }
        }
    }

    /// Renders `request` to encoded image data in its chosen format.
    ///
    /// Raster formats go through `renderCGImage` + ImageIO (honoring the scale,
    /// fixed size, and color profile); PDF uses `pdfData`. Throws
    /// `RenderError.emptyCode` for empty input and `RenderError.renderFailed` when
    /// the pipeline yields nothing, so a caller never has to interpret a bare `nil`.
    static func renderData(_ request: SnapshotRenderRequest) throws -> Data {
        guard request.hasRenderableCode else { throw RenderError.emptyCode }
        let config = request.makeConfig()

        let data = ExportManager.encodedPayload(
            request.format,
            png: {
                ExportManager.renderCGImage(
                    config, scale: request.effectiveScale, fixedSize: request.fixedSize,
                    profile: request.profile)
            },
            pdf: { ExportManager.pdfData(config, fixedSize: request.fixedSize) }
        )?.data

        guard let data else {
            Log.export.error(
                "Automation render produced no \(request.format.rawValue, privacy: .public)")
            throw RenderError.renderFailed
        }
        Log.export.notice(
            "Automation rendered an image (\(request.format.rawValue, privacy: .public))")
        return data
    }

    /// Renders `request` to a `CGImage` — the raster the Services menu hands back
    /// through the pasteboard. Honors the chosen scale, fixed size, and sRGB profile.
    /// Returning the `CGImage` lets the caller PNG-encode through the color-managed
    /// ImageIO path (`ExportManager.pngData`) rather than a legacy TIFF/
    /// `NSBitmapImageRep` round-trip (AGENTS.md, C1). Throws the same errors as
    /// `renderData`.
    static func renderCGImage(_ request: SnapshotRenderRequest) throws -> CGImage {
        guard request.hasRenderableCode else { throw RenderError.emptyCode }
        let config = request.makeConfig()
        guard
            let cgImage = ExportManager.renderCGImage(
                config, scale: request.effectiveScale, fixedSize: request.fixedSize,
                profile: request.profile)
        else {
            Log.export.error("Automation render produced no image")
            throw RenderError.renderFailed
        }
        Log.export.notice("Automation rendered an image for the Services menu")
        return cgImage
    }

    /// Renders `request` to an `NSImage` — a convenience over `renderCGImage` for
    /// callers that want an image object. Throws the same errors as `renderData`.
    static func renderImage(_ request: SnapshotRenderRequest) throws -> NSImage {
        let cgImage = try renderCGImage(request)
        return NSImage(
            cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
