import AppKit
import PDFKit
import SwiftUI
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@Suite("Carousel slide sizes and PDF output")
@MainActor
struct CarouselSizeAndPDFTests {
    private final class Log<Item> {
        var items: [Item] = []
    }

    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineCarousel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func code(lines: Int, width: Int = 12) -> String {
        (1...lines).map { "let v\($0) = " + String(repeating: "a", count: max(0, width - 9)) }
            .joined(separator: "\n")
    }

    private func naturalSize(_ config: SnapshotConfig) -> CGSize {
        var measured = CGSize.zero
        ImageRenderer(content: SnapshotCanvas(config: config)).render { size, _ in
            measured = size
        }
        return measured
    }

    // MARK: - Sizes

    @Test func everySizeHasItsPlatformFrame() {
        #expect(CarouselSlideSize.linkedIn.pixels == CGSize(width: 1080, height: 1350))
        #expect(CarouselSlideSize.instagram.pixels == CGSize(width: 1080, height: 1080))
        #expect(CarouselSlideSize.x.pixels == CGSize(width: 1920, height: 1080))
        #expect(CarouselSlideSize.story.pixels == CGSize(width: 1080, height: 1920))
        #expect(ExportManager.carouselSlideSize == CarouselSlideSize.linkedIn.pixels)
    }

