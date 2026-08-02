import CoreGraphics
import ImageIO
import Testing

@testable import Vitrine

@MainActor
@Suite("Comparison board export")
struct ComparisonBoardExportTests {
    @Test func rasterAndPDFUseTheDraftExportScale() throws {
        let draft = try ComparisonBoardDraft(
            captures: [capture("before"), capture("after")],
            baseConfig: SnapshotConfig(),
            profile: .sRGB,
            renderScale: 2,
            render: { _, _, _ in solidImage() })
        let expected = try draft.compose(scale: draft.exportScale, profile: .sRGB)

        let png = try #require(
            ComparisonBoardExporter.encodedPayload(
                for: draft, format: .png, profile: .sRGB))
        let pngSource = try #require(CGImageSourceCreateWithData(png.data as CFData, nil))
        let pngImage = try #require(CGImageSourceCreateImageAtIndex(pngSource, 0, nil))

        let pdf = try #require(
            ComparisonBoardExporter.encodedPayload(
                for: draft, format: .pdf, profile: .sRGB))
        let provider = try #require(CGDataProvider(data: pdf.data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let mediaBox = page.getBoxRect(.mediaBox)

        #expect(pngImage.width == expected.pixelWidth)
        #expect(pngImage.height == expected.pixelHeight)
        #expect(Int(mediaBox.width) == expected.pixelWidth)
        #expect(Int(mediaBox.height) == expected.pixelHeight)
    }

    private func capture(_ code: String) -> Capture {
        Capture(code: code, languageID: "swift", themeID: "one-dark")
    }

    private func solidImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 320,
            height: 180,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        return context.makeImage()!
    }
}
