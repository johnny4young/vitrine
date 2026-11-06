import AppKit
import OSLog
import VitrineDomain
import VitrineRendering

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
    /// named `vitrine-<preset id>.<ext>`, with a numeric suffix when any image or
    /// requested sidecar name is occupied. Returns how many were written and how many
    /// presets failed, so the caller can give precise feedback. Only the
    /// format/counts are logged, never the chosen folder path.
    @discardableResult
    static func exportPresetSizes(
        _ baseConfig: SnapshotConfig, presets: [ExportPreset], to directory: URL,
        format: ExportFormat = .png, profile: ColorProfile = .sRGB, textSidecar: Bool = false,
        onProgress: (@MainActor (_ completed: Int, _ total: Int) -> Void)? = nil,
        writeFile: @escaping @Sendable (Data, URL) throws -> Void = {
            try BatchOutputFiles.publish($0, to: $1)
        }
    ) async -> BatchExportResult {
        var written = 0
        var failed = 0
        var firstRenderFailure: RenderBudgetError?
        let total = presets.count
        let outputs: [BatchOutputFiles.Item]
        do {
            outputs = try BatchOutputFiles.plan(
                filenames: presets.map { "vitrine-\($0.id).\(format.fileExtension)" },
                in: directory, textSidecars: textSidecar)
        } catch {
            onProgress?(total, total)
            return BatchExportResult(written: 0, failed: total, firstRenderFailure: nil)
        }
        // Pipeline the batch: each preset renders on the main actor (`ImageRenderer`
        // requires it), then its CPU-bound encode + disk write run off-main as a child
        // task while the main actor immediately moves on to render the next preset. So
        // a batch of large presets at 2–3× scale neither beachballs the app nor waits
        // for one preset's encode before starting the next. Each writes a distinct
        // `vitrine-<preset id>` file, so the concurrent writes never collide.
        var completed = 0
        await withTaskGroup(of: BatchItemOutcome.self) { group in
            for (preset, output) in zip(presets, outputs) {
                guard !Task.isCancelled else {
                    group.addTask { .failed }
                    continue
                }
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
                group.addTask {
                    await writePreset(
                        raster: raster, pdf: pdf, format: format, output: output,
                        sidecarText: sidecar, writeFile: writeFile)
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
    /// bytes (`Data`) cross the hop. Every requested nonempty sidecar must succeed;
    /// partial publication is reported as failure and keeps any completed image.
    @concurrent nonisolated private static func writePreset(
        raster cgImage: CGImage?, pdf pdfData: Data?, format: ExportFormat,
        output: BatchOutputFiles.Item, sidecarText: String,
        writeFile: @Sendable (Data, URL) throws -> Void
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
            try Task.checkCancellation()
            try writeFile(data, output.image)
            if !sidecarText.isEmpty, let sidecar = output.sidecar {
                try Task.checkCancellation()
                try writeFile(Data(sidecarText.utf8), sidecar)
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

    /// The default slide frame, LinkedIn's 4:5 portrait card.
    static let carouselSlideSize = CarouselSlideSize.linkedIn.pixels

    /// The smallest type a fitted slide gets: a line too wide even at this size overflows
    /// rather than shrinking past legibility, and the sheet says so.
    static let carouselMinimumFontSize: Double = 14

    /// Renders one slide per page into `directory` as `carousel-01.png` …, a `carousel.pdf`
    /// with a page per slide, or both, every slide at the size's frame and `fit`'s type
    /// size (fitted here when not given). PDF pages render first, releasing the main actor
    /// between pages; PNGs render on the main actor and encode + write off it. Progress
    /// counts PDF pages and PNG files; the result counts files. Only counts are logged.
    @discardableResult
    static func exportCarousel(
        _ baseConfig: SnapshotConfig, slides: [CarouselPaginator.Slide],
        cues: CarouselPaginator.Cues = .none, size: CarouselSlideSize = .linkedIn,
        fit: CarouselFit? = nil, output: CarouselOutput = .pngSet, to directory: URL,
        profile: ColorProfile = .sRGB,
        onProgress: (@MainActor (_ completed: Int, _ total: Int) -> Void)? = nil,
        writeFile: @escaping @Sendable (Data, URL) throws -> Void = {
            try BatchOutputFiles.publish($0, to: $1)
        }
    ) async -> BatchExportResult {
        var written = 0
        var failed = 0
        var firstRenderFailure: RenderBudgetError?
        let requested = CarouselPaginator.requestedFilenames(
            slideCount: slides.count, output: output)
        let total = carouselProgressUnits(slideCount: slides.count, output: output)
        var outputs: [BatchOutputFiles.Item]
        do {
            outputs = try BatchOutputFiles.plan(filenames: requested, in: directory)
        } catch {
            onProgress?(total, total)
            return BatchExportResult(written: 0, failed: requested.count, firstRenderFailure: nil)
        }
        let fit = fit ?? CarouselPaginator.fit(baseConfig, slides: slides, cues: cues, size: size)
        let configs = slides.indices.map { index in
            CarouselPaginator.slideConfig(
                baseConfig, slide: slides[index], at: index, of: slides.count, cues: cues,
                fontSize: fit.fontSize)
        }
        let pdfOutput = output.writesPDF ? outputs.popLast() : nil
        var completed = 0
        // Each outcome says whether it is the PDF, whose progress was counted by page.
        await withTaskGroup(of: (BatchItemOutcome, Bool).self) { group in
            if let pdfOutput {
                let pdf = await pdfData(
                    pages: configs, fixedSize: size.pixels, rasterized: fit.overflows,
                    profile: profile,
                    onPage: { _ in
                        completed += 1
                        onProgress?(completed, total)
                    })
                group.addTask {
                    let outcome = await writePreset(
                        raster: nil, pdf: pdf, format: .pdf, output: pdfOutput,
                        sidecarText: "", writeFile: writeFile)
                    return (outcome, true)
                }
            }
            for (config, output) in zip(configs, outputs) {
                guard !Task.isCancelled else {
                    group.addTask { (.failed, false) }
                    continue
                }
                let raster: CGImage?
                do throws(RenderBudgetError) {
                    raster = try renderCGImageChecked(
                        config, scale: 1, fixedSize: size.pixels, profile: profile)
                } catch let error {
                    Log.export.error(
                        "Carousel export rejected a slide before raster allocation")
                    raster = nil
                    group.addTask { (.renderFailed(error), false) }
                    continue
                }
                group.addTask {
                    let outcome = await writePreset(
                        raster: raster, pdf: nil, format: .png, output: output,
                        sidecarText: "", writeFile: writeFile)
                    return (outcome, false)
                }
                await Task.yield()
            }
            for await (outcome, isPDF) in group {
                switch outcome {
                case .written:
                    written += 1
                case .failed:
                    failed += 1
                case .renderFailed(let error):
                    failed += 1
                    if firstRenderFailure == nil { firstRenderFailure = error }
                }
                if !isPDF {
                    completed += 1
                    onProgress?(completed, total)
                }
            }
        }
        Log.export.notice(
            "Carousel export wrote \(written, privacy: .public), failed \(failed, privacy: .public)"
        )
        return BatchExportResult(
            written: written, failed: failed, firstRenderFailure: firstRenderFailure)
    }

    /// The steps a carousel export reports: one per PNG and one per PDF page.
    static func carouselProgressUnits(slideCount: Int, output: CarouselOutput) -> Int {
        (output.writesPNG ? slideCount : 0) + (output.writesPDF ? slideCount : 0)
    }

    /// The bytes `output` should take, sampled from the slides that can be previewed: the
    /// first one's PNG times the slide count, and a PDF of the first two, whose difference is
    /// what a page adds once the fonts are embedded. Renders on the main actor and writes nothing.
    static func estimatedCarouselBytes(
        _ baseConfig: SnapshotConfig, slides: [CarouselPaginator.Slide],
        cues: CarouselPaginator.Cues, size: CarouselSlideSize = .linkedIn,
        fit: CarouselFit? = nil, output: CarouselOutput = .pngSet, profile: ColorProfile = .sRGB
    ) async -> Int? {
        let fit = fit ?? CarouselPaginator.fit(baseConfig, slides: slides, cues: cues, size: size)
        let samples = slides.indices.filter { slides[$0].canPreview }.prefix(2).map { index in
            CarouselPaginator.slideConfig(
                baseConfig, slide: slides[index], at: index, of: slides.count, cues: cues,
                fontSize: fit.fontSize)
        }
        guard let first = samples.first else { return nil }
        var total = 0
        if output.writesPDF {
            func pdfBytes(_ pages: [SnapshotConfig]) async -> Int? {
                await pdfData(
                    pages: pages, fixedSize: size.pixels, rasterized: fit.overflows,
                    profile: profile)?.count
            }
            guard let one = await pdfBytes([first]), let both = await pdfBytes(samples)
            else { return nil }
            let perPage = samples.count > 1 ? both - one : one
            total += one + (slides.count - 1) * perPage
        }
        if output.writesPNG {
            guard
                let raster = try? renderCGImageChecked(
                    first, scale: 1, fixedSize: size.pixels, profile: profile),
                let bytes = await encodedByteCount(raster, format: .png)
            else { return nil }
            total += bytes * slides.count
        }
        return total
    }

    /// The encoded size of one preset's file, rendered as `exportPresetSizes` renders it.
    /// Writes nothing, and `nil` means the export would fail for this preset too.
    static func estimatedPresetBytes(
        _ baseConfig: SnapshotConfig, preset: ExportPreset, format: ExportFormat,
        profile: ColorProfile = .sRGB
    ) async -> Int? {
        var config = baseConfig
        preset.apply(to: &config)
        let size = preset.sizing.fixedSize
        if format == .pdf { return pdfData(config, fixedSize: size)?.count }
        guard
            let raster = try? renderCGImageChecked(
                config, scale: CGFloat(preset.scale), fixedSize: size, profile: profile)
        else { return nil }
        return await encodedByteCount(raster, format: format)
    }

    @concurrent nonisolated private static func encodedByteCount(
        _ image: CGImage, format: ExportFormat
    ) async -> Int? {
        rasterData(from: image, format: format)?.count
    }

    /// One finished raster in an image-set export, named without its extension.
    nonisolated struct NamedRaster: Sendable {
        let name: String
        let image: CGImage
    }

    /// Writes already-rendered rasters into `directory` in `format`, encoding off the main
    /// actor. PDF pages are sized in points at `scale`; an existing file is never replaced,
    /// the new one takes the next free `name-2`, `name-3`, … instead.
    @discardableResult
    static func exportRasters(
        _ items: [NamedRaster], to directory: URL, format: ExportFormat, scale: CGFloat
    ) async -> BatchExportResult {
        var claimed: Set<String> = []
        let targets = items.map { item in
            let url = availableFileURL(
                in: directory, name: item.name, fileExtension: format.fileExtension,
                isTaken: {
                    claimed.contains($0.lastPathComponent)
                        || FileManager.default.fileExists(atPath: $0.path)
                })
            claimed.insert(url.lastPathComponent)
            return (item.image, url)
        }
        var written = 0
        var failed = 0
        await withTaskGroup(of: Bool.self) { group in
            for (image, url) in targets {
                group.addTask {
                    await writeRaster(image, format: format, scale: scale, to: url)
                }
            }
            for await succeeded in group {
                if succeeded { written += 1 } else { failed += 1 }
            }
        }
        Log.export.notice(
            "Image-set export wrote \(written, privacy: .public), failed \(failed, privacy: .public)"
        )
        return BatchExportResult(written: written, failed: failed, firstRenderFailure: nil)
    }

    /// The first `name.ext`, `name-2.ext`, … in `directory` that `isTaken` does not claim.
    static func availableFileURL(
        in directory: URL, name: String, fileExtension: String, isTaken: (URL) -> Bool
    ) -> URL {
        var candidate = directory.appendingPathComponent("\(name).\(fileExtension)")
        var suffix = 2
        while isTaken(candidate) {
            candidate = directory.appendingPathComponent("\(name)-\(suffix).\(fileExtension)")
            suffix += 1
        }
        return candidate
    }

    @concurrent nonisolated private static func writeRaster(
        _ image: CGImage, format: ExportFormat, scale: CGFloat, to url: URL
    ) async -> Bool {
        let data: Data? =
            if case .pdf = format {
                pdfData(from: image, scale: scale)
            } else {
                rasterData(from: image, format: format)
            }
        guard let data else {
            Log.export.error("Image-set export: encode returned nil")
            return false
        }
        do {
            try data.write(to: url, options: .withoutOverwriting)
            return true
        } catch {
            let nsError = error as NSError
            Log.export.error(
                "Image-set export write failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            return false
        }
    }
}
