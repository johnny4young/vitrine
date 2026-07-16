import AppKit
import ImageIO
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Renders a `SnapshotConfig` to PNG/PDF/HEIC/AVIF and exports it to the clipboard or a
/// file (CS-007/010). Raster encoding goes through ImageIO directly from the
/// rendered `CGImage`; PDF uses `ImageRenderer.render` into a `CGContext` — no legacy
/// `NSBitmapImageRep`/TIFF round-trip.
///
/// Color management (CS-024): a render is always normalized into an explicit ICC
/// color space before PNG encoding — sRGB by default, Display P3 only as an
/// advanced opt-in. `ImageRenderer` happens to default to sRGB today, but the
/// exporter tags the output deliberately rather than trusting that default, so
/// PNG color is predictable across displays, apps, and social platforms. The
/// normalization preserves the alpha channel (no matte), so a transparent
/// background exports with real transparency.
enum ExportManager {
    /// Replaces the pasteboard contents with the exact plain-text source.
    ///
    /// Accepting a pasteboard keeps the primitive deterministic in tests and avoids
    /// touching the developer's clipboard outside the user-initiated default path.
    @discardableResult
    static func copySourceToPasteboard(
        _ source: String, to pasteboard: NSPasteboard = .general
    ) -> Bool {
        pasteboard.clearContents()
        let copied = pasteboard.setString(source, forType: .string)
        Log.export.info("Copied source to pasteboard (success \(copied, privacy: .public))")
        return copied
    }

    /// Renders the canvas for `config` to a `CGImage` at the given scale (1/2/3),
    /// normalized into `profile`'s color space (sRGB by default, CS-024).
    ///
    /// The render is wrapped in an `os_signpost` interval (CS-048) so render
    /// latency can be measured in Instruments/the unified log without timing code
    /// in the hot path — this is the signal CS-026's performance budget consumes.
    /// Only non-PII measures are attached to the signpost and the log (the code
    /// length and scale), never the code itself.
    static func renderCGImage(
        _ config: SnapshotConfig, scale: CGFloat = 2, fixedSize: CGSize? = nil,
        profile: ColorProfile = .sRGB,
        backgroundImageStore: BackgroundImageStore = .container,
        foregroundImageStore: BackgroundImageStore = .foregroundContainer
    ) -> CGImage? {
        let signposter = RenderSignpost.signposter
        let state = signposter.beginInterval(
            RenderSignpost.renderName, "scale=\(Int(scale)) length=\(config.code.count)")
        defer { signposter.endInterval(RenderSignpost.renderName, state) }

        let renderer = ImageRenderer(
            content: SnapshotCanvas(config: config, fixedSize: fixedSize)
                .environment(\.backgroundImageStore, backgroundImageStore)
                .environment(\.foregroundImageStore, foregroundImageStore))
        renderer.scale = scale
        // Pin the layout size for fixed-size presets so the rendered pixel size
        // is exactly `fixedSize × scale` (e.g. OpenGraph 1200×630 at 1×, CS-020).
        if let fixedSize { renderer.proposedSize = ProposedViewSize(fixedSize) }
        guard let cgImage = renderer.cgImage else {
            Log.render.error(
                "Render produced no image (scale \(Int(scale), privacy: .public))")
            return nil
        }
        let normalizedImage = normalized(cgImage, to: profile)
        if case .image = config.background {
            return compositedOverBlack(normalizedImage)
        }
        return normalizedImage
    }

