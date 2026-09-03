import Foundation
import Observation

/// The observable document behind the Web Snapshot window: the chosen input mode, the
/// URL/HTML the user is composing, the rendered result, and the in-flight/error state.
///
/// The render itself runs here so the view stays declarative: ``render(settings:)``
/// resolves the input, delegates each viewport to the injected strategy, and publishes
/// either the `RenderedAsset` or a typed, non-PII error message. The live strategy
/// routes HTML to `HTMLRenderer` and URLs to `URLRenderer`; URL capture stays gated on
/// the network entitlement inside `URLRenderer`, so a build without it surfaces a clear
/// "only in the direct-download build" message rather than a blank result.
@MainActor
@Observable
final class WebSnapshotModel {
    let viewportRenderer: WebSnapshotViewportRenderer

    init(viewportRenderer: WebSnapshotViewportRenderer = .live) {
        self.viewportRenderer = viewportRenderer
    }

    var mode: WebInputMode = .url
    var urlText: String = ""
    var htmlText: String = ""

    /// The most recent successful render, shown in the preview and exported. In a
    /// multi-resolution batch this is the primary (first selected) captured viewport.
    var renderedAsset: RenderedAsset?

    /// Every viewport captured in the last multi-resolution batch, in selection
    /// order. Drives the result gallery and the responsive board; empty for a failed or
    /// not-yet-run capture.
    var results: [CapturedViewport] = []

    /// The composite "responsive board" for a multi-size batch: every capture
    /// laid out in one shareable image. `nil` for a single-viewport capture or a failed
    /// batch; when present it is the primary preview/export.
    var boardAsset: RenderedAsset?

    /// Downsampled copy of ``boardAsset`` for the filmstrip. The full board stays in
    /// ``boardAsset`` for export, while the UI keeps layout cheap.
    var boardThumbnailAsset: RenderedAsset?

    /// Whether a render is in flight (drives the preview's loading state).
    var isRendering = false
    /// A user-facing, non-PII error from the last render attempt, or `nil`.
    var errorMessage: String?

    /// Progress through a multi-viewport batch (cancel/progress): the 1-based
    /// index of the viewport being captured and the batch total, so the loading state can
    /// say "Capturing 2 of 4". `nil` when idle or for a single-viewport capture.
    struct RenderProgress: Equatable {
        var current: Int
        var total: Int
    }
    var renderProgress: RenderProgress?

    /// Whether the active input has enough content to attempt a render.
    var canRender: Bool {
        switch mode {
        case .url: !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .html: !htmlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The host of the URL being captured, shown verbatim in the loading state for
    /// transparency (which page is being loaded). `nil` outside URL mode or for an
    /// unparseable URL.
    var loadingHost: String? {
        guard mode == .url, let url = Self.normalizedURL(urlText) else { return nil }
        return url.host
    }

    /// The in-flight capture.
    ///
    /// Owned by the model rather than the view's `@State` so window teardown can reach
    /// it: `windowWillClose` lives on the AppKit controller and cannot see SwiftUI state,
    /// so a capture started from the view outlived its window and re-seated `results`,
    /// `renderedAsset`, and `boardAsset` into the model that `discardRenderedAssets()`
    /// had just cleared — keeping the full-resolution captures resident for the app's
    /// lifetime and presenting an abandoned batch on the next open.
    private(set) var renderTask: Task<Void, Never>?

    /// Whether a capture is in flight.
    ///
    /// This is the re-entrancy guard, not `isRendering`: the handle is assigned
    /// synchronously on the main actor by ``beginRender(_:)``, whereas `isRendering` only
    /// flips once the spawned task starts running, so two quick triggers could both clear
    /// an `isRendering` check.
    var isCapturing: Bool { renderTask != nil }

    /// Records the capture the view just spawned. Synchronous on the main actor, which is
    /// what makes ``isCapturing`` a reliable guard.
    func beginRender(_ task: Task<Void, Never>) {
        renderTask = task
    }

    /// Clears the handle once a capture finishes, so the next trigger is accepted.
    func finishRender() {
        renderTask = nil
    }

    /// Stops an in-flight capture. `render` checks `Task.isCancelled` before publishing,
    /// and both this and that check run on the main actor with no suspension point
    /// between them, so a cancel issued during teardown lands before any write.
    func cancelRender() {
        renderTask?.cancel()
    }

    /// Releases the large rendered images — a multi-viewport batch can hold several
    /// full-resolution `CGImage`s (~100 MB) — when the window closes. The input text, mode,
    /// and settings stay, so reopening resumes ready to re-capture.
    func discardRenderedAssets() {
        renderedAsset = nil
        results = []
        boardAsset = nil
        boardThumbnailAsset = nil
        errorMessage = nil
        // Also drop a not-yet-consumed auto-capture flag so closing the window can't leak
        // a stale prefilled URL into an auto-capture on the next open. `prepareForPrefillURL`
        // sets the flag *after* calling this, so its own prefill is unaffected.
        pendingAutoCapture = false
    }

    /// Set when a prefilled URL arrives in a build where URL capture is available, so the
    /// view fires the capture automatically instead of stranding the user on a prefilled
    /// form. Cleared once the view acts on it.
    var pendingAutoCapture = false

    /// Whether a prefilled URL should capture automatically: only in URL mode, and only
    /// where URL capture is actually available — otherwise the window just shows why it is
    /// disabled rather than auto-firing into an error. Pure for testability.
    static func shouldAutoCapture(mode: WebInputMode, urlCaptureEnabled: Bool) -> Bool {
        mode == .url && urlCaptureEnabled
    }

    /// Loads a URL supplied by quick capture or another presenter, clearing all prior
    /// rendered outputs so stale filmstrip/export-all results cannot survive into the new
    /// capture session, and — where URL capture is available — flags it to auto-capture so
    /// the user is not left on a static prefilled form.
    func prepareForPrefillURL(_ prefillURL: String) {
        mode = .url
        urlText = prefillURL
        discardRenderedAssets()
        pendingAutoCapture = Self.shouldAutoCapture(
            mode: .url, urlCaptureEnabled: NetworkCapability.isURLCaptureEnabled)
    }
}
