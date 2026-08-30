import CoreGraphics
import Foundation

/// The Web Snapshot composer's actions: starting a capture and exporting the result
/// (copy / save / share / export-all).
extension WebSnapshotEditorView {
    // MARK: - Capture

    /// Starts a capture. For a URL, the first attempt (or any attempt on a build that
    /// cannot reach the network) routes through the privacy disclosure before any load;
    /// HTML renders immediately since it never reaches the network.
    func attemptCapture() {
        // Ignore a re-entrant trigger (a fast second click, or Return in the URL field)
        // while a capture is already in flight. Guard on `model.isCapturing`, not
        // `model.isRendering`: the handle is assigned synchronously below, whereas
        // `isRendering` only flips once the spawned task starts running — so two quick
        // triggers could both clear an `isRendering` guard and the second would overwrite
        // the handle, leaving Cancel pointed at a no-op task while the real render runs.
        guard !model.isCapturing else { return }
        // Show the privacy disclosure only when URL capture is actually available and the
        // user hasn't consented yet. On a build that can't reach the network the disclosure's
        // confirm button is permanently disabled, so routing through it strands the user in a
        // dismiss-and-retry dead end; instead fall through to the capture, which fails fast
        // with `RenderError.urlCaptureDisabled` and its clear message.
        if model.mode == .url,
            !settings.webCapture.consentGiven, NetworkCapability.isURLCaptureEnabled
        {
            showDisclosure = true
            return
        }
        model.beginRender(Task { await capture() })
    }

    /// Opens the interactive sign-in window on the URL being captured.
    ///
    /// The window shares the capture's persistent data store, so the session the user
    /// establishes there is the one the next capture sends. Silently does nothing for an
    /// address that does not validate — the button that calls this is only offered once
    /// `WebSessionAvailability` says the URL is usable, so reaching here with a bad one
    /// means the field changed under the click.
    func signInToCaptureSite() {
        guard
            let url = try? WebSnapshotConfig.validate(
                captureURLString: model.urlText,
                allowLoopback: settings.webCapture.allowsLoopbackCapture)
        else { return }
        presentation.showSignIn(for: url)
    }

    func capture() async {
        defer {
            model.finishRender()
            // Pick up a prefill that arrived while this capture was in flight (it was
            // left pending rather than dropped — see `autoCaptureIfPending`).
            autoCaptureIfPending()
        }
        await model.render(settings: settings)
        if let error = model.errorMessage {
            feedback(Notifier.failure(error))
        }
    }

    /// Fires the capture for a freshly prefilled URL (quick-capture route) so the user
    /// isn't left on a static form. `attemptCapture` re-checks availability and consent,
    /// so this routes through the privacy disclosure on first use just like a manual tap.
    func autoCaptureIfPending() {
        // Don't consume the flag while a capture is running: `attemptCapture` would early
        // return on its `isCapturing` guard and drop the signal. Leave it set — the
        // running capture's `defer` calls back here once it finishes.
        guard model.pendingAutoCapture, !model.isCapturing else { return }
        model.pendingAutoCapture = false
        attemptCapture()
    }

    /// Stops an in-flight capture (the Cancel button / Escape). Cancellation propagates
    /// into `model.render`, which stops between viewports and whose in-flight renderer
    /// aborts its load and waits, so the user is never stuck waiting out a long batch.
    func cancelCapture() {
        model.cancelRender()
    }

    // MARK: - Export

    func copyImage() {
        guard let asset = model.renderedAsset else { return }
        feedback(
            ExportFeedback.copyOutcome(
                ExportManager.copyPNGToPasteboardOutcome(asset.cgImage)))
    }

    func saveImage() {
        guard let asset = model.renderedAsset else { return }
        // Honor the user's chosen export format through the same ladder the rest of
        // the app uses, then funnel the panel/write through the shared save path so
        // this flow follows the same logging policy as every other save.
        guard
            let payload = ExportManager.encodedPayload(
                settings.export.format,
                png: { asset.cgImage },
                pdf: { ExportManager.pdfData(from: asset.cgImage) })
        else {
            if let feedbackOutcome = ExportFeedback.saveOutcome(.failed) {
                feedback(feedbackOutcome)
            }
            return
        }
        if let feedbackOutcome = ExportFeedback.saveOutcome(
            ExportManager.saveToFile(payload: payload, suggestedName: "vitrine-web"))
        {
            feedback(feedbackOutcome)
        }
    }

    /// Exports every captured viewport plus the composite board as PNGs into a folder
    /// the user picks (multi-resolution) — a ready-to-share set in one action.
    func exportAll() {
        var items: [(name: String, image: CGImage)] = model.results.map { result in
            let size = result.preset.size
            return (
                "vitrine-web-\(result.kind.rawValue)-\(Int(size.width))x\(Int(size.height))",
                result.asset.cgImage
            )
        }
        if let board = model.boardAsset?.cgImage {
            items.append(("vitrine-web-responsive-board", board))
        }
        guard !items.isEmpty else { return }
        guard
            let directory = presentation.batchExport.chooseDirectory(
                message: String(localized: "Choose a folder for the exported images."))
        else { return }

        var written = 0
        for item in items {
            guard let data = ExportManager.pngData(from: item.image) else { continue }
            if (try? data.write(to: directory.appendingPathComponent("\(item.name).png"))) != nil {
                written += 1
            }
        }

        let completion = BatchExportCompletion(
            written: written,
            failed: items.count - written,
            expected: items.count)
        if completion.isComplete {
            feedback(Notifier.confirmation(String(localized: "Images exported")))
            presentation.batchExport.reveal(directory)
        } else {
            feedback(
                Notifier.failure(
                    completion.failureNote
                        ?? String(localized: "Couldn't export the images")))
        }
    }

    func shareImage() {
        guard let asset = model.renderedAsset else { return }
        presentation.share(nsImage(from: asset))
    }
}
