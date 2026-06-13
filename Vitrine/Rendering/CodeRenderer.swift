import CoreGraphics
import Foundation
import OSLog

/// The Phase 1 renderer: turns a `.code` input into a framed, syntax-highlighted
/// image (CS-040). It is a thin, network-free wrapper over the existing render
/// path (`ExportManager.renderCGImage` → `SnapshotCanvas` → ImageIO color
/// tagging), placed behind the `Renderer` abstraction so code rendering can evolve
/// independently of the Phase 2 web paths.
///
/// The renderer reads only the snapshot configuration it is handed; it never
/// touches the network, the clipboard, or any URL configuration, which is what the
/// CS-040 acceptance test asserts.
struct CodeRenderer: Renderer {
    /// Output scale (1/2/3), matching `ExportManager`'s default.
    var scale: CGFloat = 2

    /// Optional fixed layout size for size-preset framing (e.g. OpenGraph
    /// 1200×630). `nil` lets the canvas size to its content (CS-020).
    var fixedSize: CGSize?

    /// Color profile to tag the output with — sRGB by default (CS-024).
    var profile: ColorProfile = .sRGB

    /// Accepts only the code input; URL and HTML are handled by their own
    /// renderers (`URLRenderer` / `HTMLRenderer`).
    func canRender(_ input: CaptureInput) -> Bool {
        if case .code = input { return true }
        return false
    }

    /// Renders a `.code` input to a `RenderedAsset`.
    ///
    /// The supplied `config` carries the look (theme, font, background, padding);
    /// this method overlays the input's text and — when the detector supplied one
    /// — its language hint, so the renderer honors classification done upstream
    /// without re-detecting. Rejecting any non-code input throws
    /// `RenderError.noRendererFor`; a render that yields no image throws
    /// `RenderError.renderFailed` rather than returning a blank picture.
    func render(_ input: CaptureInput, config: SnapshotConfig) async throws -> RenderedAsset {
        guard case .code(let text, let languageHint) = input else {
            throw RenderError.noRendererFor(kind: input.diagnosticKind)
        }

        var resolved = config
        resolved.code = text
        if let languageHint { resolved.language = languageHint }

        guard
            let cgImage = ExportManager.renderCGImage(
                resolved, scale: scale, fixedSize: fixedSize, profile: profile)
        else {
            // Non-PII only: the language and a length measure, never the code.
            Log.render.error(
                "CodeRenderer produced no image (\(resolved.language.rawValue, privacy: .public), \(resolved.code.count, privacy: .public) chars)"
            )
            throw RenderError.renderFailed
        }
        return RenderedAsset(cgImage: cgImage, profile: profile)
    }
}
