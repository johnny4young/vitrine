import AppKit
import UniformTypeIdentifiers

/// The Web Snapshot composer's actions: starting a capture and exporting the result
/// (copy / save / share / export-all).
extension WebSnapshotEditorView {
    // MARK: - Capture

    /// Starts a capture. For a URL, the first attempt (or any attempt on a build that
    /// cannot reach the network) routes through the privacy disclosure before any load;
    /// HTML renders immediately since it never reaches the network.
    func attemptCapture() {
        // Ignore a re-entrant trigger (a fast second click, or Return in the URL field)
        // while a capture is already in flight. Guard on `renderTask`, not
        // `model.isRendering`: `renderTask` is assigned synchronously below, whereas
        // `isRendering` only flips once the spawned task starts running — so two quick
        // triggers could both clear an `isRendering` guard and the second would overwrite
        // the handle, leaving Cancel pointed at a no-op task while the real render runs.
        guard renderTask == nil else { return }
        // Show the privacy disclosure only when URL capture is actually available and the
        // user hasn't consented yet. On a build that can't reach the network the disclosure's
        // confirm button is permanently disabled, so routing through it strands the user in a
        // dismiss-and-retry dead end; instead fall through to the capture, which fails fast
        // with `RenderError.urlCaptureDisabled` and its clear message (audit P0-4).
        if model.mode == .url,
            !settings.webCapture.consentGiven, NetworkCapability.isURLCaptureEnabled
        {
            showDisclosure = true
            return
        }
        renderTask = Task { await capture() }
    }

    func capture() async {
        defer {
            renderTask = nil
            // Pick up a prefill that arrived while this capture was in flight (it was
            // left pending rather than dropped — see `autoCaptureIfPending`).
            autoCaptureIfPending()
        }
        await model.render(settings: settings)
        if let error = model.errorMessage {
            CaptureHUDController.shared.present(Notifier.failure(error))
        }
    }

    /// Fires the capture for a freshly prefilled URL (quick-capture route) so the user
    /// isn't left on a static form. `attemptCapture` re-checks availability and consent,
    /// so this routes through the privacy disclosure on first use just like a manual tap.
    func autoCaptureIfPending() {
        // Don't consume the flag while a capture is running: `attemptCapture` would early
        // return on its `renderTask != nil` guard and drop the signal. Leave it set — the
        // running capture's `defer` calls back here once it finishes.
        guard model.pendingAutoCapture, renderTask == nil else { return }
        model.pendingAutoCapture = false
        attemptCapture()
    }

    /// Stops an in-flight capture (the Cancel button / Escape). Cancellation propagates
    /// into `model.render`, which stops between viewports and whose in-flight renderer
    /// aborts its load and waits, so the user is never stuck waiting out a long batch.
    func cancelCapture() {
        renderTask?.cancel()
    }

    // MARK: - Export

    func copyImage() {
        guard let asset = model.renderedAsset else { return }
        ExportFeedback.presentCopy(ExportManager.copyPNGToPasteboard(asset.cgImage))
    }

    func saveImage() {
        guard let asset = model.renderedAsset else { return }
        // Honor the user's chosen export format through the same ladder the rest of
        // the app uses, then funnel the panel/write through the shared save path so
        // this flow gets the CS-048 logging discipline like every other save.
        guard
            let payload = ExportManager.encodedPayload(
                settings.export.format,
                png: { asset.cgImage },
                pdf: { ExportManager.pdfData(from: asset.cgImage) })
        else {
            ExportFeedback.presentSave(.failed)
            return
        }
        ExportFeedback.presentSave(
            ExportManager.saveToFile(payload: payload, suggestedName: "vitrine-web"))
    }

    /// Exports every captured viewport plus the composite board as PNGs into a folder
    /// the user picks (CS-044 multi-resolution) — a ready-to-share set in one action.
    func exportAll() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Export")
        guard panel.runModal() == .OK, let directory = panel.url else { return }

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

        var written = 0
        for item in items {
            guard let data = ExportManager.pngData(from: item.image) else { continue }
            if (try? data.write(to: directory.appendingPathComponent("\(item.name).png"))) != nil {
                written += 1
            }
        }

        CaptureHUDController.shared.present(
            written > 0
                ? Notifier.confirmation(String(localized: "Images exported"))
                : Notifier.failure(String(localized: "Couldn't export the images")))
    }

    func shareImage() {
        guard let asset = model.renderedAsset, let view = NSApp.keyWindow?.contentView else {
            return
        }
        ShareManager.share(nsImage(from: asset), relativeTo: view)
    }
}
