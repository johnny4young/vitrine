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

    private static let cues = CarouselPaginator.Cues(
        lineNumbers: .continuing, showsPageBadge: false, showsContinuation: true,
        continuationLabel: "continues →")

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

    /// The bounding box of non-transparent pixels, in pixels.
    private func opaqueBox(_ image: CGImage) throws -> CGRect {
        let (width, height) = (image.width, image.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(
            CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var (minX, maxX, minY, maxY) = (width, -1, height, -1)
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 16 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Every slide, framed, shows the whole card it has at its own size: nothing is cut off
    /// or re-wrapped by the frame, and the card stays clear of the edges.
    private func expectEverySlideFits(
        _ base: SnapshotConfig, linesPerSlide: Int, size: CarouselSlideSize,
        _ label: Comment
    ) throws -> CarouselFit {
        var base = base
        base.background = .transparent
        base.showShadow = false
        let slides = CarouselSplit(linesPerSlide: linesPerSlide).slides(of: base.code)
        let fit = CarouselPaginator.fit(base, slides: slides, cues: Self.cues, size: size)
        #expect(!fit.overflows, label)
        for index in slides.indices {
            let config = CarouselPaginator.slideConfig(
                base, slide: slides[index], at: index, of: slides.count, cues: Self.cues,
                fontSize: fit.fontSize)
            let framed = try opaqueBox(
                try #require(ExportManager.renderCGImage(config, scale: 1, fixedSize: size.pixels)))
            let natural = try opaqueBox(
                try #require(ExportManager.renderCGImage(config, scale: 1)))
            // A row layout may widen to the frame; a cut or re-wrapped line changes the height.
            #expect(framed.width >= natural.width - 2, label)
            #expect(abs(framed.height - natural.height) <= 2, label)
            #expect(framed.minX > 0 && framed.minY > 0, label)
            #expect(framed.maxX < size.pixels.width && framed.maxY < size.pixels.height, label)
        }
        return fit
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

    @Test func slidesWithLineNumbersAndTheCueFitEverySize() throws {
        var base = SnapshotConfig()
        base.code = code(lines: 24, width: 40)
        for size in CarouselSlideSize.allCases {
            let fit = try expectEverySlideFits(base, linesPerSlide: 12, size: size, "\(size)")
            // At this width the old floor left most of a slide empty.
            #expect(fit.fontSize > 22, "\(size)")
        }
    }

    @Test func wrappedLinesAreCountedAsRows() throws {
        var base = SnapshotConfig()
        base.code = (1...10).map {
            "let v\($0) = \"" + String(repeating: "wrap ", count: 14) + "\""
        }
        .joined(separator: "\n")
        base.wrapColumns = 30
        for size in [CarouselSlideSize.linkedIn, .x] {
            _ = try expectEverySlideFits(base, linesPerSlide: 10, size: size, "\(size)")
        }
    }

    @Test func wideCharactersAreMeasuredByTheirAdvance() throws {
        var base = SnapshotConfig()
        base.code = (1...8).map { "let 名前\($0) = \"東京都の天気予報は晴れのち曇りです 🌤️🌤️\"" }
            .joined(separator: "\n")
        for size in [CarouselSlideSize.instagram, .story] {
            _ = try expectEverySlideFits(base, linesPerSlide: 4, size: size, "\(size)")
        }
    }

    @Test func aNarrowSnippetKeepsRoomForTheContinuationCue() throws {
        var base = SnapshotConfig()
        base.code = "a\nb\nc\nd"
        _ = try expectEverySlideFits(base, linesPerSlide: 2, size: .story, "story")
    }

    /// The badge's frame is where the render changes when it is drawn; the card's is what the
    /// render holds without it.
    @Test func thePageBadgeSitsClearOfTheCardOnEverySize() throws {
        let cues = CarouselPaginator.Cues(
            lineNumbers: .continuing, showsPageBadge: true, showsContinuation: true,
            continuationLabel: "continues →")
        for (lines, width) in [(24, 40), (24, 50), (24, 60), (24, 12), (6, 30)] {
            var base = SnapshotConfig()
            base.code = code(lines: lines, width: width)
            // Little padding, so the canvas edge alone cannot keep the card off the badge.
            base.padding = 8
            base.background = .transparent
            base.showShadow = false
            let slides = CarouselSplit(linesPerSlide: min(12, lines / 2)).slides(of: base.code)
            for size in CarouselSlideSize.allCases {
                let label: Comment = "\(size) \(lines)×\(width)"
                let fit = CarouselPaginator.fit(base, slides: slides, cues: cues, size: size)
                let badged = CarouselPaginator.slideConfig(
                    base, slide: slides[0], at: 0, of: slides.count, cues: cues,
                    fontSize: fit.fontSize)
                var plain = badged
                plain.slideCue?.pageLabel = nil
                let withBadge = try #require(
                    ExportManager.renderCGImage(badged, scale: 1, fixedSize: size.pixels))
                let withoutBadge = try #require(
                    ExportManager.renderCGImage(plain, scale: 1, fixedSize: size.pixels))
                let card = try opaqueBox(withoutBadge)
                let badge = try changedBox(withBadge, withoutBadge)
                #expect(!badge.isEmpty, label)
                #expect(!badge.intersects(card), label)
            }
        }
    }

    /// The bounding box of pixels that differ between two renders of one size.
    private func changedBox(_ lhs: CGImage, _ rhs: CGImage) throws -> CGRect {
        func pixels(_ image: CGImage) throws -> [UInt8] {
            var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try #require(
                CGContext(
                    data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return buffer
        }
        let (a, b) = (try pixels(lhs), try pixels(rhs))
        let width = lhs.width
        var (minX, maxX, minY, maxY) = (width, -1, lhs.height, -1)
        for index in stride(from: 0, to: a.count, by: 4)
        where a[index] != b[index] || a[index + 1] != b[index + 1]
            || a[index + 2] != b[index + 2] || a[index + 3] != b[index + 3]
        {
            let (x, y) = ((index / 4) % width, (index / 4) / width)
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
        guard maxX >= 0 else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @Test func shortSlidesSizeTheirTypeForEightRows() {
        var short = SnapshotConfig()
        short.code = code(lines: 2, width: 10)
        var eight = SnapshotConfig()
        eight.code = code(lines: 8, width: 10)
        func fitted(_ config: SnapshotConfig) -> Double {
            CarouselPaginator.fit(
                config, slides: CarouselSplit().slides(of: config.code), cues: .none,
                size: .instagram
            ).fontSize
        }
        #expect(fitted(short) == fitted(eight))
    }

    @Test func aLineTooWideForTheFloorIsReported() {
        var base = SnapshotConfig()
        base.code = code(lines: 4, width: 20)
        let slides = CarouselSplit().slides(of: base.code)
        #expect(
            !CarouselPaginator.fit(base, slides: slides, cues: .none, size: .linkedIn).overflows)
        base.code += "\n" + String(repeating: "w", count: 400)
        let wide = CarouselPaginator.fit(
            base, slides: CarouselSplit().slides(of: base.code), cues: .none, size: .linkedIn)
        #expect(
            wide == CarouselFit(fontSize: ExportManager.carouselMinimumFontSize, overflows: true))
        #expect(
            CarouselPaginator.fit(base, slides: [], cues: .none, size: .linkedIn)
                == CarouselFit(fontSize: ExportManager.carouselMinimumFontSize))
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

    @Test func anOverflowingCarouselLeavesNoHiddenTextInThePDF() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var base = SnapshotConfig()
        base.code = "let tail = 1\n" + String(repeating: "hidden ", count: 80)
        let slides = CarouselSplit().slides(of: base.code)
        #expect(
            await ExportManager.exportCarousel(base, slides: slides, output: .pdf, to: dir)
                .written == 1)
        let document = try #require(
            PDFDocument(url: dir.appendingPathComponent(CarouselPaginator.pdfFilename)))
        #expect(document.pageCount == 1)
        #expect(document.string?.contains("hidden") != true)
    }

    @Test func pdfPagesReportProgressAndStopWhenCancelled() async {
        let configs = [SnapshotConfig(), SnapshotConfig(), SnapshotConfig()]
        let pages = Log<Int>()
        let data = await ExportManager.pdfData(
            pages: configs, fixedSize: ExportManager.carouselSlideSize,
            onPage: { pages.items.append($0) })
        #expect(data != nil)
        #expect(pages.items == [1, 2, 3])
        #expect(
            await ExportManager.pdfData(pages: [], fixedSize: ExportManager.carouselSlideSize)
                == nil)

        let task = Task {
            await ExportManager.pdfData(pages: configs, fixedSize: ExportManager.carouselSlideSize)
        }
        task.cancel()
        #expect(await task.value == nil)
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
                #expect(total == 4)
                progress.items.append(completed)
            })
        #expect(result.written == 3)
        // PDF pages first, then the PNGs as their writes land.
        #expect(progress.items == [1, 2, 3, 4])
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
    }

    @Test func theEstimateCoversEachOutput() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var base = SnapshotConfig()
        base.code = code(lines: 40, width: 30)
        let slides = CarouselSplit(linesPerSlide: 10).slides(of: base.code)
        let fit = CarouselFit(fontSize: 30)
        #expect(
            await ExportManager.exportCarousel(
                base, slides: slides, fit: fit, output: .pdf, to: dir
            ).written == 1)
        let written = try Data(contentsOf: dir.appendingPathComponent("carousel.pdf")).count
        let pdf = try #require(
            await ExportManager.estimatedCarouselBytes(
                base, slides: slides, cues: .none, fit: fit, output: .pdf))
        #expect(abs(pdf - written) <= written / 4, "estimate \(pdf), written \(written)")
        let png = try #require(
            await ExportManager.estimatedCarouselBytes(
                base, slides: slides, cues: .none, fit: fit, output: .pngSet))
        let both = await ExportManager.estimatedCarouselBytes(
            base, slides: slides, cues: .none, fit: fit, output: .both)
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
        #expect(ExportManager.carouselProgressUnits(slideCount: 4, output: .both) == 8)
        #expect(ExportManager.carouselProgressUnits(slideCount: 4, output: .pdf) == 4)
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

    @Test func theFilmstripWaitsForTheFitAndRendersAtTheChosenSize() async throws {
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
        var input = CarouselFilmstripModel.Input(
            base: base, slides: slides, cues: .none, size: .x, profile: .sRGB)
        model.visible = [0, 1]
        await model.refresh(input)
        #expect(sizes.items.isEmpty)

        input.fontSize = 33
        await model.refresh(input)
        #expect(sizes.items == [.x, .x])
        #expect(fonts.items == [33, 33])

        let tile = try #require(
            CarouselFilmstripModel.renderTile(
                CarouselPaginator.slideConfig(
                    base, slide: slides[0], at: 0, of: 2, cues: .none, fontSize: 33),
                size: .story, profile: .sRGB))
        #expect(abs(CGFloat(tile.height) - 2 * CarouselFilmstripModel.tileSize.height) <= 1)
    }
}
