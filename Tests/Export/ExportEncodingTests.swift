import CoreGraphics
import ImageIO
import Testing

@testable import Vitrine

/// What `ExportManager` actually writes: the encoded bytes for each format.
///
/// These cover the render-and-encode core (`renderCGImage`, `encodedPayload`, `pdfData`)
/// rather than any delivery destination — the same boundary the production facade keeps,
/// so a change to how an image is encoded is tested apart from where it is sent. Each
/// format is decoded back rather than checked by extension or length: a container that
/// cannot be read is not an export.
@MainActor
@Suite("Export · encoding")
struct ExportEncodingTests {
    @Test("HEIC export encodes the rendered image into a real HEIC container")
    func heicEncodesTheRenderedImage() throws {
        let payload = try #require(
            ExportManager.encodedPayload(
                .heic,
                png: { ExportManager.renderCGImage(ExportTestFixtures.sampleConfig(), scale: 1) },
                pdf: { nil }))
        #expect(payload.ext == "heic")
        #expect(!payload.data.isEmpty)
        // It decodes back to an image of the same pixel size as a PNG render.
        let source = try #require(CGImageSourceCreateWithData(payload.data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let reference = try #require(
            ExportManager.renderCGImage(ExportTestFixtures.sampleConfig(), scale: 1))
        #expect(decoded.width == reference.width)
        #expect(decoded.height == reference.height)
    }

    @Test("AVIF export follows the active ImageIO writer capability")
    func avifEncodesTheRenderedImage() throws {
        if !ExportFormat.avif.isEncodingAvailable {
            let image = try #require(
                ExportManager.renderCGImage(
                    ExportTestFixtures.sampleConfig { $0.background = .transparent }, scale: 1))
            #expect(ExportManager.avifData(from: image) == nil)
            return
        }
        let payload = try #require(
            ExportManager.encodedPayload(
                .avif,
                png: {
                    ExportManager.renderCGImage(
                        ExportTestFixtures.sampleConfig { $0.background = .transparent }, scale: 1)
                },
                pdf: { nil }))
        #expect(payload.ext == "avif")
        #expect(payload.type.identifier == "public.avif")
        #expect(!payload.data.isEmpty)
        let source = try #require(CGImageSourceCreateWithData(payload.data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let reference = try #require(
            ExportManager.renderCGImage(
                ExportTestFixtures.sampleConfig { $0.background = .transparent }, scale: 1))
        #expect(decoded.width == reference.width)
        #expect(decoded.height == reference.height)
        #expect(decoded.alphaInfo != .none)
    }

    @Test("PDF export is a real PDF document (%PDF magic)")
    func pdfSignature() throws {
        let pdf = try #require(ExportManager.pdfData(ExportTestFixtures.sampleConfig()))
        // "%PDF" — a genuine vector PDF, the supported full-canvas vector format.
        #expect(Array(pdf.prefix(4)) == Array("%PDF".utf8))
    }

    @Test("PDF export preserves a transparent background (no opaque matte)")
    func pdfTransparentBackgroundHasAlpha() throws {
        let pdf = try #require(
            ExportManager.pdfData(
                ExportTestFixtures.sampleConfig { $0.background = .transparent }))
        let provider = try #require(CGDataProvider(data: pdf as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)

        // Rasterize the whole page into a fully transparent bitmap. The padding
        // around the code card has a transparent background, so those regions must
        // stay clear (alpha 0); an opaque matte would force every pixel to alpha
        // 255. This is the same transparency the PNG path guarantees,
        // exercised through the supported vector format.
        let width = max(Int(box.width), 1)
        let height = max(Int(box.height), 1)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0xFF, count: bytesPerRow * height)
        let context = try #require(
            CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Start fully transparent so untouched regions report alpha 0, then draw.
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.drawPDFPage(page)

        let clearPixels = stride(from: 3, to: pixels.count, by: 4).lazy
            .filter { pixels[$0] == 0 }.count
        // A meaningful fraction of the page is the transparent background; require
        // it to be genuinely clear rather than matted onto an opaque color.
        #expect(clearPixels > 0)
    }
}
