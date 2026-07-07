import AppKit
import OSLog
import SwiftUI

/// Which kind of web input the Web Snapshot surface is composing.
enum WebInputMode: String, CaseIterable, Identifiable {
    /// A user-provided `http`/`https` URL, captured locally in WebKit (CS-043).
    case url
    /// A pasted HTML fragment or document, rendered locally with remote subresources
    /// blocked (CS-042).
    case html

    var id: String { rawValue }
}

/// One viewport's capture in a multi-resolution batch (CS-044): the size it was
/// rendered at and the resulting asset, for the result gallery and the responsive board.
struct CapturedViewport: Identifiable {
    let kind: WebSnapshotConfig.ViewportPreset.Kind
    let preset: WebSnapshotConfig.ViewportPreset
    let asset: RenderedAsset
    let thumbnailAsset: RenderedAsset
    /// Unique within a batch — the selected viewport set is de-duplicated by kind.
    var id: WebSnapshotConfig.ViewportPreset.Kind { kind }
    /// A short label for the result tile, e.g. "Desktop (1440 × 900)".
    var label: String { preset.displayName }

    /// The filmstrip renders thumbnails at 92×58 pt. Keeping a 2× bitmap avoids
    /// handing SwiftUI full-page captures to downscale on every layout pass.
    static let thumbnailMaxPixelWidth = 184
    static let thumbnailMaxPixelHeight = 116

    init(
        kind: WebSnapshotConfig.ViewportPreset.Kind,
        preset: WebSnapshotConfig.ViewportPreset,
        asset: RenderedAsset,
        thumbnailAsset: RenderedAsset? = nil
    ) {
        self.kind = kind
        self.preset = preset
        self.asset = asset
        self.thumbnailAsset = thumbnailAsset ?? Self.makeThumbnail(from: asset)
    }

    static func makeThumbnail(from asset: RenderedAsset) -> RenderedAsset {
        let source = asset.cgImage
        guard source.width > 0, source.height > 0 else { return asset }

        let scale = min(
            CGFloat(thumbnailMaxPixelWidth) / CGFloat(source.width),
            CGFloat(thumbnailMaxPixelHeight) / CGFloat(source.height),
            1)
        let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
        guard width < source.width || height < source.height else { return asset }

        let colorSpace = source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard
            let colorSpace,
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return asset
        }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let thumbnail = context.makeImage() else { return asset }
        return RenderedAsset(cgImage: thumbnail, profile: asset.profile)
    }
}

/// The observable document behind the Web Snapshot window: the chosen input mode, the
/// URL/HTML the user is composing, the rendered result, and the in-flight/error state
/// (CS-042/CS-043).
///
/// The render itself runs here so the view stays declarative: ``render(settings:)``
/// builds the right renderer (`HTMLRenderer` for HTML, `URLRenderer.configured` for
/// URL), invokes it, and publishes either the `RenderedAsset` or a typed, non-PII
/// error message. URL capture stays gated on the network entitlement inside
/// `URLRenderer`, so a build without it surfaces a clear "only in the direct-download
/// build" message rather than a blank result.
@MainActor
@Observable
final class WebSnapshotModel {
    var mode: WebInputMode = .url
    var urlText: String = ""
    var htmlText: String = ""

    /// The most recent successful render, shown in the preview and exported. In a
    /// multi-resolution batch this is the primary (first selected) captured viewport.
    var renderedAsset: RenderedAsset?

    /// Every viewport captured in the last multi-resolution batch (CS-044), in selection
    /// order. Drives the result gallery and the responsive board; empty for a failed or
    /// not-yet-run capture.
    var results: [CapturedViewport] = []

    /// The composite "responsive board" for a multi-size batch (CS-044): every capture
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

    /// Progress through a multi-viewport batch (CS-044 cancel/progress): the 1-based
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

