import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Comparison board export")
struct ComparisonBoardExportTests {
    @Test(arguments: ExportFormat.allCases)
    func eachFormatKeepsItsContainerAtTheDraftExportScale(_ format: ExportFormat) throws {
        let draft = try ComparisonBoardDraft(
            captures: [capture("before"), capture("after")],
            baseConfig: SnapshotConfig(),
            profile: .sRGB,
            renderScale: 2,
            render: { _, _, _ in solidImage() })

        guard format.isEncodingAvailable else {
            #expect(throws: RenderBudgetError.encodingFailed) {
                try ComparisonBoardExporter.encodedPayloadChecked(
                    for: draft, format: format, profile: .sRGB)
            }
            return
        }

        let expected = try draft.compose(scale: draft.exportScale, profile: .sRGB)
        let payload = try ComparisonBoardExporter.encodedPayloadChecked(
            for: draft, format: format, profile: .sRGB)
        let identifiers: [ExportFormat: String] = [
            .png: "public.png", .pdf: "com.adobe.pdf",
            .heic: "public.heic", .avif: "public.avif",
        ]
        #expect(payload.ext == format.fileExtension)
        #expect(payload.type.identifier == identifiers[format])
        if format == .pdf {
            let provider = try #require(CGDataProvider(data: payload.data as CFData))
            let document = try #require(CGPDFDocument(provider))
            let page = try #require(document.page(at: 1))
            let mediaBox = page.getBoxRect(.mediaBox)
            #expect(document.numberOfPages == 1)
            // The PDF page is in points, so the 2× export keeps the 1× page size.
            #expect(mediaBox.width == CGFloat(expected.pixelWidth) / draft.exportScale)
            #expect(mediaBox.height == CGFloat(expected.pixelHeight) / draft.exportScale)
        } else {
            let source = try #require(CGImageSourceCreateWithData(payload.data as CFData, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(CGImageSourceGetType(source) as String? == identifiers[format])
            #expect(decoded.width == expected.pixelWidth)
            #expect(decoded.height == expected.pixelHeight)
        }
    }

    @Test func invalidDraftFailsBeforeEncoding() throws {
        let draft = try ComparisonBoardDraft(
            captures: [capture("before"), capture("after")],
            baseConfig: SnapshotConfig(), profile: .sRGB,
            render: { _, _, _ in solidImage() })
        draft.items[0].label = " "

        #expect(throws: RenderBudgetError.self) {
            try ComparisonBoardExporter.encodedPayloadChecked(
                for: draft, format: .png, profile: .sRGB)
        }
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
