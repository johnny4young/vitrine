import AppKit
import PDFKit
import SwiftUI
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@Suite("Carousel captions, cover and closing slides")
@MainActor
struct CarouselCaptionsTests {
    private final class Log<Item> {
        var items: [Item] = []
    }

    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineCaptions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func code(lines: Int) -> String {
        (1...lines).map { "let v\($0) = \($0)" }.joined(separator: "\n")
    }

    /// Rows that hold any visible pixel, top to bottom in image space.
    private func opaqueRows(_ image: CGImage) throws -> [Int] {
        let (width, height) = (image.width, image.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(
            CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The bitmap's first row is the image's top row.
        return (0..<height).filter { y in
            (0..<width).contains { pixels[(y * width + $0) * 4 + 3] > 16 }
        }
    }

    private func pngBytes(_ image: CGImage) -> Data? {
        ExportManager.rasterData(from: image, format: .png)
    }

    /// Each page of a PDF drawn to a bitmap, so files differing only in metadata compare equal.
    private func pageImages(_ data: Data) throws -> [Data] {
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        return try (1...document.numberOfPages).map { number in
            let page = try #require(document.page(at: number))
            let box = page.getBoxRect(.mediaBox)
            let context = try #require(
                CGContext(
                    data: nil, width: Int(box.width), height: Int(box.height),
                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.drawPDFPage(page)
            return try #require(context.makeImage().flatMap(pngBytes))
        }
    }

    // MARK: - Pages

    @Test func captionsStayWithTheirSlideIndex() {
        var extras = CarouselExtras()
        extras.captions = [0: "First", 3: "  ", 5: "Orphan"]
        #expect(extras.caption(at: 0) == "First")
        #expect(extras.caption(at: 3) == nil)
        // A caption past the last slide is kept for when the slide comes back, never drawn.
        #expect(extras.hasCaptions(slideCount: 4))
        #expect(!CarouselExtras(captions: [5: "Orphan"]).hasCaptions(slideCount: 4))
        #expect(CarouselExtras(captions: [5: "Orphan"]).hasCaptions(slideCount: 6))
        #expect(extras.missingTextCount(slideCount: 4) == 3)
        #expect(extras.lacksText(.slide(1), slideCount: 4))
        #expect(!CarouselExtras().lacksText(.slide(1), slideCount: 4))
    }

    @Test func coverAndClosingCardFrameTheSlides() {
        var extras = CarouselExtras(showsCover: true, showsOutro: true)
        #expect(extras.pageCount(slideCount: 3) == 5)
        #expect(extras.pageCount(slideCount: 0) == 0)
        #expect(
            (0..<5).map { extras.page(at: $0, slideCount: 3) }
                == [.cover, .slide(0), .slide(1), .slide(2), .outro])
        #expect(extras.pageIndex(ofSlide: 2) == 3)
        #expect(extras.missingTextCount(slideCount: 3) == 2)
        extras.setText("Title", of: .cover)
        extras.setText("Follow", of: .outro)
        extras.setText("Caption", of: .slide(1))
        #expect(extras.text(of: .cover) == "Title")
        #expect(extras.text(of: .outro) == "Follow")
        #expect(extras.caption(at: 1) == "Caption")
        #expect(extras.missingTextCount(slideCount: 3) == 2)
        extras.setText("", of: .slide(1))
        #expect(extras.captions[1] == nil)
    }

    @Test func textIsOneLineOfAtMostTheLimit() {
        let long = String(repeating: "a", count: 200)
        #expect(CarouselExtras.limited(long).count == CarouselExtras.textLimit)
        #expect(CarouselExtras.limited("one\ntwo") == "one two")
    }

    @Test func cardsUseTheCaptureLookAndTheHandle() throws {
        var base = SnapshotConfig()
        base.code = code(lines: 4)
        base.theme = .dracula
        base.background = .solid(RGBAColor(red: 1, green: 1, blue: 1, opacity: 1))
        let slides = CarouselSplit(linesPerSlide: 4).slides(of: base.code)
        let extras = CarouselExtras(
            showsCover: true, coverTitle: "Hooks", showsOutro: true, callToAction: "Follow",
            handle: "@jane")
        let pages = CarouselPaginator.pages(
            base, slides: slides, cues: .none, fontSize: 20, extras: extras)
        #expect(pages.count == 3)
        guard case .card(let cover) = pages[0], case .card(let outro) = pages[2] else {
            Issue.record("Cover and closing card expected around the slide")
            return
        }
        #expect(cover.title == "Hooks")
        #expect(outro.title == "Follow")
        #expect(cover.author == "@jane")
        #expect(cover.template == .headline)
        #expect(cover.theme == base.theme)
        #expect(cover.background == base.background)
    }

    // MARK: - Unchanged without captions

    @Test func noCaptionsKeepsEverySlideAndPageAsBefore() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var base = SnapshotConfig()
        base.code = code(lines: 6)
        let slides = CarouselSplit(linesPerSlide: 3).slides(of: base.code)
        let fit = CarouselFit(fontSize: 30)
        let result = await ExportManager.exportCarousel(
            base, slides: slides, fit: fit, output: .both, to: dir)
        #expect(result.written == 3)
        let configs = slides.indices.map {
            CarouselPaginator.slideConfig(
                base, slide: slides[$0], at: $0, of: slides.count, cues: .none, fontSize: 30)
        }
        for (index, config) in configs.enumerated() {
            let written = try Data(
                contentsOf: dir.appendingPathComponent(
                    CarouselPaginator.outputFilename(forSlideAt: index)))
            let snapshot = try #require(
                ExportManager.renderCGImage(
                    config, scale: 1, fixedSize: CarouselSlideSize.linkedIn.pixels))
            #expect(written == pngBytes(snapshot))
        }
        let pdf = try Data(contentsOf: dir.appendingPathComponent(CarouselPaginator.pdfFilename))
        let direct = try #require(
            await ExportManager.pdfData(
                pages: configs, fixedSize: CarouselSlideSize.linkedIn.pixels))
        #expect(try pageImages(pdf) == pageImages(direct))
    }

    // MARK: - Caption band

    @Test func theCaptionBandFitsUnderTheCardOnEverySize() throws {
        var base = SnapshotConfig()
        base.code = code(lines: 12)
        base.background = .transparent
        base.showShadow = false
        let slides = CarouselSplit(linesPerSlide: 12).slides(of: base.code)
        let wide = String(repeating: "界", count: CarouselExtras.textLimit)
        for size in CarouselSlideSize.allCases {
            let fit = CarouselPaginator.fit(
                base, slides: slides, cues: .none, size: size, reservesCaptionBand: true)
            let plain = CarouselPaginator.fit(base, slides: slides, cues: .none, size: size)
            #expect(fit.fontSize < plain.fontSize, "\(size)")
            let config = CarouselPaginator.slideConfig(
                base, slide: slides[0], at: 0, of: 1, cues: .none, fontSize: fit.fontSize)
            let band = Int(CarouselPage.captionBandHeight(for: size.pixels))
            let height = Int(size.pixels.height)
            for caption in ["Clean up the timer.", wide] {
                let image = try ExportManager.renderCGImageChecked(
                    .slide(config, caption: caption), fixedSize: size.pixels)
                #expect(image.height == height && image.width == Int(size.pixels.width))
                let rows = try opaqueRows(image)
                let card = rows.filter { $0 < height - band }
                let text = rows.filter { $0 >= height - band }
                #expect(!card.isEmpty && !text.isEmpty, "\(size)")
                // The card ends above the band, and the caption above the frame's foot.
                #expect((card.max() ?? height) < height - band - 8, "\(size)")
                #expect((text.max() ?? height) < height - 8, "\(size)")
            }
        }
    }

    @Test func captionedSlidesAndCardsAreWrittenInOrder() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var base = SnapshotConfig()
        base.code = code(lines: 6)
        let slides = CarouselSplit(linesPerSlide: 3).slides(of: base.code)
        let extras = CarouselExtras(
            captions: [1: "Second slide"], showsCover: true, coverTitle: "CoverTitle",
            showsOutro: true, callToAction: "FollowMe", handle: "@jane")
        let progress = Log<Int>()
        let result = await ExportManager.exportCarousel(
            base, slides: slides, fit: CarouselFit(fontSize: 24), output: .both, extras: extras,
            to: dir,
            onProgress: { completed, total in
                #expect(total == 8)
                progress.items.append(completed)
            })
        #expect(result.written == 5)
        #expect(result.failed == 0)
        #expect(progress.items == Array(1...8))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == (1...4).map { String(format: "carousel-%02d.png", $0) } + ["carousel.pdf"])

        let document = try #require(
            PDFDocument(url: dir.appendingPathComponent(CarouselPaginator.pdfFilename)))
        #expect(document.pageCount == 4)
        let text = (0..<4).map { document.page(at: $0)?.string ?? "" }
        #expect(text[0].contains("CoverTitle") && text[0].contains("@jane"))
        #expect(text[1].contains("v1") && !text[1].contains("Second slide"))
        #expect(text[2].contains("v4") && text[2].contains("Second slide"))
        #expect(text[3].contains("FollowMe"))
        for index in 0..<4 {
            #expect(
                document.page(at: index)?.bounds(for: .mediaBox).size
                    == CarouselSlideSize.linkedIn.pixels)
        }
    }

    @Test func anOverflowingCarouselRastersItsCardsToo() async throws {
        var base = SnapshotConfig()
        base.code = "let tail = 1\n" + String(repeating: "hidden ", count: 80)
        let slides = CarouselSplit().slides(of: base.code)
        let pages = CarouselPaginator.pages(
            base, slides: slides, cues: .none, fontSize: 14,
            extras: CarouselExtras(showsCover: true, coverTitle: "Cover"))
        let data = try #require(
            await ExportManager.pdfData(
                carouselPages: pages, fixedSize: ExportManager.carouselSlideSize,
                rasterized: true))
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 2)
        #expect(document.string?.contains("hidden") != true)
    }

    @Test func theEstimateCountsEveryPage() async throws {
        var base = SnapshotConfig()
        base.code = code(lines: 6)
        let slides = CarouselSplit(linesPerSlide: 3).slides(of: base.code)
        let fit = CarouselFit(fontSize: 24)
        let plain = try #require(
            await ExportManager.estimatedCarouselBytes(base, slides: slides, cues: .none, fit: fit))
        let framed = try #require(
            await ExportManager.estimatedCarouselBytes(
                base, slides: slides, cues: .none, fit: fit,
                extras: CarouselExtras(showsCover: true, showsOutro: true)))
        #expect(framed == plain * 2)
    }

    // MARK: - Filmstrip

    @Test func theFilmstripDrawsTheCoverAndClosingCard() async {
        let log = Log<CarouselPage>()
        let model = CarouselFilmstripModel(quietWindow: .zero, frameGap: .zero) { page, _, _ in
            log.items.append(page)
            return nil
        }
        var base = SnapshotConfig()
        base.code = code(lines: 6)
        let slides = CarouselSplit(linesPerSlide: 3).slides(of: base.code)
        let extras = CarouselExtras(
            captions: [0: "First"], showsCover: true, coverTitle: "Cover", showsOutro: true)
        let input = CarouselFilmstripModel.Input(
            base: base, slides: slides, cues: .none, fontSize: 20, profile: .sRGB,
            extras: extras)
        #expect(input.pageCount == 4)
        model.visible = [0, 1, 2, 3, 9]
        await model.refresh(input)
        #expect(
            log.items
                == (0..<4).map {
                    CarouselPaginator.page(
                        at: $0, base, slides: slides, cues: .none, fontSize: 20, extras: extras)
                })
        guard case .slide(_, let caption) = log.items[1] else {
            Issue.record("The first slide follows the cover")
            return
        }
        #expect(caption == "First")
    }
}
