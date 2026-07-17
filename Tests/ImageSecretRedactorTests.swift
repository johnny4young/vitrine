import CoreGraphics
import Testing

@testable import Vitrine

/// Redacting secrets in a beautified image (analysis §10.4): OCR regions → cover the
/// pixels of the ones `SecretScanner` flags. The geometry (Vision box → image pixel
/// rect), the filtering, and the destructive cover are pinned here without Vision.
@Suite("Image secret redactor")
struct ImageSecretRedactorTests {
    private func line(_ text: String, _ box: CGRect) -> ImageSecretRedactor.RecognizedLine {
        ImageSecretRedactor.RecognizedLine(text: text, boundingBox: box)
    }

    private let imageSize = CGSize(width: 1000, height: 500)

    // MARK: - Box conversion (Vision bottom-left normalized → image top-left pixels)

    @Test func visionBoxFlipsYAndScalesToPixels() {
        // A box in the upper-left of the image: Vision minY high (near the top).
        let vision = CGRect(x: 0.2, y: 0.7, width: 0.3, height: 0.1)  // maxY = 0.8
        let rect = ImageSecretRedactor.pixelRect(for: vision, imageSize: imageSize)
        // X scales straight: 0.2·1000 … 0.5·1000, plus the height-fraction padding.
        let pad = 0.1 * 0.25  // height 0.1 × paddingFraction 0.25 = 0.025 normalized
        #expect(abs(rect.minX - (0.2 - pad) * 1000) < 0.01)
        #expect(abs(rect.maxX - (0.5 + pad) * 1000) < 0.01)
        // Top edge from Vision maxY (0.8) flipped: (1 - (0.8 + pad))·500.
        #expect(abs(rect.minY - (1 - (0.8 + pad)) * 500) < 0.01)
    }

    @Test func rectIsClampedToTheImageBounds() {
        // A box flush against the top edge: padding must not push it off-image.
        let edge = CGRect(x: 0, y: 0.95, width: 1, height: 0.05)  // maxY = 1
        let rect = ImageSecretRedactor.pixelRect(for: edge, imageSize: imageSize)
        #expect(rect.minX >= 0)
        #expect(rect.minY >= 0)
        #expect(rect.maxX <= imageSize.width)
        #expect(rect.maxY <= imageSize.height)
    }

    @Test func aDegenerateImageSizeYieldsNoRects() {
        let lines = [line("AKIAIOSFODNN7EXAMPLE", CGRect(x: 0.1, y: 0.5, width: 0.6, height: 0.05))]
        #expect(ImageSecretRedactor.secretPixelRects(imageSize: .zero, for: lines).isEmpty)
    }

    // MARK: - Secret filtering

    @Test func onlySecretBearingRegionsAreCovered() {
        let lines = [
            line("let count = 0", CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.05)),
            line("AKIAIOSFODNN7EXAMPLE", CGRect(x: 0.1, y: 0.6, width: 0.6, height: 0.05)),
            line("print(count)", CGRect(x: 0.1, y: 0.4, width: 0.4, height: 0.05)),
        ]
        let rects = ImageSecretRedactor.secretPixelRects(imageSize: imageSize, for: lines)
        #expect(rects.count == 1, "only the AWS key line is a secret")
        // The cover sits on the key's row: Vision y 0.6–0.65 → image y ≈ 0.35–0.4 · 500.
        #expect(rects[0].midY > 150 && rects[0].midY < 210)
    }

    @Test func aCleanImageProducesNoCovers() {
        let lines = [
            line("func greet() {", CGRect(x: 0.1, y: 0.8, width: 0.4, height: 0.05)),
            line("  print(\"hi\")", CGRect(x: 0.1, y: 0.7, width: 0.4, height: 0.05)),
        ]
        #expect(ImageSecretRedactor.secretPixelRects(imageSize: imageSize, for: lines).isEmpty)
    }

    /// The regions are read top-to-bottom before scanning, so SecretScanner's multi-line
    /// PEM handling works even when Vision returns the boxes shuffled: the BEGIN banner
    /// and the key body all get covered, not just the banner.
    @Test func multilinePrivateKeyCoversEveryRegionInReadingOrder() {
        let lines = [
            line("-----END PRIVATE KEY-----", CGRect(x: 0.1, y: 0.3, width: 0.6, height: 0.05)),
            line("MIIBVgIBADANBgkqhkiG9w0BAQEF", CGRect(x: 0.1, y: 0.4, width: 0.6, height: 0.05)),
            line("-----BEGIN PRIVATE KEY-----", CGRect(x: 0.1, y: 0.5, width: 0.6, height: 0.05)),
        ]
        let rects = ImageSecretRedactor.secretPixelRects(imageSize: imageSize, for: lines)
        #expect(rects.count == 3, "the banner, the body, and the closing line all covered")
    }

    // MARK: - Destructive cover

    @Test func redactingActuallyChangesTheCoveredPixels() throws {
        // A white image; cover a central rect and confirm those pixels went dark while
        // the rest stayed white — i.e. the secret is gone from the bytes.
        let width = 40
        let height = 20
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let white = try #require(context.makeImage())

        let cover = CGRect(x: 10, y: 5, width: 20, height: 10)  // top-left coords
        let redacted = try #require(
            ImageSecretRedactor.redacted(white, coveringPixelRects: [cover]))
        #expect(redacted.width == width && redacted.height == height)

        // Sample the center of the cover (dark) and a corner (still white).
        #expect(isDark(redacted, x: 20, y: 10), "the covered region must be opaque and dark")
        #expect(!isDark(redacted, x: 2, y: 2), "pixels outside the cover stay untouched")
    }

    @Test func redactingWithNoRectsReturnsTheOriginal() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        #expect(ImageSecretRedactor.redacted(image, coveringPixelRects: []) === image)
    }

    /// Reads a pixel and reports whether it is dark (the redaction cover), tolerant of
    /// the exact cover color.
    private func isDark(_ image: CGImage, x: Int, y: Int) -> Bool {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // CGContext is bottom-left; the caller passes top-left, so flip the row.
        let row = image.height - 1 - y
        let offset = row * bytesPerRow + x * 4
        return pixels[offset] < 80 && pixels[offset + 1] < 80 && pixels[offset + 2] < 80
    }
}
