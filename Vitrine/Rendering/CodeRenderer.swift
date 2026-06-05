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
    /// renderers (the Phase 2 stubs today).
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

/// The explicit Phase 2 stub for URL and HTML inputs (CS-040). It accepts both
/// kinds so the coordinator routes them here, then throws a typed
/// `RenderError.deferredToPhase2` naming the ticket that will implement the real
/// renderer — never a blank image and never a `noRendererFor` that would imply the
/// input was unclassifiable.
///
/// Keeping the deferral *inside* a renderer (rather than as a special case in the
/// coordinator) means the seam stays uniform: when CS-042/CS-043 ship, the real
/// `HTMLRenderer` and `URLRenderer` simply replace this stub in the renderer list.
struct DeferredWebRenderer: Renderer {
    func canRender(_ input: CaptureInput) -> Bool {
        switch input {
        case .url, .html: true
        case .code: false
        }
    }

    /// The Phase 2 ticket each web input is deferred to — the single source of
    /// truth shared by both the synchronous probe (`deferralTicket`) and the error
    /// `render` throws, so they can never drift.
    ///
    // TODO: CS-043 — WKWebView snapshot of the URL.
    // TODO: CS-042 — local WKWebView render of HTML/CSS.
    func deferralTicket(for input: CaptureInput) -> String? {
        switch input {
        case .url: "CS-043"
        case .html: "CS-042"
        case .code: nil
        }
    }

    func render(_ input: CaptureInput, config: SnapshotConfig) async throws -> RenderedAsset {
        guard let ticket = deferralTicket(for: input) else {
            throw RenderError.noRendererFor(kind: input.diagnosticKind)
        }
        throw RenderError.deferredToPhase2(ticket: ticket)
    }
}
