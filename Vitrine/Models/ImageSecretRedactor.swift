import CoreGraphics

/// Redacts secrets in a beautified image (analysis §10.4 — the one axis where Xnapper
/// leads) by painting over the image's own pixels.
///
/// The code-redaction path blurs whole *lines* of a snippet; a beautified screenshot
/// has no lines, so this redacts *regions*. Crucially it operates in the **image's own
/// pixel space**, not the canvas's: the image is later composited inside padding and an
/// optional window/device frame, so a mark placed in canvas coordinates would land on
/// the wrong row. Painting the pixels directly is both correct regardless of the frame
/// and *destructive* — a solid cover cannot be un-blurred the way a soft blur sometimes
/// can, so the secret is genuinely gone from the exported bytes.
///
/// Detection reuses `SecretScanner` verbatim, including its multi-line PEM handling.
/// The geometry and filtering are pure and UI-free so they are unit-testable without
/// Vision or a render.
enum ImageSecretRedactor {
    /// One recognized text region: the string Vision read and its box in **Vision's**
    /// coordinate space — normalized `0...1`, origin **bottom-left**.
    struct RecognizedLine: Equatable {
        let text: String
        let boundingBox: CGRect
    }

    /// How much to grow each cover box, as a fraction of the region's own height, so
    /// the redaction fully hides the glyphs rather than clipping at the tight text
    /// bounds Vision returns.
    static let paddingFraction: Double = 0.25

    /// The pixel rectangles (top-left origin, in `imageSize` pixels) that must be
    /// covered to hide every recognized region `SecretScanner` flags as a secret.
    ///
    /// The regions are ordered top-to-bottom (reading order) and joined with newlines
    /// before scanning, so `SecretScanner`'s line-based detection — and its multi-line
    /// PEM-key block handling — sees the image's text exactly as it would a snippet.
    /// Each flagged Vision box (normalized, bottom-left) is flipped to a top-left pixel
    /// rect, padded by a fraction of its height, and clamped to the image bounds.
    static func secretPixelRects(imageSize: CGSize, for lines: [RecognizedLine]) -> [CGRect] {
        guard imageSize.width > 0, imageSize.height > 0 else { return [] }
        let ordered = lines.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        let fullText = ordered.map(\.text).joined(separator: "\n")
        let secretLineNumbers = Set(SecretScanner.secretLines(in: fullText))  // 1-based
        return ordered.enumerated().compactMap { index, line in
            guard secretLineNumbers.contains(index + 1) else { return nil }
            return pixelRect(for: line.boundingBox, imageSize: imageSize)
        }
    }

    /// Converts a Vision box (normalized, origin bottom-left) into a padded, clamped
    /// pixel rect (origin top-left) in an image of `imageSize`.
    static func pixelRect(for visionBox: CGRect, imageSize: CGSize) -> CGRect {
        let width = imageSize.width
        let height = imageSize.height
        let pad = visionBox.height * paddingFraction
        // Grow the box, then flip Y (Vision grows up, image rows grow down).
        let minX = (visionBox.minX - pad) * width
        let maxX = (visionBox.maxX + pad) * width
        let topY = (1 - (visionBox.maxY + pad)) * height
        let bottomY = (1 - (visionBox.minY - pad)) * height
        let rect = CGRect(x: minX, y: topY, width: maxX - minX, height: bottomY - topY)
        return rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// A copy of `cgImage` with every rect in `pixelRects` painted over with an opaque
    /// cover, or the original when there is nothing to redact. The cover is a solid
    /// dark bar — the standard, irreversible redaction — so the secret cannot be
    /// recovered from the exported image the way a soft blur sometimes can.
    static func redacted(_ cgImage: CGImage, coveringPixelRects pixelRects: [CGRect]) -> CGImage? {
        guard !pixelRects.isEmpty else { return cgImage }
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let colorSpace,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The rects are top-left; CGContext is bottom-left, so flip each one's origin.
        context.setFillColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)
        for rect in pixelRects {
            let flipped = CGRect(
                x: rect.minX, y: CGFloat(height) - rect.maxY,
                width: rect.width, height: rect.height)
            context.fill(flipped)
        }
        return context.makeImage()
    }
}