    /// Releases the large rendered images — a multi-viewport batch can hold several
    /// full-resolution `CGImage`s (~100 MB) — when the window closes. The input text, mode,
    /// and settings stay, so reopening resumes ready to re-capture (audit P1-Perf-6).
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
    /// form (UX audit). Cleared once the view acts on it.
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
    /// the user is not left on a static prefilled form (UX audit).
    func prepareForPrefillURL(_ prefillURL: String) {
        mode = .url
        urlText = prefillURL
        discardRenderedAssets()
        pendingAutoCapture = Self.shouldAutoCapture(
            mode: .url, urlCaptureEnabled: NetworkCapability.isURLCaptureEnabled)
    }

    /// The maximum number of viewport captures to run at once (P6). Small so a large
    /// selection never spawns many heavy `WKWebView`s (and their web-content processes)
    /// at once; the loads still overlap, cutting a multi-size batch well below N× a single
    /// capture.
    private static let maxConcurrentCaptures = 3

    /// The `Sendable` result of one viewport's concurrent capture task (P6): the finished
    /// `RenderedAsset` (or a typed failure) crosses back from the child task, and the
    /// main-actor drain loop wraps it in a `CapturedViewport` (whose `preset` accessors are
    /// main-actor bound) once it knows the completion order.
    private enum ViewportOutcome: Sendable {
        case captured(RenderedAsset)
        case renderFailed(RenderError)
        case cancelled
        case unknownFailure
    }

