import AppKit
import OSLog

extension ExportManager {
    nonisolated struct BatchExportResult: Equatable, Sendable {
        let written: Int
        let failed: Int
        let firstRenderFailure: RenderBudgetError?
    }

    nonisolated private enum BatchItemOutcome: Sendable {
        case written
        case failed
        case renderFailed(RenderBudgetError)
    }

    /// Renders `baseConfig` once per preset and writes one file per preset into
    /// `directory` — the PRO multi-size one-pass export.
    ///
    /// This is the single-export ladder fanned out, not a new encoder: for each
    /// preset it applies that preset's presentation (`apply(to:)` writes padding +
    /// background, leaving `code`/`language`/any watermark intact) and renders at the
    /// preset's pinned `fixedSize` and `scale` through the same color-managed
    /// `encodedPayload` path. So each written file is byte-for-byte what a single
    /// export with THAT preset selected (at its pinned scale) produces. Files are
    /// named `vitrine-<preset id>.<ext>`. Returns how many were written and how many
    /// presets failed, so the caller can give precise feedback. Only the
    /// format/counts are logged, never the chosen folder path.
    @discardableResult
    static func exportPresetSizes(
        _ baseConfig: SnapshotConfig, presets: [ExportPreset], to directory: URL,
        format: ExportFormat = .png, profile: ColorProfile = .sRGB, textSidecar: Bool = false,
        onProgress: (@MainActor (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async -> BatchExportResult {
        var written = 0
        var failed = 0
        var firstRenderFailure: RenderBudgetError?
        let total = presets.count
        // Pipeline the batch: each preset renders on the main actor (`ImageRenderer`
        // requires it), then its CPU-bound encode + disk write run off-main as a child
        // task while the main actor immediately moves on to render the next preset. So
        // a batch of large presets at 2–3× scale neither beachballs the app nor waits
        // for one preset's encode before starting the next. Each writes a distinct
        // `vitrine-<preset id>` file, so the concurrent writes never collide.
        var completed = 0
        await withTaskGroup(of: BatchItemOutcome.self) { group in
            for preset in presets {
                var config = baseConfig
                preset.apply(to: &config)
                let size = preset.sizing.fixedSize
                // PDF is rendered *and* encoded on main because `pdfData` also drives
                // `ImageRenderer`; only raster formats defer their encode off-main.
                let raster: CGImage?
                let pdf: Data?
                switch format {
                case .png, .heic, .avif:
                    do throws(RenderBudgetError) {
                        raster = try renderCGImageChecked(
                            config, scale: CGFloat(preset.scale), fixedSize: size,
                            profile: profile)
                    } catch let error {
                        Log.export.error(
                            "Multi-size export rejected a preset before raster allocation")
                        raster = nil
                        group.addTask { .renderFailed(error) }
                        continue
                    }
                    pdf = nil
                case .pdf:
                    raster = nil
                    pdf = pdfData(config, fixedSize: size)
                }
                // The chosen folder is a user-granted directory, so a `.txt` sidecar
                // beside each image is sandbox-safe here (unlike a single save panel).
                let sidecar = textSidecar ? config.sidecarText : ""
                let url = directory.appendingPathComponent(
                    "vitrine-\(preset.id).\(format.fileExtension)", isDirectory: false)
                group.addTask {
                    await writePreset(
                        raster: raster, pdf: pdf, format: format, to: url, sidecarText: sidecar)
                }
                // Release the main actor after dispatching each render so the encode/write
                // tasks get to run and the next render doesn't monopolize the run loop.
                await Task.yield()
            }
            // Drain results as encodes/writes finish, reporting count-based progress.
            for await outcome in group {
                switch outcome {
                case .written:
                    written += 1
                case .failed:
                    failed += 1
                case .renderFailed(let error):
                    failed += 1
                    if firstRenderFailure == nil { firstRenderFailure = error }
                }
                completed += 1
                onProgress?(completed, total)
            }
        }
        Log.export.notice(
            "Multi-size export wrote \(written, privacy: .public), failed \(failed, privacy: .public)"
        )
        return BatchExportResult(
            written: written, failed: failed, firstRenderFailure: firstRenderFailure)
    }

    /// Encodes (for raster formats) and writes one multi-size preset off the main
    /// actor — the CPU-bound ImageIO encode plus the disk write for a single preset,
    /// hopped off main via `@concurrent` so the UI stays live during a batch. The
    /// render itself stays on main; only `Sendable` finished pixels (`CGImage`) or
    /// bytes (`Data`) cross the hop. Returns whether the image file was written; a
    /// sidecar failure is best-effort and never fails the image.
    @concurrent nonisolated private static func writePreset(
        raster cgImage: CGImage?, pdf pdfData: Data?, format: ExportFormat,
        to url: URL, sidecarText: String
    ) async -> BatchItemOutcome {
        let data: Data? =
            if case .pdf = format { pdfData } else {
                cgImage.flatMap { rasterData(from: $0, format: format) }
            }
        guard let data else {
            Log.export.error("Multi-size export: render/encode returned nil for a preset")
            return .renderFailed(.encodingFailed)
        }
        do {
            try data.write(to: url)
            if !sidecarText.isEmpty {
                let sidecarURL = url.deletingPathExtension().appendingPathExtension("txt")
                // A missing sidecar must not fail the image it accompanies.
                try? Data(sidecarText.utf8).write(to: sidecarURL)
            }
            return .written
        } catch {
            let nsError = error as NSError
            Log.export.error(
                "Multi-size export write failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            return .failed
        }
    }

    /// The carousel slide frame: 1080×1350 (4:5), the portrait card LinkedIn and
    /// Instagram carousels share.
    static let carouselSlideSize = CGSize(width: 1080, height: 1350)

    /// The minimum font size a carousel slide renders at. The editor's default (~13 pt)
    /// leaves a tiny card adrift in a 1080×1350 frame — illegible at feed size — so
    /// slides bump up to this floor; a user style already at or above it is respected.
    static let carouselMinimumFontSize: Double = 22

    /// Renders one slide per page into `directory` as `carousel-01.png` … — the
    /// carousel export. Each slide is `baseConfig` with only its `code`
    /// replaced by that page's lines, rendered at the fixed 4:5 slide frame through
    /// the standard pipeline; content marks that belong to the whole document
    /// (annotations, highlighted/redacted lines) are cleared so a page never carries a
    /// mark positioned against different lines. Pipelined like `exportPresetSizes`:
    /// render on the main actor, PNG-encode + write off it, results drain in
    /// completion order with count-based progress. Two-digit numbering keeps the
    /// files sorted everywhere; only counts are logged.
    @discardableResult
    static func exportCarousel(
        _ baseConfig: SnapshotConfig, pages: [String], to directory: URL,
        profile: ColorProfile = .sRGB,
        onProgress: (@MainActor (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async -> BatchExportResult {
        var written = 0
        var failed = 0
        var firstRenderFailure: RenderBudgetError?
        let total = pages.count
        var completed = 0
        await withTaskGroup(of: BatchItemOutcome.self) { group in
            for (index, page) in pages.enumerated() {
                var config = baseConfig
                config.clearContentMarks()
                config.code = page
                config.fontSize = max(config.fontSize, carouselMinimumFontSize)
                let raster: CGImage?
                do throws(RenderBudgetError) {
                    raster = try renderCGImageChecked(
                        config, scale: 1, fixedSize: carouselSlideSize, profile: profile)
                } catch let error {
                    Log.export.error(
                        "Carousel export rejected a slide before raster allocation")
                    raster = nil
                    group.addTask { .renderFailed(error) }
                    continue
                }
                let url = directory.appendingPathComponent(
                    String(format: "carousel-%02d.png", index + 1), isDirectory: false)
                group.addTask {
                    await writePreset(
                        raster: raster, pdf: nil, format: .png, to: url, sidecarText: "")
                }
                await Task.yield()
            }
            for await outcome in group {
                switch outcome {
                case .written:
                    written += 1
                case .failed:
                    failed += 1
                case .renderFailed(let error):
                    failed += 1
                    if firstRenderFailure == nil { firstRenderFailure = error }
                }
                completed += 1
                onProgress?(completed, total)
            }
        }
        Log.export.notice(
            "Carousel export wrote \(written, privacy: .public), failed \(failed, privacy: .public)"
        )
        return BatchExportResult(
            written: written, failed: failed, firstRenderFailure: firstRenderFailure)
    }
}