    @Test func slidesAreWrittenAtTheChosenFrame() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var base = SnapshotConfig()
        base.code = code(lines: 6)
        let slides = CarouselSplit(linesPerSlide: 4).slides(of: base.code)
        let result = await ExportManager.exportCarousel(base, slides: slides, size: .x, to: dir)
        #expect(result.written == 2)
        let image = try #require(
            GoldenComparator.loadImage(at: dir.appendingPathComponent("carousel-01.png")))
        #expect(image.width == 1920)
        #expect(image.height == 1080)
    }

    // MARK: - Fitted type

    @Test func theFittedCardFillsTheFrameWithoutOverflowing() {
        for size in CarouselSlideSize.allCases {
            for (lines, width) in [(3, 12), (12, 40), (20, 70)] {
                var base = SnapshotConfig()
                base.code = code(lines: lines, width: width)
                let slides = CarouselSplit(linesPerSlide: 30).slides(of: base.code)
                let fontSize = CarouselPaginator.fittedFontSize(
                    base, slides: slides, cues: .none, size: size)
                #expect(fontSize > ExportManager.carouselMinimumFontSize)
                let frame = size.pixels
                let margin = 2 * CarouselPaginator.fittedMargin * min(frame.width, frame.height)
                func card(_ fontSize: Double) -> CGSize {
                    naturalSize(
                        CarouselPaginator.slideConfig(
                            base, slide: slides[0], at: 0, of: 1, cues: .none,
                            fontSize: fontSize))
                }
                let fitted = card(fontSize)
                #expect(fitted.width <= frame.width - margin + 1, "\(size) \(lines)×\(width)")
                #expect(fitted.height <= frame.height - margin + 1, "\(size) \(lines)×\(width)")
                // A few points more would overflow one side: the type really fills the frame.
                guard lines >= CarouselPaginator.fittedMinimumRows else { continue }
                let larger = card(fontSize + 3)
                #expect(
                    larger.width > frame.width - margin || larger.height > frame.height - margin,
                    "\(size) \(lines)×\(width)")
            }
        }
    }

    @Test func shortSlidesSizeTheirTypeForEightLines() {
        var short = SnapshotConfig()
        short.code = code(lines: 2, width: 10)
        var eight = SnapshotConfig()
        eight.code = code(lines: 8, width: 10)
        func fitted(_ config: SnapshotConfig) -> Double {
            CarouselPaginator.fittedFontSize(
                config, slides: CarouselSplit().slides(of: config.code), cues: .none,
                size: .instagram)
        }
        #expect(fitted(short) == fitted(eight))
    }

    @Test func aWideLineShrinksTheTypeButNeverBelowTheFloor() {
        var base = SnapshotConfig()
        base.code = code(lines: 4, width: 20)
        let narrow = CarouselPaginator.fittedFontSize(
            base, slides: CarouselSplit().slides(of: base.code), cues: .none, size: .linkedIn)
        base.code += "\n" + String(repeating: "w", count: 400)
        let wide = CarouselPaginator.fittedFontSize(
            base, slides: CarouselSplit().slides(of: base.code), cues: .none, size: .linkedIn)
        #expect(wide < narrow)
        #expect(wide == ExportManager.carouselMinimumFontSize)
        #expect(
            CarouselPaginator.fittedFontSize(base, slides: [], cues: .none, size: .linkedIn)
                == ExportManager.carouselMinimumFontSize)
    }

    // MARK: - PDF

    @Test func pdfHoldsOnePagePerSlideAtTheFrame() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var base = SnapshotConfig()
        base.code = code(lines: 9)
        let slides = CarouselSplit(linesPerSlide: 3).slides(of: base.code)
        let result = await ExportManager.exportCarousel(
            base, slides: slides, size: .story, output: .pdf, to: dir)
        #expect(result.written == 1)
        #expect(result.failed == 0)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names == ["carousel.pdf"])
        let document = try #require(
            PDFDocument(url: dir.appendingPathComponent(CarouselPaginator.pdfFilename)))
        #expect(document.pageCount == 3)
        let page = try #require(document.page(at: 2))
        #expect(page.bounds(for: .mediaBox).size == CarouselSlideSize.story.pixels)
        #expect(document.string?.contains("v7") == true)
    }

    @Test func bothWritesTheSlidesAndThePDFWithoutReplacingEither() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let existing = dir.appendingPathComponent("carousel.pdf")
        try Data("existing".utf8).write(to: existing)
        var base = SnapshotConfig()
        base.code = code(lines: 6)
        let slides = CarouselSplit(linesPerSlide: 3).slides(of: base.code)
        let planned = CarouselPaginator.plannedFilenames(
            slideCount: slides.count, output: .both, in: dir)
        #expect(planned == ["carousel-01.png", "carousel-02.png", "carousel-2.pdf"])

        let progress = Log<Int>()
        let result = await ExportManager.exportCarousel(
            base, slides: slides, output: .both, to: dir,
            onProgress: { completed, total in
                #expect(total == 3)
                progress.items.append(completed)
            })
        #expect(result.written == 3)
        #expect(progress.items == [1, 2, 3])
        #expect(try Data(contentsOf: existing) == Data("existing".utf8))
        for name in planned {
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path))
        }
        #expect(PDFDocument(url: dir.appendingPathComponent("carousel-2.pdf"))?.pageCount == 2)
    }

    @Test func redactedLinesLeaveNoTextInThePDF() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let secret = ["hunter", "2-", "swordfish"].joined()
        var base = SnapshotConfig()
        base.code = "let a = 1\nlet s = \"\(secret)\"\nlet b = 2\nlet c = 3"
        base.redactedLineRanges = [2...2]
        let slides = CarouselSplit(linesPerSlide: 2).slides(of: base.code)
        #expect(
            await ExportManager.exportCarousel(base, slides: slides, output: .pdf, to: dir)
                .written == 1)
        let document = try #require(
            PDFDocument(url: dir.appendingPathComponent(CarouselPaginator.pdfFilename)))
        let text = try #require(document.string)
        #expect(text.contains("let c"))
        #expect(!text.contains(secret))
    }

    @Test func aFailedPDFWriteIsCounted() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let slides = [CarouselPaginator.Slide(text: "one", firstLine: 1, lineCount: 1)]
        let result = await ExportManager.exportCarousel(
            SnapshotConfig(), slides: slides, output: .both, to: dir,
            writeFile: { data, url in
                guard url.pathExtension == "png" else { throw CocoaError(.fileWriteNoPermission) }
                try data.write(to: url)
            })
        #expect(result.written == 1)
        #expect(result.failed == 1)
        #expect(ExportManager.pdfData(pages: [], fixedSize: ExportManager.carouselSlideSize) == nil)
    }

    @Test func theEstimateCoversEachOutput() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var base = SnapshotConfig()
        base.code = code(lines: 40, width: 30)
        let slides = CarouselSplit(linesPerSlide: 10).slides(of: base.code)
        #expect(
            await ExportManager.exportCarousel(base, slides: slides, output: .pdf, to: dir)
                .written == 1)
        let written = try Data(contentsOf: dir.appendingPathComponent("carousel.pdf")).count
        let pdf = try #require(
            await ExportManager.estimatedCarouselBytes(
                base, slides: slides, cues: .none, output: .pdf))
        #expect(abs(pdf - written) <= written / 4, "estimate \(pdf), written \(written)")
        let png = try #require(
            await ExportManager.estimatedCarouselBytes(
                base, slides: slides, cues: .none, output: .pngSet))
        let both = await ExportManager.estimatedCarouselBytes(
            base, slides: slides, cues: .none, output: .both)
        #expect(both == pdf + png)
    }

    // MARK: - Sheet text

    @Test func theSummaryNamesThePDFBesideTheSlides() {
        let both = CarouselPaginator.requestedFilenames(slideCount: 4, output: .both)
        #expect(
            CarouselPaginator.outputSummary(filenames: both, estimatedBytes: nil)
                == "carousel-01.png … 04.png + carousel.pdf")
        let pdf = CarouselPaginator.requestedFilenames(slideCount: 4, output: .pdf)
        #expect(
            CarouselPaginator.outputSummary(filenames: pdf, estimatedBytes: nil) == "carousel.pdf")
        #expect(
            CarouselPaginator.spokenOutputSummary(filenames: pdf, estimatedBytes: nil)
                == "carousel.pdf")
        #expect(
            CarouselPaginator.spokenOutputSummary(
                filenames: ["carousel-01.png", "carousel.pdf"], estimatedBytes: nil)
                == "carousel-01.png, carousel.pdf")
        #expect(CarouselPaginator.requestedFilenames(slideCount: 0, output: .both).isEmpty)
    }

    @Test func tilesKeepOneHeightAndTheSlideShape() {
        for size in CarouselSlideSize.allCases {
            let tile = CarouselFilmstripModel.tileSize(for: size)
            #expect(tile.height == CarouselFilmstripModel.tileSize.height)
            let ratio = size.pixels.width / size.pixels.height
            #expect(abs(tile.width / tile.height - ratio) < 0.02)
        }
        #expect(CarouselFilmstripModel.tileSize(for: .linkedIn) == CarouselFilmstripModel.tileSize)
    }

    @Test func theFilmstripRendersAtTheChosenSize() async throws {
        let sizes = Log<CarouselSlideSize>()
        let fonts = Log<Double>()
        let model = CarouselFilmstripModel(quietWindow: .zero, frameGap: .zero) { config, size, _ in
            sizes.items.append(size)
            fonts.items.append(config.fontSize)
            return nil
        }
        var base = SnapshotConfig()
        base.code = code(lines: 8)
        let slides = CarouselSplit(linesPerSlide: 4).slides(of: base.code)
        let input = CarouselFilmstripModel.Input(
            base: base, slides: slides, cues: .none, size: .x, profile: .sRGB)
        model.visible = [0, 1]
        await model.refresh(input)
        #expect(sizes.items == [.x, .x])
        let fitted = CarouselPaginator.fittedFontSize(
            base, slides: slides, cues: .none, size: .x)
        #expect(fonts.items == [fitted, fitted])
        #expect(model.fontSize(for: input) == fitted)

        let tile = try #require(
            CarouselFilmstripModel.renderTile(
                CarouselPaginator.slideConfig(
                    base, slide: slides[0], at: 0, of: 2, cues: .none, fontSize: fitted),
                size: .story, profile: .sRGB))
        #expect(abs(CGFloat(tile.height) - 2 * CarouselFilmstripModel.tileSize.height) <= 1)
    }
}