    /// Converts a rendered `CGImage` into `profile`'s color space, redrawing it
    /// through a Core Graphics context so the result is both *converted* (the
    /// sRGB↔P3 matrix is applied) and *tagged* with that ICC profile (CS-024).
    ///
    /// The destination context keeps an alpha channel (`premultipliedLast`) and
    /// is initialized fully transparent, so a transparent-background render keeps
    /// real alpha — its empty regions stay `(0,0,0,0)` and are never composited
    /// over an opaque matte. If the target color space cannot be created (it is
    /// a system constant, so this is not expected) or the context fails, the
    /// original image is returned unchanged rather than failing the export.
    static func normalized(_ cgImage: CGImage, to profile: ColorProfile) -> CGImage {
        guard let colorSpace = profile.cgColorSpace else {
            Log.render.error("Color space unavailable; exporting render untagged")
            return cgImage
        }
        // Skip the full-bitmap allocate+draw+copy when the render is already in the exact
        // output format (same color space, 8 bpc, premultiplied-last alpha) — the common
        // default-sRGB path otherwise pays a no-op conversion on every export and thumbnail
        // (audit P1-Perf-2). The redraw still runs for a real sRGB↔P3 conversion or any other
        // pixel format, so the produced bytes are unchanged.
        if let space = cgImage.colorSpace, space.name == colorSpace.name,
            cgImage.bitsPerComponent == 8,
            cgImage.alphaInfo == .premultipliedLast
        {
            return cgImage
        }
        let width = cgImage.width
        let height = cgImage.height
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            Log.render.error("Color context creation failed; exporting render untagged")
            return cgImage
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? cgImage
    }

