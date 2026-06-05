import Foundation

/// What Vitrine was asked to turn into an image, classified by *kind* of input
/// rather than by how it will be drawn (CS-040).
///
/// Separating classification from rendering keeps the Phase 1 code path free of
/// the network and web-view assumptions that Phase 2's URL, HTML, and social-card
/// inputs introduce: the capture layer decides *what* the input is, and a
/// `RenderCoordinator` later picks the renderer that handles that case. Adding a
/// Phase 2 input is therefore a new `case` plus a new `Renderer`, with no change
/// to the code path.
///
/// The social-card input is intentionally a documented future extension point
/// rather than a live case: its model (`SocialCardModel`) ships with the
/// local social-card renderer.
// TODO: CS-041 — add `case socialCard(SocialCardModel)` once the model exists.
enum CaptureInput: Equatable {
    /// Source code to syntax-highlight and frame — the Phase 1 path. The optional
    /// language hint comes from the detector (a Markdown fence's info string, a
    /// file extension, or content scoring); `nil` lets the renderer fall back to
    /// its own detection.
    case code(String, languageHint: Language?)

    /// A web page to capture locally through WebKit (Product Phase 2). Only
    /// `http`/`https` URLs reach this case; validation lives in the URL renderer.
    case url(URL)

    /// A self-contained HTML fragment or document to render locally (Product
    /// Phase 2). Carried as a string so no network or file access is implied by
    /// the input itself.
    case html(String)
}

extension CaptureInput {
    /// Whether this input is part of Product Phase 2 (URL, HTML, social cards) and
    /// therefore not yet renderable. The code path is Phase 1 and renders today;
    /// everything else is an explicit deferred stub until its renderer ships.
    ///
    /// This is a property of the *input kind*, independent of which renderers are
    /// registered, so the capture layer can name a deferred outcome without first
    /// running the coordinator.
    var isDeferredToPhase2: Bool {
        switch self {
        case .code: false
        case .url, .html: true
        }
    }
}