    /// Renders the current input at every selected viewport, publishing the captured
    /// set or a typed error. Safe to call repeatedly; each call replaces the results.
    ///
    /// Multi-resolution capture (CS-044) overlaps the per-viewport loads with a small
    /// concurrency cap (`maxConcurrentCaptures`, P6): each viewport builds its **own**
    /// `WKWebView` — a separate web-content process — so their loads run in parallel even
    /// though `WKWebView` is main-actor bound (the `await` on each load releases the main
    /// actor for the others). A re-entrant `render()` is still refused (`isRendering`), a
    /// single viewport that fails is recorded and skipped, and the results are reassembled
    /// in the user's selected order for the board/preview. The input (URL/HTML) is
    /// validated once up front since it is the same across viewports.
    func render(settings: AppSettings) async {
        // Ignore a re-entrant render while one is already in flight (a fast second
        // Capture tap, or a disclosure-confirm landing while a prefilled render runs),
        // so two WKWebView load-and-snapshot cycles never overlap. Safe because this
        // type is @MainActor, so the check-and-set cannot interleave.
        guard !isRendering else { return }
        errorMessage = nil
        isRendering = true
        defer {
            isRendering = false
            renderProgress = nil
        }

        // Resolve the input once; it is identical across viewports.
        let input: CaptureInput
        switch mode {
        case .url:
            guard let url = Self.normalizedURL(urlText) else {
                errorMessage = String(localized: "Enter a valid http or https URL.")
                results = []
                renderedAsset = nil
                boardAsset = nil
                return
            }
            input = .url(url)
        case .html:
            input = .html(htmlText)
        }

        let presets = settings.webCapture.selectedViewportPresets
        let reportsBatchProgress = presets.count > 1
        var capturedByIndex: [Int: CapturedViewport] = [:]
        var lastError: RenderError?
        var hadUnknownError = false

        // Overlap the per-viewport loads with a small concurrency cap (P6): keep at most
        // `maxConcurrentCaptures` in flight, scheduling the next as each finishes. Each
        // renderer owns its WKWebView/web-content process, so the loads run in parallel;
        // the awaits release the main actor between them. Cancellation (the Cancel button)
        // cancels the in-flight children — whose waits are cancellation-aware — and stops
        // scheduling; a single viewport that fails is recorded and skipped.
        let maxConcurrent = min(presets.count, Self.maxConcurrentCaptures)
        await withTaskGroup(of: (Int, ViewportOutcome).self) { group in
            var nextIndex = 0
            func scheduleNext() {
                guard nextIndex < presets.count, !Task.isCancelled else { return }
                let index = nextIndex
                let preset = presets[index]
                nextIndex += 1
                group.addTask {
                    do {
                        let asset = try await self.renderOne(
                            input: input, preset: preset, settings: settings)
                        return (index, .captured(asset))
                    } catch is CancellationError {
                        return (index, .cancelled)
                    } catch let error as RenderError {
                        return (index, .renderFailed(error))
                    } catch {
                        return (index, .unknownFailure)
                    }
                }
            }
            for _ in 0..<maxConcurrent { scheduleNext() }

            var completed = 0
            while let (index, outcome) = await group.next() {
                completed += 1
                if reportsBatchProgress {
                    renderProgress = RenderProgress(current: completed, total: presets.count)
                }
                switch outcome {
                case .captured(let asset):
                    // Build the CapturedViewport here on the main actor, where the preset's
                    // (main-actor) accessors are available.
                    let preset = presets[index]
                    capturedByIndex[index] = CapturedViewport(
                        kind: preset.kind, preset: preset, asset: asset)
                case .renderFailed(let error): lastError = error
                case .unknownFailure: hadUnknownError = true
                case .cancelled: break
                }
                if Task.isCancelled {
                    group.cancelAll()
                } else {
                    scheduleNext()
                }
            }
        }

        // Reassemble in the user's selected order — the concurrent group completes out of
        // order, but the board composer and the primary preview depend on the order.
        let captured = capturedByIndex.keys.sorted().compactMap { capturedByIndex[$0] }

        // A cancel is not a failure: stop cleanly, leaving any prior result in place and
        // showing no error (`isRendering`/`renderProgress` reset in the `defer`).
        if Task.isCancelled { return }

        guard !captured.isEmpty else {
            results = []
            renderedAsset = nil
            boardAsset = nil
            boardThumbnailAsset = nil
            errorMessage =
                lastError.map(Self.message(for:))
                ?? (hadUnknownError ? String(localized: "The render didn't complete.") : nil)
            return
        }

        results = captured
        renderedAsset = captured.first?.asset
        // A multi-size batch also gets a composite "responsive board" as the primary
        // preview/export; a single capture has none.
        if captured.count > 1 {
            boardAsset = ResponsiveBoardComposer.compose(
                captured, scale: CGFloat(settings.exportScale), profile: settings.colorProfile)
            if let board = boardAsset {
                boardThumbnailAsset = CapturedViewport.makeThumbnail(from: board)
                renderedAsset = board
            } else {
                boardThumbnailAsset = nil
            }
        } else {
            boardAsset = nil
            boardThumbnailAsset = nil
        }
        // Note a partial failure when some viewports succeeded and others didn't.
        if captured.count < presets.count {
            errorMessage = String(
                localized: "Captured \(captured.count) of \(presets.count) sizes; some didn't load."
            )
        }
    }

    /// Renders `input` at a single `preset` viewport with the user's capture settings.
    /// Builds a fresh renderer per call (no shared web-view state), so the concurrent
    /// batch runs the exact single-capture path once per size.
    ///
    /// The renderer branch is chosen from the captured, immutable `input` — not the live
    /// `mode` — so a parallel batch routes every viewport consistently even if the user
    /// flips the mode picker mid-render (P6 review): `input` was resolved once from `mode`
    /// at the top of `render`, so it is the authoritative source for all viewports.
    private func renderOne(
        input: CaptureInput,
        preset: WebSnapshotConfig.ViewportPreset,
        settings: AppSettings
    ) async throws -> RenderedAsset {
        switch input {
        case .html:
            let renderer = HTMLRenderer(
                viewport: preset.size,
                scale: CGFloat(settings.exportScale),
                profile: settings.colorProfile)
            return try await renderer.render(input, config: settings.config)
        case .url:
            let renderer = URLRenderer(
                scale: CGFloat(settings.exportScale),
                viewportPreset: preset,
                captureMode: settings.webCapture.captureMode,
                waitStrategy: settings.webCapture.waitStrategy,
                profile: settings.colorProfile,
                dataStoreMode: settings.webCapture.dataStoreMode)
            return try await renderer.render(input, config: settings.config)
        case .code:
            // The web snapshot flow only ever resolves `.url`/`.html`; a `.code` input
            // has no web renderer, so surface it as a typed failure rather than silently.
            throw RenderError.noRendererFor(kind: "code")
        }
    }

