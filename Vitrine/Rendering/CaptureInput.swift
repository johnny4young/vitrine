import Foundation

/// What Vitrine was asked to turn into an image, classified by *kind* of input
/// rather than by how it will be drawn.
///
/// Separating classification from rendering keeps the code-rendering path free of
/// the network and web-view assumptions that web capture's URL, HTML, and social-card
/// inputs introduce: the capture layer decides *what* the input is, and a
/// `RenderCoordinator` later picks the renderer that handles that case. Adding a
/// web capture input is therefore a new `case` plus a new `Renderer`, with no change
/// to the code path.
///
/// Social cards ship through their own dedicated renderer (`SocialCardRenderer`
/// over `SocialCardModel`) rather than this classify-then-coordinate path. That
/// boundary keeps the capture input focused on code and WebKit-backed inputs.
enum CaptureInput: Equatable {
    /// Source code to syntax-highlight and frame — the local rendering path. The optional
    /// language hint comes from the detector (a Markdown fence's info string, a
    /// file extension, or content scoring); `nil` lets the renderer fall back to
    /// its own detection.
    case code(String, languageHint: Language?)

    /// A web page to capture locally through WebKit (web capture). Only
    /// `http`/`https` URLs reach this case; validation lives in the URL renderer.
    case url(URL)

    /// A self-contained HTML fragment or document to render locally.
    /// web capture). Carried as a string so no network or file access is implied by
    /// the input itself.
    case html(String)
}
