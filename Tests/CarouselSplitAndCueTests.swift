import AppKit
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@Suite("Carousel blank-line split and continuation cues")
@MainActor
struct CarouselSplitAndCueTests {
    private static let cues = CarouselPaginator.Cues(
        lineNumbers: .continuing, showsPageBadge: true, showsContinuation: true,
        continuationLabel: "continues →")

    private func code(lines: Int, blankAt blanks: Set<Int> = []) -> String {
        (1...lines).map { blanks.contains($0) ? "" : "line \($0)" }.joined(separator: "\n")
    }

    // MARK: - Blank-line breaks

    @Test func snippetWithoutBlankLinesSplitsAsBalanced() {
        let source = code(lines: 25)
        let preferred = CarouselPaginator.slides(
            for: source, maxLinesPerSlide: 12, preferBlankLineBreaks: true)
        #expect(preferred == CarouselPaginator.slides(for: source, maxLinesPerSlide: 12))
        #expect(preferred.map(\.lineCount) == [9, 8, 8])
    }

    @Test func breakMovesToNearbyBlankLineAndDropsTheSeparator() {
        // 25 lines at 12 balance to 9 · 8 · 8; the blank at line 8 pulls the first break.
        let slides = CarouselPaginator.slides(
            for: code(lines: 25, blankAt: [8]), maxLinesPerSlide: 12,
            preferBlankLineBreaks: true)
        #expect(slides.count == 3)
        #expect(slides[0].firstLine == 1)
        #expect(slides[0].lineCount == 7)
        #expect(slides[0].text.hasSuffix("line 7"))
        #expect(slides[1].firstLine == 9)
        #expect(slides[1].text.hasPrefix("line 9"))
    }

    @Test func aRunOfBlankLinesAndWhitespaceOnlyLinesAreOneSeparator() {
        var lines = (1...24).map { "line \($0)" }
        lines[8] = "   "
        lines[9] = "\t"
        let slides = CarouselPaginator.slides(
            for: lines.joined(separator: "\n"), maxLinesPerSlide: 8,
            preferBlankLineBreaks: true)
        #expect(slides.map(\.firstLine) == [1, 11, 18])
        #expect(slides[0].lineCount == 8)
    }

    @Test func aBlankLineFarFromTheBoundaryIsNotWorthTheImbalance() {
        let source = code(lines: 24, blankAt: [2])
        let preferred = CarouselPaginator.slides(
            for: source, maxLinesPerSlide: 12, preferBlankLineBreaks: true)
        #expect(preferred == CarouselPaginator.slides(for: source, maxLinesPerSlide: 12))
    }

    @Test func aFullSplitCannotMoveItsBreaks() {
        // 24 lines at 12 leave no slack: moving the break would overflow a slide.
        let source = code(lines: 24, blankAt: [10])
        let preferred = CarouselPaginator.slides(
            for: source, maxLinesPerSlide: 12, preferBlankLineBreaks: true)
        #expect(preferred == CarouselPaginator.slides(for: source, maxLinesPerSlide: 12))
    }

    @Test func aSlideThatWouldBeAllBlankIsDropped() {
        let source = code(lines: 12, blankAt: [5, 6, 7, 8])
        for prefers in [true, false] {
            let slides = CarouselPaginator.slides(
                for: source, maxLinesPerSlide: 4, preferBlankLineBreaks: prefers)
            #expect(slides.map(\.firstLine) == [1, 9])
            #expect(slides.map(\.lineCount) == [4, 4])
        }
    }

    /// Sweeps sizes, caps and blank runs: the cap always holds, no slide is empty, the
    /// count never grows, and only blank lines may go missing between slides.
    @Test func everySplitKeepsItsCapAndContent() {
        for lineCount in stride(from: 5, through: 90, by: 5) {
            for cap in CarouselPaginator.linesPerSlideRange {
                for run in 1...6 {
                    for period in (run + 1)...(run + 6) {
                        let blanks = Set((1...lineCount).filter { $0 % period < run })
                        expectSoundSplit(
                            code(lines: lineCount, blankAt: blanks), lineCount: lineCount,
                            cap: cap, blanks: blanks)
                    }
                }
            }
        }
    }

