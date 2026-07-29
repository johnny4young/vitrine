import AppKit
import ImageIO
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Renders a `SnapshotConfig` to PNG/PDF/HEIC/AVIF and exports it to the clipboard or a
/// file. Raster encoding goes through ImageIO directly from the
/// rendered `CGImage`; PDF uses `ImageRenderer.render` into a `CGContext` — no legacy
/// `NSBitmapImageRep`/TIFF round-trip.
///
/// Color management: a render is always normalized into an explicit ICC
/// color space before PNG encoding — sRGB by default, Display P3 only as an
/// advanced opt-in. `ImageRenderer` happens to default to sRGB today, but the
/// exporter tags the output deliberately rather than trusting that default, so
/// PNG color is predictable across displays, apps, and social platforms. The
/// normalization preserves the alpha channel (no matte), so a transparent
/// background exports with real transparency.
enum ExportManager {
    /// Renders the canvas for `config` to a `CGImage` at the given scale (1/2/3),
    /// normalized into `profile`'s color space (sRGB by default).
    ///
    /// The render is wrapped in an `os_signpost` interval so render
    /// latency can be measured in Instruments/the unified log without timing code
    /// in the hot path — this is the signal consumed by the render performance budget.
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
        // is exactly `fixedSize × scale` (e.g. OpenGraph 1200×630 at 1×).
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
    /// sRGB↔P3 matrix is applied) and *tagged* with that ICC profile.
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
        // default-sRGB path otherwise pays a no-op conversion on every export and thumbnail.
        // The redraw still runs for a real sRGB↔P3 conversion or any other
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

    /// Renders the canvas to an `NSImage` (used by the share sheet).
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
    /// export can encode off the main actor.
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
    /// lives here once and is shared by both the snapshot and social-card PDF exports.
    /// Returns nil if the page context cannot be created.
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

    /// The single PNG/PDF/HEIC/AVIF format ladder shared by every save/encode path.
    /// Given a render strategy for each branch — a `png` producer of a
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

    /// The single raster format→bytes mapping: every save/batch
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
}
