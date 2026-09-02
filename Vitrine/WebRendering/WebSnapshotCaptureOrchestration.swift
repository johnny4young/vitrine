import Foundation

@MainActor
extension WebSnapshotModel {
    /// The maximum number of viewport captures to run at once. Small so a large
    /// selection never spawns many heavy `WKWebView`s (and their web-content processes)
    /// at once; the loads still overlap, cutting a multi-size batch well below N× a single
    /// capture.
    private static let maxConcurrentCaptures = 3

    /// The `Sendable` result of one viewport's concurrent capture task: the finished
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
    /// Multi-resolution capture overlaps the per-viewport loads with a small
    /// concurrency cap (`maxConcurrentCaptures`): each viewport builds its **own**
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

        // Overlap the per-viewport loads with a small concurrency cap: keep at most
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
        var boardErrorMessage: String?
        // A multi-size batch also gets a composite "responsive board" as the primary
        // preview/export; a single capture has none.
        if captured.count > 1 {
            do {
                let board = try ResponsiveBoardComposer.composeChecked(
                    captured, scale: CGFloat(settings.export.scale),
                    profile: settings.export.colorProfile)
                boardAsset = board
                boardThumbnailAsset = CapturedViewport.makeThumbnail(from: board)
                renderedAsset = board
            } catch .tooLarge(let rejection) {
                boardAsset = nil
                boardThumbnailAsset = nil
                boardErrorMessage = Self.message(for: .renderTooLarge(rejection))
            } catch {
                boardAsset = nil
                boardThumbnailAsset = nil
                boardErrorMessage = Self.message(for: .renderFailed)
            }
        } else {
            boardAsset = nil
            boardThumbnailAsset = nil
        }
        // Note a partial failure when some viewports succeeded and others didn't.
        if captured.count < presets.count {
            errorMessage =
                boardErrorMessage
                ?? String(
                    localized:
                        "Captured \(captured.count) of \(presets.count) sizes; some didn't load."
                )
        } else {
            errorMessage = boardErrorMessage
        }
    }

    /// Renders `input` at a single `preset` viewport with the user's capture settings.
    /// Builds a fresh renderer per call (no shared web-view state), so the concurrent
    /// batch runs the exact single-capture path once per size.
    ///
    /// The renderer branch is chosen from the captured, immutable `input` — not the live
    /// `mode` — so a parallel batch routes every viewport consistently even if the user
    /// flips the mode picker mid-render: `input` was resolved once from `mode`
    /// at the top of `render`, so it is the authoritative source for all viewports.
    private func renderOne(
        input: CaptureInput,
        preset: WebSnapshotConfig.ViewportPreset,
        settings: AppSettings
    ) async throws -> RenderedAsset {
        try await viewportRenderer.render(input, preset, settings)
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
        case .loopbackCaptureDisabled:
            String(
                localized:
                    "That address is on this Mac. Turn on “Allow localhost capture” in Settings ▸ Input to capture it."
            )
        case .renderFailed:
            String(localized: "Couldn't load or render that — check the input and try again.")
        case .renderTooLarge:
            String(
                localized:
                    "The image is too large to render safely. Reduce the canvas size or scale.")
        case .noRendererFor:
            String(localized: "That input can't be rendered here.")
        }
    }
}
