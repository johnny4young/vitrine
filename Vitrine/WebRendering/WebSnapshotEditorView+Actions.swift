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
        // Ignore a re-entrant trigger (e.g. Return in the URL field) while a capture is
        // already running, so the held `renderTask` always points at the live render and
        // stays cancellable. `model.render` guards too, but this keeps the handle correct.
        guard !model.isRendering else { return }
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
        await model.render(settings: settings)
        if let error = model.errorMessage {
            CaptureHUDController.shared.present(Notifier.failure(error))
        }
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
        guard let png = ExportManager.pngData(from: asset.cgImage) else {
            CaptureHUDController.shared.present(
                Notifier.failure(String(localized: "Couldn't copy the image")))
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setData(png, forType: .png)
        CaptureHUDController.shared.present(
            copied
                ? Notifier.confirmation(String(localized: "Image copied to clipboard"))
                : Notifier.failure(String(localized: "Couldn't copy the image")))
    }

    func saveImage() {
        guard let asset = model.renderedAsset else { return }
        // Honor the user's chosen export format (PNG/PDF) through the same ladder the
        // rest of the app uses, rather than always writing PNG.
        guard
            let payload = ExportManager.encodedPayload(
                settings.exportFormat,
                png: { asset.cgImage },
                pdf: { ExportManager.pdfData(from: asset.cgImage) })
        else {
            CaptureHUDController.shared.present(
                Notifier.failure(String(localized: "Couldn't save the image")))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [payload.type]
        panel.nameFieldStringValue = "vitrine-web.\(payload.ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try payload.data.write(to: url)
            CaptureHUDController.shared.present(
                Notifier.confirmation(String(localized: "Image saved")))
        } catch {
            CaptureHUDController.shared.present(
                Notifier.failure(String(localized: "Couldn't save the image")))
        }
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
