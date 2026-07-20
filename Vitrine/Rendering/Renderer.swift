import CoreGraphics
import Foundation

/// The product of a successful render: the image plus the facts a caller needs to
/// encode, copy, or save it without knowing which renderer produced it.
///
/// A `RenderedAsset` is deliberately renderer-agnostic — code, URL, HTML, and social-card
/// renderers resolve to the same value type — so the
/// clipboard, save, and share flows stay decoupled from the input kind. The image
/// is already normalized and tagged into `profile`'s color space, so encoding it
/// to PNG is a pure ImageIO call.
// `nonisolated` + `Sendable`: a pure value type over a `Sendable` `CGImage`, built
// and passed between the concurrent per-viewport capture tasks and the main actor.
nonisolated struct RenderedAsset: Sendable {
    /// The rendered image, in `profile`'s color space.
    var cgImage: CGImage

    /// The color profile the image is tagged with (sRGB by default).
    var profile: ColorProfile

    /// Pixel width of `cgImage` (scale already applied).
    var pixelWidth: Int { cgImage.width }

    /// Pixel height of `cgImage` (scale already applied).
    var pixelHeight: Int { cgImage.height }

    /// Pixel dimensions as a size, convenient for callers that report or compare
    /// output resolution.
    var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
}

/// Why a render did not produce an asset, as a typed error rather than a `nil`
/// image or a blank picture. Distinguishing *failed* (a renderer that
/// tried and could not encode) from *disabled* (URL capture without the network
/// entitlement) lets the capture layer offer the right recovery and lets tests
/// assert on the specific reason.
enum RenderError: Error, Equatable, Sendable {
    /// No registered renderer accepts this input. Carries the input kind for
    /// diagnostics; the associated value is a stable, non-PII label, never the
    /// user's content.
    case noRendererFor(kind: String)

    /// A renderer accepted the input but could not produce an image (e.g. the
    /// underlying `ImageRenderer` returned no `CGImage`). This is a genuine failure.
    case renderFailed

    /// A URL capture was requested in a build that does not carry the network
    /// client entitlement. The App Store build ships without
    /// `com.apple.security.network.client`, so the `URLRenderer` refuses early with
    /// this typed reason — distinct from a render that tried and failed.
    case urlCaptureDisabled

    /// A loopback URL was refused because the explicit localhost option is off.
    /// Kept distinct so the UI can name the safe recovery instead of blaming the URL.
    case loopbackCaptureDisabled
}

/// One strategy for turning a `CaptureInput` into a `RenderedAsset`.
///
/// The protocol intentionally has **no `associatedtype`**: an associatedtype
/// protocol cannot be stored as `any Renderer` or selected by input case, which is
/// exactly what routing needs. Dispatch happens on the `CaptureInput` enum and
/// each concrete renderer declares, via `canRender`, the cases it handles. This is
/// what lets the code path and the web-rendering paths evolve as independent types
/// behind one coordinator.
protocol Renderer {
    /// Whether this renderer handles `input`. A coordinator calls this to route;
    /// it must be cheap and side-effect-free.
    func canRender(_ input: CaptureInput) -> Bool

    /// Renders `input` with `config` to a `RenderedAsset`, or throws a
    /// `RenderError`. Implementations should not be called for an input they
    /// reject; doing so throws `RenderError.noRendererFor`.
    func render(_ input: CaptureInput, config: SnapshotConfig) async throws -> RenderedAsset
}

/// Picks the first registered renderer that accepts an input and delegates to it.
/// The order of `renderers` is the routing priority, so a more specific
/// renderer can precede a fallback. The coordinator owns no rendering logic itself
/// it is purely the seam between input classification and rendering.
struct RenderCoordinator {
    /// Renderers in priority order, e.g. `[CodeRenderer(), URLRenderer(), …]`.
    let renderers: [any Renderer]

    // `RenderCoordinator.standard` — the production coordinator wired with the code
    // and web renderers — lives in `WebRendering/RenderCoordinator+Standard.swift`,
    // which the CLI target excludes (the headless tool ships no WebKit). This struct
    // stays platform-neutral so both the app and the CLI compile it.

    /// Returns the first renderer that accepts `input`, or `nil` when none do.
    func renderer(for input: CaptureInput) -> (any Renderer)? {
        renderers.first { $0.canRender(input) }
    }

    /// Routes `input` to the first accepting renderer and returns its asset.
    /// Throws `RenderError.noRendererFor` when nothing accepts the input, and
    /// otherwise propagates the chosen renderer's error.
    func render(_ input: CaptureInput, config: SnapshotConfig) async throws -> RenderedAsset {
        guard let renderer = renderer(for: input) else {
            throw RenderError.noRendererFor(kind: input.diagnosticKind)
        }
        return try await renderer.render(input, config: config)
    }
}

extension CaptureInput {
    /// A stable, non-PII label for the input *kind*, for diagnostics and routing
    /// errors. Never includes the user's content (the code, URL, or HTML body).
    var diagnosticKind: String {
        switch self {
        case .code: "code"
        case .url: "url"
        case .html: "html"
        }
    }
}
