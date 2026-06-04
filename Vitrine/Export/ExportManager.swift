import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders a `SnapshotConfig` to PNG/PDF and exports it to the clipboard or a file
/// (CS-007/010). PNG encoding goes through ImageIO directly from the rendered
/// `CGImage`; PDF uses `ImageRenderer.render` into a `CGContext` — no legacy
/// `NSBitmapImageRep`/TIFF round-trip.
enum ExportManager {
    /// Renders the canvas for `config` to a `CGImage` at the given scale (1/2/3).
    static func renderCGImage(_ config: SnapshotConfig, scale: CGFloat = 2) -> CGImage? {
        let renderer = ImageRenderer(content: SnapshotCanvas(config: config))
        renderer.scale = scale
        return renderer.cgImage
    }

    /// Renders the canvas to an `NSImage` (used by the share sheet, CS-008).
    static func renderNSImage(_ config: SnapshotConfig, scale: CGFloat = 2) -> NSImage? {
        guard let cgImage = renderCGImage(config, scale: scale) else { return nil }
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

    /// Renders the canvas to single-page PDF data.
    static func pdfData(_ config: SnapshotConfig) -> Data? {
        let renderer = ImageRenderer(content: SnapshotCanvas(config: config))
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

    /// Renders and writes a PNG to the general pasteboard. Returns success.
    @discardableResult
    static func copyToPasteboard(_ config: SnapshotConfig, scale: CGFloat = 2) -> Bool {
        guard let cgImage = renderCGImage(config, scale: scale),
            let png = pngData(from: cgImage)
        else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(png, forType: .png)
    }

    /// Presents an `NSSavePanel` and writes the image as PNG or PDF.
    static func saveToFile(
        _ config: SnapshotConfig, scale: CGFloat = 2, format: ExportFormat = .png
    ) {
        let payload: (data: Data, type: UTType, ext: String)? =
            switch format {
            case .png:
                renderCGImage(config, scale: scale).flatMap(pngData(from:))
                    .map { ($0, .png, "png") }
            case .pdf: pdfData(config).map { ($0, .pdf, "pdf") }
            }
        guard let payload else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [payload.type]
        panel.nameFieldStringValue = "vitrine.\(payload.ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? payload.data.write(to: url)
    }
}
