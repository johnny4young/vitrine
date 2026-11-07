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

    private static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { textField(in: $0) }.first
    }

    // MARK: - Pages

    @Test func captionsFollowTheLineThatOpensTheirSlide() {
        let code = code(lines: 12)
        let extras = CarouselExtras(captions: [5: "Second", 9: "Third", 3: "  "])
        let byFour = CarouselSplit(linesPerSlide: 4, prefersBlankLineBreaks: false).slides(of: code)
        #expect(byFour.map(\.firstLine) == [1, 5, 9])
        #expect(byFour.map { extras.caption(for: $0) } == [nil, "Second", "Third"])
        #expect(extras.hiddenCaptionCount(byFour) == 0)
        #expect(extras.missingTextCount(byFour) == 1)
        #expect(extras.lacksText(.slide(0), slides: byFour))
        #expect(!CarouselExtras().lacksText(.slide(0), slides: byFour))

        // Another split keeps each caption on its line, and says which ones no slide shows.
        let bySix = CarouselSplit(linesPerSlide: 6, prefersBlankLineBreaks: false).slides(of: code)
        #expect(bySix.map(\.firstLine) == [1, 7])
        #expect(!extras.hasCaptions(bySix))
        #expect(extras.hiddenCaptionCount(bySix) == 2)
        let byTwo = CarouselSplit(linesPerSlide: 2, prefersBlankLineBreaks: false).slides(of: code)
        #expect(byTwo.compactMap { extras.caption(for: $0) } == ["Second", "Third"])
        #expect(extras.hiddenCaptionCount(byTwo) == 0)
    }

    @Test func aReplacedDocumentStartsWithoutCaptions() {
        let model = CarouselSplitModel()
        model.adoptDocument(generation: 1)
        model.extras.captions = [1: "Kept"]
        model.extras.coverTitle = "Title"
        model.adoptDocument(generation: 1)
        #expect(model.extras.captions == [1: "Kept"])
        // A refresh of the watched file is the same document.
        model.carryCaptions(from: 1, to: 2)
        model.adoptDocument(generation: 2)
        #expect(model.extras.captions == [1: "Kept"])
        model.carryCaptions(from: 7, to: 8)
        model.adoptDocument(generation: 3)
        #expect(model.extras.captions.isEmpty)
        #expect(model.extras.coverTitle == "Title")
    }

    @Test func coverAndClosingCardFrameTheSlides() {
        let slides = CarouselSplit(linesPerSlide: 2).slides(of: code(lines: 6))
        var extras = CarouselExtras(showsCover: true, showsOutro: true)
        #expect(extras.pageCount(slideCount: 3, tiles: true) == 5)
        #expect(extras.pageCount(slideCount: 0, tiles: true) == 0)
        #expect(
            extras.pages(slideCount: 3, tiles: true)
                == [.cover, .slide(0), .slide(1), .slide(2), .outro])
        #expect(extras.missingTextCount(slides) == 2)
        extras.setText("Title", of: .cover, slides: slides)
        extras.setText("Follow", of: .outro, slides: slides)
        extras.setText("Caption", of: .slide(1), slides: slides)
        #expect(extras.text(of: .cover, slides: slides) == "Title")
        #expect(extras.text(of: .outro, slides: slides) == "Follow")
        #expect(extras.captions == [3: "Caption"])
        #expect(extras.missingTextCount(slides) == 2)
        #expect(extras.pages(slideCount: 3) == [.cover, .slide(0), .slide(1), .slide(2), .outro])
        extras.setText("", of: .slide(1), slides: slides)
        #expect(extras.captions.isEmpty)
    }

    @Test func anEmptyCardIsATileButNotAFile() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var base = SnapshotConfig()
        base.code = code(lines: 6)
        let slides = CarouselSplit(linesPerSlide: 3).slides(of: base.code)
        let extras = CarouselExtras(
            showsCover: true, coverTitle: "  ", showsOutro: true, callToAction: "Follow")
        #expect(extras.pages(slideCount: 2) == [.slide(0), .slide(1), .outro])
        #expect(extras.pages(slideCount: 2, tiles: true).first == .cover)
        #expect(extras.lacksText(.cover, slides: slides))
        #expect(
            CarouselPaginator.requestedFilenames(
                slideCount: extras.pageCount(slideCount: slides.count), output: .pngSet)
                == ["carousel-01.png", "carousel-02.png", "carousel-03.png"])

        let result = await ExportManager.exportCarousel(
            base, slides: slides, fit: CarouselFit(fontSize: 24), output: .pdf, extras: extras,
            to: dir)
        #expect(result.written == 1)
        let document = try #require(
            PDFDocument(url: dir.appendingPathComponent(CarouselPaginator.pdfFilename)))
        #expect(document.pageCount == 3)
        #expect(document.page(at: 0)?.string?.contains("v1") == true)
        #expect(document.page(at: 2)?.string?.contains("Follow") == true)
    }

    @Test func textIsOneLineOfAtMostTheLimit() {
        let long = String(repeating: "a", count: 200)
        #expect(CarouselExtras.limited(long).count == CarouselExtras.textLimit)
        #expect(CarouselExtras.limited("a\nb\r\nc\rd\u{2028}e\u{85}f") == "a b c d e f")
    }

    @Test func pastingPastTheLimitLeavesTheClampedTextInTheField() async throws {
        final class Box {
            var text = ""
        }
        let box = Box()
        let host = NSHostingView(
            rootView: CarouselTextField(
                title: "Caption", text: Binding(get: { box.text }, set: { box.text = $0 })))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 60), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let field = try #require(Self.textField(in: host))
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText(
            String(repeating: "a", count: 130), replacementRange: editor.selectedRange())
        for _ in 0..<100 where editor.string.count != CarouselExtras.textLimit {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(box.text.count == CarouselExtras.textLimit)
        #expect(editor.string.count == CarouselExtras.textLimit)
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
        var snapshotPages: [Data] = []
        for (index, config) in configs.enumerated() {
            let written = try Data(
                contentsOf: dir.appendingPathComponent(
                    CarouselPaginator.outputFilename(forSlideAt: index)))
            let snapshot = try #require(
                ExportManager.renderCGImage(
                    config, scale: 1, fixedSize: CarouselSlideSize.linkedIn.pixels))
            #expect(written == pngBytes(snapshot))
            // The page a single-capture PDF export draws for the same config.
            let single = try #require(
                ExportManager.pdfData(config, fixedSize: CarouselSlideSize.linkedIn.pixels))
            snapshotPages += try pageImages(single)
        }
        let pdf = try Data(contentsOf: dir.appendingPathComponent(CarouselPaginator.pdfFilename))
        #expect(try pageImages(pdf) == snapshotPages)
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

    @Test func oneCaptionKeepsTheCardInPlaceOnEverySlide() throws {
        var base = SnapshotConfig()
        base.code = code(lines: 8)
        base.background = .transparent
        base.showShadow = false
        let slides = CarouselSplit(linesPerSlide: 4).slides(of: base.code)
        let extras = CarouselExtras(captions: [1: "Only the first slide has one."])
        let pages = CarouselPaginator.pages(
            base, slides: slides, cues: .none, fontSize: 30, extras: extras)
        guard case .slide(_, let second) = pages[1] else {
            Issue.record("Two slides expected")
            return
        }
        #expect(second == "")
        let height = Int(CarouselSlideSize.linkedIn.pixels.height)
        let band = Int(CarouselPage.captionBandHeight(for: CarouselSlideSize.linkedIn.pixels))
        let cards = try pages.map { page in
            let image = try ExportManager.renderCGImageChecked(
                page, fixedSize: CarouselSlideSize.linkedIn.pixels)
            let rows = try opaqueRows(image).filter { $0 < height - band }
            return [rows.min() ?? -1, rows.max() ?? -1]
        }
        #expect(cards[0] == cards[1])
        #expect(cards[0][0] >= 0)
    }

    @Test func captionedSlidesAndCardsAreWrittenInOrder() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var base = SnapshotConfig()
        base.code = code(lines: 6)
        let slides = CarouselSplit(linesPerSlide: 3).slides(of: base.code)
        let extras = CarouselExtras(
            captions: [4: "Second slide"], showsCover: true, coverTitle: "CoverTitle",
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
                pages: pages, fixedSize: ExportManager.carouselSlideSize, rasterized: true))
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
                extras: CarouselExtras(
                    showsCover: true, coverTitle: "C", showsOutro: true, callToAction: "F")))
        #expect(framed == plain * 2)
        let empty = try #require(
            await ExportManager.estimatedCarouselBytes(
                base, slides: slides, cues: .none, fit: fit,
                extras: CarouselExtras(showsCover: true, showsOutro: true)))
        #expect(empty == plain)
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
            captions: [1: "First"], showsCover: true, coverTitle: "Cover", showsOutro: true)
        let input = CarouselFilmstripModel.Input(
            base: base, slides: slides, cues: .none, fontSize: 20, profile: .sRGB,
            extras: extras)
        #expect(input.tileCount == 4)
        #expect(input.tile(at: 3) == .outro)
        model.visible = [0, 1, 2, 3, 9]
        await model.refresh(input)
        #expect(
            log.items
                == (0..<4).map {
                    CarouselPaginator.page(
                        input.tile(at: $0), base, slides: slides, cues: .none, fontSize: 20,
                        extras: extras, banded: true)
                })
        guard case .slide(_, let caption) = log.items[1] else {
            Issue.record("The first slide follows the cover")
            return
        }
        #expect(caption == "First")
    }
}
