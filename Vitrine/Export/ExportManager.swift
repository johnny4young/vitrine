import AppKit
import ImageIO
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Renders a `SnapshotConfig` to PNG/PDF and exports it to the clipboard or a file
/// (CS-007/010). PNG encoding goes through ImageIO directly from the rendered
/// `CGImage`; PDF uses `ImageRenderer.render` into a `CGContext` — no legacy
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
        profile: ColorProfile = .sRGB
    ) -> CGImage? {
        let signposter = RenderSignpost.signposter
        let state = signposter.beginInterval(
            RenderSignpost.renderName, "scale=\(Int(scale)) length=\(config.code.count)")
        defer { signposter.endInterval(RenderSignpost.renderName, state) }

        let renderer = ImageRenderer(content: SnapshotCanvas(config: config, fixedSize: fixedSize))
        renderer.scale = scale
        // Pin the layout size for fixed-size presets so the rendered pixel size
        // is exactly `fixedSize × scale` (e.g. OpenGraph 1200×630 at 1×, CS-020).
        if let fixedSize { renderer.proposedSize = ProposedViewSize(fixedSize) }
        guard let cgImage = renderer.cgImage else {
            Log.render.error(
                "Render produced no image (scale \(Int(scale), privacy: .public))")
            return nil
        }
        return normalized(cgImage, to: profile)
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

    /// Renders the canvas to an `NSImage` (used by the share sheet, CS-008).
    static func renderNSImage(
        _ config: SnapshotConfig, scale: CGFloat = 2, fixedSize: CGSize? = nil,
        profile: ColorProfile = .sRGB
    ) -> NSImage? {
        guard
            let cgImage = renderCGImage(
                config, scale: scale, fixedSize: fixedSize, profile: profile)
        else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// PNG-encodes a `CGImage` via ImageIO.
    static func pngData(from cgImage: CGImage) -> Data? {
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

    /// Renders the snapshot canvas for `config` to single-page PDF data, pinning the
    /// page to `fixedSize` for size presets. A thin wrapper over the shared
    /// `pdfData(_:proposedSize:)` rasterizer so the snapshot and social-card PDF paths
    /// share one `CGContext` page dance instead of copying it.
    static func pdfData(_ config: SnapshotConfig, fixedSize: CGSize? = nil) -> Data? {
        pdfData(SnapshotCanvas(config: config, fixedSize: fixedSize), proposedSize: fixedSize)
    }

    /// Renders any SwiftUI `content` to single-page PDF data, pinning the page to
    /// `proposedSize` when given. The single-page `CGDataConsumer`/`CGContext` dance
    /// lives here once and is shared by both the snapshot and social-card PDF exports
    /// (CS-007/041). Returns nil if the page context cannot be created.
    static func pdfData<Content: View>(_ content: Content, proposedSize: CGSize?) -> Data? {
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

    /// The single PNG/PDF format ladder shared by every save/encode path
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
        switch format {
        case .png: png().flatMap(pngData(from:)).map { ($0, .png, "png") }
        case .pdf: pdf().map { ($0, .pdf, "pdf") }
        }
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
        profile: ColorProfile = .sRGB, richText: Bool = false
    ) -> Bool {
        if richText {
            return RichPasteboard.copy(
                config, scale: scale, fixedSize: fixedSize, profile: profile,
                includeRichText: true)
        }
        guard
            let cgImage = renderCGImage(
                config, scale: scale, fixedSize: fixedSize, profile: profile),
            let png = pngData(from: cgImage)
        else {
            Log.export.error("Copy to pasteboard failed: render or PNG encode returned nil")
            return false
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setData(png, forType: .png)
        Log.export.info("Copied image to pasteboard (success \(copied, privacy: .public))")
        return copied
    }

    /// Presents an `NSSavePanel` and writes the image as PNG or PDF.
    ///
    /// `profile` applies to PNG export only (CS-024); PDF is a color-managed
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

        let panel = NSSavePanel()
        panel.allowedContentTypes = [payload.type]
        panel.nameFieldStringValue = "vitrine.\(payload.ext)"
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
        format: ExportFormat = .png, profile: ColorProfile = .sRGB
    ) -> (written: Int, failed: Int) {
        var written = 0
        var failed = 0
        for preset in presets {
            var config = baseConfig
            preset.apply(to: &config)
            let size = preset.sizing.fixedSize
            let payload = encodedPayload(
                format,
                png: {
                    renderCGImage(
                        config, scale: CGFloat(preset.scale), fixedSize: size, profile: profile)
                },
                pdf: { pdfData(config, fixedSize: size) })
            guard let payload else {
                Log.export.error("Multi-size export: render/encode returned nil for a preset")
                failed += 1
                continue
            }
            let url = directory.appendingPathComponent(
                "vitrine-\(preset.id).\(payload.ext)", isDirectory: false)
            do {
                try payload.data.write(to: url)
                written += 1
            } catch {
                let nsError = error as NSError
                Log.export.error(
                    "Multi-size export write failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
                )
                failed += 1
            }
        }
        Log.export.notice(
            "Multi-size export wrote \(written, privacy: .public), failed \(failed, privacy: .public)"
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
