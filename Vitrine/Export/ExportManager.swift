import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders a `SnapshotConfig` to a PNG and exports it to the clipboard or a file
/// (CS-007). PNG encoding goes through ImageIO directly from the rendered
/// `CGImage` — no `NSBitmapImageRep`/TIFF round-trip.
enum ExportManager {
    /// Renders the canvas for `config` to a `CGImage` at the given scale (1/2/3).
    static func renderCGImage(_ config: SnapshotConfig, scale: CGFloat = 2) -> CGImage? {
        let renderer = ImageRenderer(content: SnapshotCanvas(config: config))
        renderer.scale = scale
        return renderer.cgImage
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

    /// Presents an `NSSavePanel` and writes the PNG to disk.
    static func saveToFile(_ config: SnapshotConfig, scale: CGFloat = 2) {
        guard let cgImage = renderCGImage(config, scale: scale),
            let png = pngData(from: cgImage)
        else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "vitrine.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? png.write(to: url)
    }
}