    /// Trims and accepts only a single `http`/`https` URL, mirroring the renderer's own
    /// scheme gate so the UI rejects an obviously bad URL before a render attempt.
    static func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    /// A user-facing, localized message for a render error — never the URL or HTML.
    static func message(for error: RenderError) -> String {
        switch error {
        case .urlCaptureDisabled:
            String(localized: "URL capture is only available in the direct-download build.")
        case .renderFailed:
            String(localized: "Couldn't load or render that — check the input and try again.")
        case .noRendererFor:
            String(localized: "That input can't be rendered here.")
        }
    }
}

/// Owns the app's single Web Snapshot window (CS-042/CS-043): local HTML rendering and
/// (on a build that carries the network entitlement) URL capture, with a live preview
/// and the same clipboard/save/share export as the rest of the app.
///
/// Like `SocialCardWindowController`, the window is reused across opens and closes. It
/// is registered with `WebSnapshotPresenter` at launch (`registerPresenter()`), so the
/// File-menu command, the `--open-web-snapshot` hook, and the quick-capture URL route —
/// all of which live in `App/` and must not link WebKit — present it through that seam
/// rather than naming this WebKit-backed controller directly.
@MainActor
final class WebSnapshotWindowController: NSObject, NSWindowDelegate {
    static let shared = WebSnapshotWindowController()

    /// The window's working document, shared with the hosted SwiftUI view.
    let model = WebSnapshotModel()

    private var window: NSWindow?

    private static let defaultContentSize = NSSize(width: 1100, height: 760)
    private static let frameAutosaveName = "vitrine.web-snapshot.window"

    /// Not an `editor-window` prefix, so a key Web Snapshot window never enables the
    /// editor-scoped export commands.
    static let windowIdentifier = "web-snapshot-window"

    private override init() { super.init() }

    /// Installs the window opener on `WebSnapshotPresenter`. Called once at launch from
    /// the app-only `VitrineApp`, so the CLI (which excludes this file) never links the
    /// WebKit-backed window.
    static func registerPresenter() {
        WebSnapshotPresenter.open = { prefillURL in
            WebSnapshotWindowController.shared.show(prefillURL: prefillURL)
        }
    }

    /// Shows the Web Snapshot window, creating it the first time, and focuses it.
    /// `prefillURL` (from the quick-capture URL route) loads the URL field in URL mode
    /// and clears any previous result so the user lands ready to capture.
    func show(prefillURL: String? = nil) {
        if let prefillURL {
            model.prepareForPrefillURL(prefillURL)
        }
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: WebSnapshotEditorView(model: model).environment(AppSettings.shared))
        let window = TitleBarAlignedWindow(contentViewController: hosting)
        window.title = String(localized: "Web Snapshot")
        window.styleMask = [
            .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
        ]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(Self.defaultContentSize)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.setAccessibilityIdentifier(Self.windowIdentifier)

        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
                window.setFrame(
                    WindowFrameSolver.clamp(window.frame, into: visible), display: false)
            }
            window.center()
        }
        return window
    }

    /// Frees the large rendered images when the window closes. The window is reused
    /// (`isReleasedWhenClosed = false`), so without this a multi-viewport batch's
    /// full-resolution captures would stay resident for the app's lifetime (audit P1-Perf-6).
    func windowWillClose(_ notification: Notification) {
        model.discardRenderedAssets()
    }
}