    private func expectSoundSplit(_ source: String, lineCount: Int, cap: Int, blanks: Set<Int>) {
        let balancedCount = (lineCount + cap - 1) / cap
        for prefers in [true, false] {
            let slides = CarouselPaginator.slides(
                for: source, maxLinesPerSlide: cap, preferBlankLineBreaks: prefers)
            #expect(
                slides
                    == CarouselPaginator.slides(
                        for: source, maxLinesPerSlide: cap, preferBlankLineBreaks: prefers))
            #expect(slides.count <= balancedCount)
            #expect(slides.allSatisfy { (1...cap).contains($0.lineCount) })
            #expect(slides.allSatisfy { $0.text.contains("line") })

            var expectedLine = 1
            for slide in slides {
                #expect(Set(expectedLine..<slide.firstLine).isSubset(of: blanks))
                #expect(slide.text.components(separatedBy: "\n").count == slide.lineCount)
                expectedLine = slide.firstLine + slide.lineCount
            }
            #expect(Set(expectedLine..<(lineCount + 1)).isSubset(of: blanks))
        }
    }

    // MARK: - Slide configs

    @Test func middleSlideCarriesItsPositionAndContinuesTheNumbering() {
        let slide = CarouselPaginator.Slide(text: "a\nb", firstLine: 9, lineCount: 8)
        let config = CarouselPaginator.slideConfig(
            SnapshotConfig(), slide: slide, at: 1, of: 4, cues: Self.cues)
        #expect(config.showLineNumbers)
        #expect(config.firstLineNumber == 9)
        #expect(config.slideCue?.pageLabel == "2 / 4")
        #expect(config.slideCue?.rangeLabel == "9–16")
        #expect(config.slideCue?.continuationLabel == "continues →")
    }

    @Test func lastSlideStopsPromisingMore() {
        let slide = CarouselPaginator.Slide(text: "z", firstLine: 31, lineCount: 1)
        let config = CarouselPaginator.slideConfig(
            SnapshotConfig(), slide: slide, at: 3, of: 4, cues: Self.cues)
        #expect(config.slideCue?.pageLabel == "4 / 4")
        #expect(config.slideCue?.rangeLabel == "31")
        #expect(config.slideCue?.continuationLabel == nil)
    }

    @Test func aLoneSlideHasNoCues() {
        let slide = CarouselPaginator.Slide(text: "a", firstLine: 1, lineCount: 1)
        let config = CarouselPaginator.slideConfig(
            SnapshotConfig(), slide: slide, at: 0, of: 1, cues: Self.cues)
        #expect(config.slideCue == nil)
    }

    @Test func lineNumberChoicesOverrideTheDocument() {
        let slide = CarouselPaginator.Slide(text: "a", firstLine: 9, lineCount: 1)
        var base = SnapshotConfig()
        base.showLineNumbers = true
        func config(_ mode: CarouselPaginator.Cues.LineNumbers?) -> SnapshotConfig {
            CarouselPaginator.slideConfig(
                base, slide: slide, at: 1, of: 2, cues: .init(lineNumbers: mode))
        }
        #expect(config(nil).showLineNumbers)
        #expect(config(nil).firstLineNumber == 1)
        #expect(config(.restarting).showLineNumbers)
        #expect(config(.restarting).firstLineNumber == 1)
        #expect(!config(.off).showLineNumbers)
    }

    @Test func restartedNumbersAndTheFootRangeAgree() {
        let slide = CarouselPaginator.Slide(text: "a\nb", firstLine: 9, lineCount: 8)
        func range(_ mode: CarouselPaginator.Cues.LineNumbers?, gutter: Bool = false) -> String? {
            var base = SnapshotConfig()
            base.showLineNumbers = gutter
            let cues = CarouselPaginator.Cues(
                lineNumbers: mode, showsContinuation: true, continuationLabel: "next")
            return CarouselPaginator.slideConfig(base, slide: slide, at: 1, of: 2, cues: cues)
                .slideCue?.rangeLabel
        }
        #expect(range(.restarting) == "1–8")
        #expect(range(.continuing) == "9–16")
        #expect(range(.off) == "9–16")
        #expect(range(nil, gutter: true) == "1–8")
        #expect(range(nil, gutter: false) == "9–16")
    }

    @Test func focusModeOnlySurvivesOnSlidesWithAHighlight() {
        var base = SnapshotConfig()
        base.showLineNumbers = true
        base.focusHighlightedLines = true
        base.highlightedLineRanges = [2...2]
        let first = CarouselPaginator.Slide(text: "a\nb", firstLine: 1, lineCount: 2)
        let second = CarouselPaginator.Slide(text: "c\nd", firstLine: 3, lineCount: 2)
        func config(_ slide: CarouselPaginator.Slide, at index: Int) -> SnapshotConfig {
            CarouselPaginator.slideConfig(base, slide: slide, at: index, of: 2, cues: .none)
        }
        #expect(config(first, at: 0).focusHighlightedLines)
        #expect(!config(second, at: 1).focusHighlightedLines)
    }

    @Test func redactionFollowsItsLineAcrossABlankLineBreak() {
        let source = code(lines: 9, blankAt: [5])
        let slides = CarouselPaginator.slides(
            for: source, maxLinesPerSlide: 5, preferBlankLineBreaks: true)
        var base = SnapshotConfig()
        base.code = source
        base.redactedLineRanges = [7...7]
        let config = CarouselPaginator.slideConfig(
            base, slide: slides[1], at: 1, of: 2, cues: .none)
        #expect(config.redactedLineRanges == [2...2])
    }

    #if DEBUG
        /// Mirrors the toolbar: the dev hook must never reach a document the button refuses.
        @Test func carouselHookHonorsTheToolbarGate() {
            let arguments = ["--open-carousel-export"]
            func opens(
                _ style: SnapshotConfig, hasContent: Bool = true, unlocked: Bool = false,
                args: [String]
            ) -> Bool {
                EditorView.carouselHookOpens(
                    style, hasRenderableContent: hasContent, isUnlocked: unlocked, arguments: args)
            }
            var style = SnapshotConfig()
            #expect(opens(style, args: arguments))
            #expect(!opens(style, args: []))
            #expect(!opens(style, hasContent: false, args: arguments))
            style.annotations = [Annotation(kind: .blur, start: .zero, end: CGPoint(x: 1, y: 1))]
            #expect(!opens(style, args: arguments))
            #expect(opens(style, unlocked: true, args: arguments))
            style.annotations = []
            style.language = .terminal
            #expect(!opens(style, args: arguments))
            #expect(opens(style, unlocked: true, args: arguments))
            style.language = .swift
            style.foregroundImage = ImageReference(fileName: "image.png")
            #expect(!opens(style, args: arguments))
        }
    #endif

    @Test func cuesAreInertOutsideASlide() {
        let config = SnapshotConfig()
        #expect(config.firstLineNumber == 1)
        #expect(config.slideCue == nil)
    }

    // MARK: - Rendering

    @Test func continuedGutterAndCuesChangeOnlyTheSlidesThatAskForThem() throws {
        var base = SnapshotConfig()
        base.code = "one\ntwo"
        base.showLineNumbers = true
        let plain = try render(base)

        var startingAtOne = base
        startingAtOne.firstLineNumber = 1
        #expect(try compare(plain, render(startingAtOne)).matches)

        var continued = base
        continued.firstLineNumber = 9
        // Two digits in a whole slide stay under the comparator's fraction tolerance.
        #expect(try compare(plain, render(continued)).differingPixels > 0)

        var badged = base
        badged.slideCue = SlideCue(pageLabel: "2 / 4")
        #expect(try compare(plain, render(badged)).differingPixels > 0)

        var emptyCue = base
        emptyCue.slideCue = SlideCue()
        #expect(try compare(plain, render(emptyCue)).matches)
    }

    /// The card keeps hugging its code: the footer reserves a row, never the slide's width.
    @Test func cueFooterAddsARowWithoutStretchingTheCard() throws {
        var base = SnapshotConfig()
        base.code = "one\ntwo"
        base.background = .transparent
        base.showShadow = false
        var cued = base
        cued.slideCue = SlideCue(rangeLabel: "9–16", continuationLabel: "continues →")
        let plainBox = try opaqueBounds(render(base))
        let cuedBox = try opaqueBounds(render(cued))
        #expect(cuedBox.height > plainBox.height)
        #expect(cuedBox.width == plainBox.width)
    }

    @Test func badgeYieldsTheCornerToATopTrailingWatermark() throws {
        var base = SnapshotConfig()
        base.code = "one"
        base.slideCue = SlideCue(pageLabel: "1 / 2")
        var cornerMark = base
        cornerMark.watermark = Watermark(text: "@vitrine", placement: .topTrailing)
        var plainMark = cornerMark
        plainMark.slideCue = nil
        let width = ExportManager.carouselSlideSize.width
        let leftCorner = CGRect(x: 0, y: 0, width: width / 4, height: 150)
        #expect(
            try !compare(
                render(cornerMark, cropping: leftCorner), render(plainMark, cropping: leftCorner)
            )
            .matches)
    }

    @Test func badgeYieldsTheCornerToAFreeWatermarkDraggedThere() throws {
        var base = SnapshotConfig()
        base.code = "one"
        base.slideCue = SlideCue(pageLabel: "1 / 2")
        var dragged = base
        dragged.watermark = Watermark(
            text: "@vitrine", placement: .free, freePosition: CGPoint(x: 0.9, y: 0.05))
        var unbadged = dragged
        unbadged.slideCue = nil
        let width = ExportManager.carouselSlideSize.width
        let leftCorner = CGRect(x: 0, y: 0, width: width / 4, height: 150)
        #expect(
            try compare(
                render(dragged, cropping: leftCorner), render(unbadged, cropping: leftCorner)
            ).differingPixels > 0)

        // Anywhere else the mark leaves the corner alone, so the badge stays on the right.
        var elsewhere = base
        elsewhere.watermark = Watermark(text: "@vitrine", placement: .free)
        var elsewhereUnbadged = elsewhere
        elsewhereUnbadged.slideCue = nil
        #expect(
            try compare(
                render(elsewhere, cropping: leftCorner),
                render(elsewhereUnbadged, cropping: leftCorner)
            ).differingPixels == 0)
    }

    @Test func exportedSlidesMatchTheirSingleRenders() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineCarousel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var base = SnapshotConfig()
        base.code = code(lines: 9, blankAt: [5])
        let slides = CarouselPaginator.slides(
            for: base.code, maxLinesPerSlide: 5, preferBlankLineBreaks: true)
        #expect(slides.map(\.firstLine) == [1, 6])

        let result = await ExportManager.exportCarousel(
            base, slides: slides, cues: Self.cues, to: dir)
        #expect(result.written == 2)
        let fontSize = CarouselPaginator.fittedFontSize(
            base, slides: slides, cues: Self.cues, size: .linkedIn)
        for (index, slide) in slides.enumerated() {
            let url = dir.appendingPathComponent(
                CarouselPaginator.outputFilename(forSlideAt: index))
            let written = try #require(GoldenComparator.loadImage(at: url))
            let reference = try render(
                CarouselPaginator.slideConfig(
                    base, slide: slide, at: index, of: 2, cues: Self.cues, fontSize: fontSize))
            #expect(try compare(written, reference).matches)
        }

    }

    /// The sheet shows the sampled slide scaled by the count, so that total is what must
    /// land near the bytes actually written.
    @Test func sizeEstimateIsCloseToTheWrittenTotal() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineCarousel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var base = SnapshotConfig()
        base.code = code(lines: 60, blankAt: [11, 25, 40])
        let slides = CarouselPaginator.slides(
            for: base.code, maxLinesPerSlide: 12, preferBlankLineBreaks: true)
        #expect(slides.count == 5)
        let result = await ExportManager.exportCarousel(
            base, slides: slides, cues: Self.cues, to: dir)
        #expect(result.written == slides.count)

        let written = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)
        let total = try written.reduce(0) { $0 + (try Data(contentsOf: $1).count) }
        let estimate = try #require(
            await ExportManager.estimatedCarouselBytes(base, slides: slides, cues: Self.cues))
        #expect(abs(estimate - total) <= total / 10)
    }

    @Test func nothingToSampleHasNoEstimate() async {
        let estimate = await ExportManager.estimatedCarouselBytes(
            SnapshotConfig(), slides: [], cues: .none)
        #expect(estimate == nil)
    }

    // MARK: - Output line

    @Test func outputSummaryNamesTheFilesAndTheSize() {
        func requested(_ count: Int) -> [String] {
            CarouselPaginator.plannedFilenames(slideCount: count, in: nil)
        }
        #expect(
            CarouselPaginator.outputSummary(filenames: requested(4), estimatedBytes: nil)
                == "carousel-01.png … 04.png")
        #expect(
            CarouselPaginator.outputSummary(filenames: requested(1), estimatedBytes: nil)
                == "carousel-01.png")
        #expect(
            CarouselPaginator.outputSummary(filenames: requested(120), estimatedBytes: nil)
                == "carousel-01.png … 120.png")
        let sized = CarouselPaginator.outputSummary(
            filenames: requested(2), estimatedBytes: 1_400_000)
        #expect(sized.hasPrefix("carousel-01.png … 02.png · ~1"))
        #expect(sized.hasSuffix("MB"))
    }

    /// The summary must name what the writer will really produce in the chosen folder.
    @Test func plannedNamesMatchWhatTheExportWrites() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineCarousel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("taken".utf8).write(to: dir.appendingPathComponent("carousel-01.png"))

        let planned = CarouselPaginator.plannedFilenames(slideCount: 2, in: dir)
        #expect(planned == ["carousel-01-2.png", "carousel-02.png"])
        #expect(
            CarouselPaginator.outputSummary(filenames: planned, estimatedBytes: nil)
                == "carousel-01-2.png … 02.png")

        var base = SnapshotConfig()
        base.code = "one\ntwo"
        let slides = CarouselPaginator.slides(for: base.code, maxLinesPerSlide: 1)
        #expect(await ExportManager.exportCarousel(base, slides: slides, to: dir).written == 2)
        for name in planned {
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path))
        }

        // A folder that cannot be listed falls back to the requested names.
        let missing = dir.appendingPathComponent("missing")
        #expect(
            CarouselPaginator.plannedFilenames(slideCount: 1, in: missing) == ["carousel-01.png"])
    }

    @Test func folderPathShortensOnlyTheRealHome() {
        let home = "/Users/jane"
        func path(_ raw: String) -> String {
            CarouselPaginator.displayPath(URL(fileURLWithPath: raw), home: home)
        }
        #expect(path("/Users/jane/Desktop/slides") == "~/Desktop/slides")
        #expect(path("/Users/jane") == "~")
        #expect(path("/Users/janet/Desktop") == "/Users/janet/Desktop")
        #expect(
            CarouselPaginator.displayPath(URL(fileURLWithPath: "/tmp/a"), home: nil) == "/tmp/a")
    }

    // MARK: - Helpers

    private func render(_ config: SnapshotConfig, cropping: CGRect? = nil) throws -> CGImage {
        let image = try #require(
            ExportManager.renderCGImage(
                config, scale: 1, fixedSize: ExportManager.carouselSlideSize))
        guard let cropping else { return image }
        return try #require(image.cropping(to: cropping))
    }

    private func compare(_ lhs: CGImage, _ rhs: CGImage) throws -> GoldenComparator.Result {
        switch GoldenComparator.compare(lhs, rhs) {
        case .success(let result): return result
        case .failure(let failure): throw failure
        }
    }

    /// The bounding box of non-transparent pixels, in pixels.
    private func opaqueBounds(_ image: CGImage) throws -> CGSize {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(
            CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var (minX, maxX, minY, maxY) = (width, 0, height, 0)
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 16 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        return CGSize(width: maxX - minX, height: maxY - minY)
    }
}