    /// Makes an image-backed snapshot fully opaque after the complete SwiftUI
    /// hierarchy has rendered. Applying a matte inside `BackgroundView` can make
    /// `ImageRenderer` composite that layer above selectable text in fit mode;
    /// flattening the finished bitmap preserves the foreground while filling fit
    /// letterboxes and translucent blur edges deterministically.
    private static func compositedOverBlack(_ cgImage: CGImage) -> CGImage {
        guard
            let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            Log.render.error("Opaque image-background context creation failed")
            return cgImage
        }
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(bounds)
        context.draw(cgImage, in: bounds)
        return context.makeImage() ?? cgImage
    }

    /// Renders the canvas to an `NSImage` (used by the share sheet, CS-008).
    static func renderNSImage(
        _ config: SnapshotConfig, scale: CGFloat = 2, fixedSize: CGSize? = nil,
        profile: ColorProfile = .sRGB,
        backgroundImageStore: BackgroundImageStore = .container,
        foregroundImageStore: BackgroundImageStore = .foregroundContainer
    ) -> NSImage? {
        guard
            let cgImage = renderCGImage(
                config, scale: scale, fixedSize: fixedSize, profile: profile,
                backgroundImageStore: backgroundImageStore,
                foregroundImageStore: foregroundImageStore)
        else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// PNG-encodes a `CGImage` via ImageIO. `nonisolated` because it is a pure
    /// function of a `Sendable` `CGImage` over thread-safe ImageIO, so the multi-size
    /// export can encode off the main actor (C3).
    nonisolated static func pngData(from cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil
            )
        else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// HEIC-encodes a `CGImage` via ImageIO — the same rendered, color-managed
    /// image the PNG path uses, in a far smaller container for docs sites and
    /// wikis that accept it. Alpha survives (HEIC carries an alpha plane), and
    /// the near-lossless quality keeps text crisp; the codec is still lossy, so
    /// PNG remains the byte-exact default.
    nonisolated static func heicData(from cgImage: CGImage) -> Data? {
        lossyImageData(
            from: cgImage, typeIdentifier: UTType.heic.identifier, quality: 0.95)
    }

    /// AVIF-encodes a `CGImage` through ImageIO. AVIF keeps the same color-managed
    /// pixels and alpha channel as PNG while producing compact web-ready artifacts.
    /// `UTType` does not currently expose an `avif` static convenience, so the
    /// system-declared public identifier is resolved explicitly.
    nonisolated static func avifData(from cgImage: CGImage) -> Data? {
        lossyImageData(from: cgImage, typeIdentifier: "public.avif", quality: 0.95)
    }

    /// Shared ImageIO path for alpha-capable lossy raster formats. Keeping destination
    /// creation, quality, image addition, and finalization in one place prevents HEIC
    /// and AVIF behavior from drifting as export surfaces evolve.
    nonisolated private static func lossyImageData(
        from cgImage: CGImage, typeIdentifier: String, quality: Double
    ) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, typeIdentifier as CFString, 1, nil
            )
        else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Renders the snapshot canvas for `config` to single-page PDF data, pinning the
    /// page to `fixedSize` for size presets. A thin wrapper over the shared
    /// `pdfData(_:proposedSize:)` rasterizer so the snapshot and social-card PDF paths
    /// share one `CGContext` page dance instead of copying it.
    static func pdfData(
        _ config: SnapshotConfig, fixedSize: CGSize? = nil,
        backgroundImageStore: BackgroundImageStore = .container,
        foregroundImageStore: BackgroundImageStore = .foregroundContainer
    ) -> Data? {
        let opaqueMatte: CGColor? =
            if case .image = config.background { CGColor(gray: 0, alpha: 1) } else { nil }
        return pdfData(
            SnapshotCanvas(config: config, fixedSize: fixedSize)
                .environment(\.backgroundImageStore, backgroundImageStore)
                .environment(\.foregroundImageStore, foregroundImageStore),
            proposedSize: fixedSize, opaqueMatte: opaqueMatte)
    }

    /// Renders any SwiftUI `content` to single-page PDF data, pinning the page to
    /// `proposedSize` when given. The single-page `CGDataConsumer`/`CGContext` dance
    /// lives here once and is shared by both the snapshot and social-card PDF exports
    /// (CS-007/041). Returns nil if the page context cannot be created.
    static func pdfData<Content: View>(
        _ content: Content, proposedSize: CGSize?, opaqueMatte: CGColor? = nil
    ) -> Data? {
        let renderer = ImageRenderer(content: content)
        if let proposedSize { renderer.proposedSize = ProposedViewSize(proposedSize) }
        let data = NSMutableData()
        var produced = false
        renderer.render { size, renderInContext in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
            else { return }
            context.beginPDFPage(nil)
            if let opaqueMatte {
                context.setFillColor(opaqueMatte)
                context.fill(mediaBox)
            }
            renderInContext(context)
            context.endPDFPage()
            context.closePDF()
            produced = true
        }
        return produced ? data as Data : nil
    }

    /// Wraps a finished `CGImage` in single-page PDF data at its own pixel size — the
    /// `CGImage` analogue of the view-based `pdfData(_:proposedSize:)`, for export
    /// paths (web snapshots) that already hold a rasterized bitmap rather than a SwiftUI
    /// view. Returns nil if the PDF page context cannot be created.
    static func pdfData(from cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }
        context.beginPDFPage(nil)
        context.draw(cgImage, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// The single PNG/PDF/HEIC/AVIF format ladder shared by every save/encode path
    /// (CS-007/041). Given a render strategy for each branch — a `png` producer of a
    /// `CGImage` and a `pdf` producer of finished `Data` — it picks the branch for
    /// `format`, encodes PNG through the shared color-managed ImageIO path, and pairs
    /// the bytes with the matching content type and file extension. Returns nil if the
    /// chosen render or encode yields nothing. Centralizing the switch here keeps a
    /// snapshot and a social card (and the automation surface) from ever drifting on
    /// what "PNG"/"PDF" encodes to.
    static func encodedPayload(
        _ format: ExportFormat, png: () -> CGImage?, pdf: () -> Data?
    ) -> (data: Data, type: UTType, ext: String)? {
        if case .pdf = format { return pdf().map { ($0, .pdf, "pdf") } }
        // Raster formats encode the exact rendered, color-managed CGImage the PNG path
        // produces — they differ only in container/codec, so no call site needs
        // another render closure.
        guard let cgImage = png(),
            let data = rasterData(from: cgImage, format: format),
            let metadata = rasterMetadata(for: format)
        else { return nil }
        return (data, metadata.type, metadata.ext)
    }

    /// The single raster format→bytes mapping (deep-review finding): every save/batch
    /// path used to carry its own PNG/HEIC/AVIF switch, three copies that had to stay
    /// in sync by hand. `nonisolated` — a pure function of a `Sendable` `CGImage` —
    /// so the main-actor payload ladder and the off-main batch writer share it.
    nonisolated static func rasterData(from cgImage: CGImage, format: ExportFormat) -> Data? {
        switch format {
        case .png: pngData(from: cgImage)
        case .heic: heicData(from: cgImage)
        case .avif: avifData(from: cgImage)
        case .pdf: nil
        }
    }

    /// The content type + extension a raster format encodes to; `nil` for PDF (a
    /// vector document, not a raster encode).
    nonisolated static func rasterMetadata(
        for format: ExportFormat
    ) -> (type: UTType, ext: String)? {
        switch format {
        case .png: (.png, "png")
        case .heic: (.heic, "heic")
        case .avif: (avifContentType, "avif")
        case .pdf: nil
        }
    }

    /// The public AVIF type is system-declared on supported macOS releases, but the
    /// Swift overlay has no `UTType.avif` convenience. Resolve it by identifier for
    /// save panels, with an imported image type as a defensive fallback.
    nonisolated static var avifContentType: UTType {
        UTType("public.avif") ?? UTType(importedAs: "public.avif", conformingTo: .image)
    }

    /// Renders and writes the image to the general pasteboard. Returns success.
    ///
    /// By default this places a single PNG representation — the unchanged
    /// one-shortcut copy. When `richText` is true (the user opted into the rich
    /// clipboard, CS-054), it instead places a multi-representation item: the same
    /// PNG plus the highlighted code as RTF and HTML, so a paste into a rich-text
    /// editor keeps the syntax colors and font while an image well still receives
    /// the picture. The PNG round-trip is identical in both modes — `richText`
    /// only *adds* representations, never changes the image bytes.
    @discardableResult
    static func copyToPasteboard(
        _ config: SnapshotConfig, scale: CGFloat = 2, fixedSize: CGSize? = nil,
        profile: ColorProfile = .sRGB, richText: Bool = false, plainText: Bool = false,
        backgroundImageStore: BackgroundImageStore = .container,
        foregroundImageStore: BackgroundImageStore = .foregroundContainer
    ) -> Bool {
        // Either opt-in (rich styled text, or the plain-text rider) needs the
        // multi-representation item, so route both through RichPasteboard; the plain
        // image fast-path stays for the default copy that asked for neither.
        if richText || plainText {
            return RichPasteboard.copy(
                config, scale: scale, fixedSize: fixedSize, profile: profile,
                includeRichText: richText, includePlainText: plainText,
                backgroundImageStore: backgroundImageStore,
                foregroundImageStore: foregroundImageStore)
        }
        guard
            let cgImage = renderCGImage(
                config, scale: scale, fixedSize: fixedSize, profile: profile,
                backgroundImageStore: backgroundImageStore,
                foregroundImageStore: foregroundImageStore)
        else {
            Log.export.error("Copy to pasteboard failed: render returned nil")
            return false
        }
        return copyPNGToPasteboard(cgImage)
    }

    /// Writes a PNG of an already-rendered `cgImage` to the general pasteboard —
    /// the shared primitive behind the config-based copy above and editors that
    /// hold a rendered asset (the web snapshot editor). Returns success.
    @discardableResult
    static func copyPNGToPasteboard(_ cgImage: CGImage) -> Bool {
        guard let png = pngData(from: cgImage) else {
            Log.export.error("Copy to pasteboard failed: PNG encode returned nil")
            return false
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setData(png, forType: .png)
        Log.export.info("Copied image to pasteboard (success \(copied, privacy: .public))")
        return copied
    }

    /// Presents an `NSSavePanel` and writes the image as PNG, PDF, HEIC, or AVIF.
    ///
    /// `profile` applies to raster export only (CS-024); PDF is a color-managed
    /// vector document and is unaffected by the raster color-profile choice.
    ///
    /// Returns the outcome so a caller can give the user precise feedback
    /// (CS-038): `.saved` when a file was written, `.cancelled` when the user
    /// dismissed the panel, and `.failed` when rendering, encoding, or the write
    /// itself failed. The result is discardable for callers that do not care.
    @discardableResult
    static func saveToFile(
        _ config: SnapshotConfig, scale: CGFloat = 2, format: ExportFormat = .png,
        fixedSize: CGSize? = nil, profile: ColorProfile = .sRGB
    ) -> SaveOutcome {
        let payload = encodedPayload(
            format,
            png: { renderCGImage(config, scale: scale, fixedSize: fixedSize, profile: profile) },
            pdf: { pdfData(config, fixedSize: fixedSize) })
        guard let payload else {
            Log.export.error("Save to file failed: render or encode returned nil")
            return .failed
        }
        return saveToFile(
            payload: payload, suggestedName: SuggestedFilename.basename(for: config))
    }

    /// Saves an **already-rendered** raster `cgImage` as PNG, HEIC, or AVIF (P5): the
    /// quick-capture path renders the styled image once and reuses it for both the
    /// clipboard copy and this file save instead of re-rendering the identical config.
    /// PDF is a vector document and must render its own page, so it is not accepted here
    /// — callers save PDF through the `config`-based `saveToFile` above.
    @discardableResult
    static func saveToFile(
        cgImage: CGImage, format: ExportFormat, suggestedName: String
    ) -> SaveOutcome {
        guard let data = rasterData(from: cgImage, format: format),
            let metadata = rasterMetadata(for: format)
        else {
            Log.export.error("Save to file failed: raster encode returned nil or PDF via cgImage")
            return .failed
        }
        return saveToFile(
            payload: (data, metadata.type, metadata.ext), suggestedName: suggestedName)
    }

    /// Presents the save panel for an already-encoded payload and writes it — the
    /// shared panel/write/log dance behind every save flow (the config path above,
    /// the social-card renderer, and the web editor), so the CS-048 logging rule
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
            // the path itself (CS-048 privacy rule).
            try payload.data.write(to: url)
            Log.export.notice("Saved image to file (\(payload.ext, privacy: .public))")
            return .saved
        } catch {
            // Log only the error domain/code — never `localizedDescription`, which
            // can embed the (user-chosen) filename (CS-048 privacy rule).
            let nsError = error as NSError
            Log.export.error(
                "Saving image to file failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            return .failed
        }
    }

    /// Renders `baseConfig` once per preset and writes one file per preset into
    /// `directory` — the PRO multi-size one-pass export (CS-093).
    ///
    /// This is the single-export ladder fanned out, not a new encoder: for each
    /// preset it applies that preset's presentation (`apply(to:)` writes padding +
    /// background, leaving `code`/`language`/any watermark intact) and renders at the
    /// preset's pinned `fixedSize` and `scale` through the same color-managed
    /// `encodedPayload` path. So each written file is byte-for-byte what a single
    /// export with THAT preset selected (at its pinned scale) produces. Files are
    /// named `vitrine-<preset id>.<ext>`. Returns how many were written and how many
    /// presets failed, so the caller can give precise feedback (CS-038). Only the
    /// format/counts are logged, never the chosen folder path (CS-048).
    @discardableResult
    static func exportPresetSizes(
        _ baseConfig: SnapshotConfig, presets: [ExportPreset], to directory: URL,
        format: ExportFormat = .png, profile: ColorProfile = .sRGB, textSidecar: Bool = false,
        onProgress: (@MainActor (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async -> (written: Int, failed: Int) {
        var written = 0
        var failed = 0
        let total = presets.count
        // Pipeline the batch: each preset renders on the main actor (`ImageRenderer`
        // requires it), then its CPU-bound encode + disk write run off-main as a child
        // task while the main actor immediately moves on to render the next preset. So
        // a batch of large presets at 2–3× scale neither beachballs the app nor waits
        // for one preset's encode before starting the next (C3). Each writes a distinct
        // `vitrine-<preset id>` file, so the concurrent writes never collide.
        var completed = 0
        await withTaskGroup(of: Bool.self) { group in
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
                    raster = renderCGImage(
                        config, scale: CGFloat(preset.scale), fixedSize: size, profile: profile)
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
            for await ok in group {
                if ok { written += 1 } else { failed += 1 }
                completed += 1
                onProgress?(completed, total)
            }
        }
        Log.export.notice(
            "Multi-size export wrote \(written, privacy: .public), failed \(failed, privacy: .public)"
        )
        return (written, failed)
    }

    /// Encodes (for raster formats) and writes one multi-size preset off the main
    /// actor — the CPU-bound ImageIO encode plus the disk write for a single preset,
    /// hopped off main via `@concurrent` so the UI stays live during a batch (C3). The
    /// render itself stays on main; only `Sendable` finished pixels (`CGImage`) or
    /// bytes (`Data`) cross the hop. Returns whether the image file was written; a
    /// sidecar failure is best-effort and never fails the image.
    @concurrent nonisolated private static func writePreset(
        raster cgImage: CGImage?, pdf pdfData: Data?, format: ExportFormat,
        to url: URL, sidecarText: String
    ) async -> Bool {
        let data: Data? =
            if case .pdf = format { pdfData } else {
                cgImage.flatMap { rasterData(from: $0, format: format) }
            }
        guard let data else {
            Log.export.error("Multi-size export: render/encode returned nil for a preset")
            return false
        }
        do {
            try data.write(to: url)
            if !sidecarText.isEmpty {
                let sidecarURL = url.deletingPathExtension().appendingPathExtension("txt")
                // A missing sidecar must not fail the image it accompanies.
                try? Data(sidecarText.utf8).write(to: sidecarURL)
            }
            return true
        } catch {
            let nsError = error as NSError
            Log.export.error(
                "Multi-size export write failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            return false
        }
    }

    /// The carousel slide frame: 1080×1350 (4:5), the portrait card LinkedIn and
    /// Instagram carousels share (feature #15).
    static let carouselSlideSize = CGSize(width: 1080, height: 1350)

    /// The minimum font size a carousel slide renders at. The editor's default (~13 pt)
    /// leaves a tiny card adrift in a 1080×1350 frame — illegible at feed size — so
    /// slides bump up to this floor; a user style already at or above it is respected.
    static let carouselMinimumFontSize: Double = 22

    /// Renders one slide per page into `directory` as `carousel-01.png` … — the
    /// carousel export (feature #15). Each slide is `baseConfig` with only its `code`
    /// replaced by that page's lines, rendered at the fixed 4:5 slide frame through
    /// the standard pipeline; content marks that belong to the whole document
    /// (annotations, highlighted/redacted lines) are cleared so a page never carries a
    /// mark positioned against different lines. Pipelined like `exportPresetSizes`:
    /// render on the main actor, PNG-encode + write off it, results drain in
    /// completion order with count-based progress. Two-digit numbering keeps the
    /// files sorted everywhere; only counts are logged (CS-048).
    @discardableResult
    static func exportCarousel(
        _ baseConfig: SnapshotConfig, pages: [String], to directory: URL,
        profile: ColorProfile = .sRGB,
        onProgress: (@MainActor (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async -> (written: Int, failed: Int) {
        var written = 0
        var failed = 0
        let total = pages.count
        var completed = 0
        await withTaskGroup(of: Bool.self) { group in
            for (index, page) in pages.enumerated() {
                var config = baseConfig
                config.clearContentMarks()
                config.code = page
                config.fontSize = max(config.fontSize, carouselMinimumFontSize)
                let raster = renderCGImage(
                    config, scale: 1, fixedSize: carouselSlideSize, profile: profile)
                let url = directory.appendingPathComponent(
                    String(format: "carousel-%02d.png", index + 1), isDirectory: false)
                group.addTask {
                    await writePreset(
                        raster: raster, pdf: nil, format: .png, to: url, sidecarText: "")
                }
                await Task.yield()
            }
            for await ok in group {
                if ok { written += 1 } else { failed += 1 }
                completed += 1
                onProgress?(completed, total)
            }
        }
        Log.export.notice(
            "Carousel export wrote \(written, privacy: .public), failed \(failed, privacy: .public)"
        )
        return (written, failed)
    }

    /// The outcome of a save-to-file attempt, so callers can tell apart a written
    /// file, a user cancel, and a genuine failure for feedback (CS-038).
    enum SaveOutcome: Equatable {
        case saved
        case cancelled
        case failed
    }
}
