import CoreGraphics
import Foundation
import OSLog

/// Renders a `.html` input to an image locally through `WKWebView`.
///
/// It slots into the `Renderer` abstraction so a coordinator routes HTML
/// to it exactly as it routes code to `CodeRenderer`. Rendering is fully
/// local — the offscreen `WebSnapshotView` it delegates to blocks remote loads for
/// pasted HTML and never touches the screen — so an HTML snapshot needs neither the
/// network entitlement nor Screen Recording permission.
///
/// The renderer reuses the exporter's color step: the bitmap WebKit
/// produces is normalized into and tagged with `profile`'s ICC color space, so an
/// HTML snapshot and a code snapshot carry the same predictable color and can flow
/// through the same clipboard, save, and share paths as a uniform `RenderedAsset`.
struct HTMLRenderer: Renderer {
    /// The viewport the HTML is laid out and snapshotted in. Fixed so the same HTML
    /// always renders to the same pixel size — the rendering contract requires this.
    /// Defaults to OpenGraph's 1200×630.
    var viewport: CGSize = CGSize(width: 1200, height: 630)

    /// Output scale (1/2/3), matching `ExportManager`'s default. The rendered image
    /// is `viewport × scale` device pixels.
    var scale: CGFloat = 2

    /// Color profile to tag the output with — sRGB by default.
    var profile: ColorProfile = .sRGB

    /// Whether remote (network) loads are allowed for the HTML. `false` (the
    /// default) blocks every remote request, keeping pasted HTML local; a caller
    /// flips this on only for HTML the user has explicitly allowed to reach the
    /// network.  owns the real URL network mode.
    var allowsNetwork: Bool = false

    /// An optional **local** base URL (a user-selected file or a bundled resource)
    /// for resolving relative asset references. `nil` (the default) loads with no
    /// base URL, so relative references cannot resolve to anything.
    var localBaseURL: URL?

    /// Accepts only the HTML input; code and URL are handled by their own renderers
    /// (`CodeRenderer` and 's URL renderer).
    func canRender(_ input: CaptureInput) -> Bool {
        if case .html = input { return true }
        return false
    }

    /// Renders a `.html` input to a `RenderedAsset`.
    ///
    /// The `config` is accepted for protocol symmetry with `CodeRenderer` but does
    /// not style the page — HTML carries its own CSS, so the snapshot is of the
    /// document as written, not of Vitrine's code frame. Rejecting any non-HTML
    /// input throws `RenderError.noRendererFor`; a load or snapshot failure surfaces
    /// the offscreen engine's typed `WebSnapshotError` mapped to
    /// `RenderError.renderFailed`, so the caller never receives a blank image.
    func render(_ input: CaptureInput, config: SnapshotConfig) async throws -> RenderedAsset {
        guard case .html(let html) = input else {
            throw RenderError.noRendererFor(kind: input.diagnosticKind)
        }

        let request = WebSnapshotView.Request(
            html: html,
            viewport: viewport,
            scale: scale,
            allowsNetwork: allowsNetwork,
            localBaseURL: localBaseURL)

        let rawImage: CGImage
        do {
            rawImage = try await WebSnapshotView().snapshot(of: request)
        } catch let error as WebSnapshotError {
            // Non-PII only: the typed failure mode and a length measure, never the
            // HTML body. A typed engine error becomes the abstraction's typed
            // `renderFailed`, distinct from a web capture deferral or an unroutable
            // input — and never a blank picture.
            Log.render.error(
                "HTMLRenderer failed to snapshot HTML (\(error.diagnosticReason, privacy: .public), \(html.count, privacy: .public) chars)"
            )
            throw RenderError.renderFailed
        }

        // Apply the same color normalization/tagging the exporter uses, so
        // an HTML snapshot carries the same predictable, profile-tagged color as a
        // code snapshot.
        let normalized = ExportManager.normalized(rawImage, to: profile)
        return RenderedAsset(cgImage: normalized, profile: profile)
    }
}

extension WebSnapshotError {
    /// A stable, non-PII label for the failure mode, for diagnostics. Never
    /// includes the HTML body — only the kind of failure.
    var diagnosticReason: String {
        switch self {
        case .invalidViewport: "invalid-viewport"
        case .invalidBaseURL: "invalid-base-url"
        case .loadFailed: "load-failed"
        case .timedOut: "timed-out"
        case .snapshotFailed: "snapshot-failed"
        case .networkIsolationUnavailable: "network-isolation-unavailable"
        }
    }
}
