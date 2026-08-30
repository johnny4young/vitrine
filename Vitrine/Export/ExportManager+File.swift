import AppKit
import OSLog
import UniformTypeIdentifiers

extension ExportManager {
    /// Presents an `NSSavePanel` and writes the image as PNG, PDF, HEIC, or AVIF.
    ///
    /// `profile` applies to raster export only; PDF is a color-managed
    /// vector document and is unaffected by the raster color-profile choice.
    ///
    /// Returns the outcome so a caller can give the user precise feedback:
    /// `.saved` when a file was written, `.cancelled` when the user
    /// dismissed the panel, and `.failed` when rendering, encoding, or the write
    /// itself failed. The result is discardable for callers that do not care.
    @discardableResult
    static func saveToFile(
        _ config: SnapshotConfig, scale: CGFloat = 2, format: ExportFormat = .png,
        fixedSize: CGSize? = nil, profile: ColorProfile = .sRGB
    ) -> SaveOutcome {
        let payload: (data: Data, type: UTType, ext: String)
        do {
            payload = try encodedPayloadChecked(
                format,
                raster: { () throws(RenderBudgetError) -> CGImage in
                    try renderCGImageChecked(
                        config, scale: scale, fixedSize: fixedSize, profile: profile)
                },
                pdf: { pdfData(config, fixedSize: fixedSize) })
        } catch let error {
            Log.export.error("Save to file failed: render or encode returned nil")
            return .renderFailed(error)
        }
        return saveToFile(
            payload: payload, suggestedName: SuggestedFilename.basename(for: config))
    }

    /// Saves an **already-rendered** raster `cgImage` as PNG, HEIC, or AVIF: the
    /// quick-capture path renders the styled image once and reuses it for both the
    /// clipboard copy and this file save instead of re-rendering the identical config.
    /// PDF is a vector document and must render its own page, so this overload does not
    /// accept it; callers save PDF through the `config`-based `saveToFile` above.
    @discardableResult
    static func saveToFile(
        cgImage: CGImage, format: ExportFormat, suggestedName: String
    ) -> SaveOutcome {
        guard let data = rasterData(from: cgImage, format: format),
            let metadata = rasterMetadata(for: format)
        else {
            Log.export.error("Save to file failed: raster encode returned nil or PDF via cgImage")
            return .renderFailed(.encodingFailed)
        }
        return saveToFile(
            payload: (data, metadata.type, metadata.ext), suggestedName: suggestedName)
    }

    /// Presents the save panel for an already-encoded payload and writes it — the
    /// shared panel/write/log dance behind every save flow (the config path above,
    /// the social-card renderer, and the web editor), so the logging policy
    /// lives in exactly one place.
    @discardableResult
    static func saveToFile(
        payload: (data: Data, type: UTType, ext: String), suggestedName: String
    ) -> SaveOutcome {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [payload.type]
        panel.nameFieldStringValue = "\(suggestedName).\(payload.ext)"
        guard panel.runModal() == .OK, let url = panel.url else {
            Log.export.info("Save to file cancelled")
            return .cancelled
        }
        do {
            // The destination is a user-chosen path; we log only the format, never
            // the path itself (privacy policy).
            try payload.data.write(to: url)
            Log.export.notice("Saved image to file (\(payload.ext, privacy: .public))")
            return .saved
        } catch {
            // Log only the error domain/code — never `localizedDescription`, which
            // can embed the (user-chosen) filename (privacy policy).
            let nsError = error as NSError
            Log.export.error(
                "Saving image to file failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            return .failed
        }
    }

    /// The outcome of a save-to-file attempt, so callers can tell apart a written
    /// file, a user cancel, and a genuine failure for feedback.
    enum SaveOutcome: Equatable {
        case saved
        case cancelled
        case failed
        case renderFailed(RenderBudgetError)
    }
}
