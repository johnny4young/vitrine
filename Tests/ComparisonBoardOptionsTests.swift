import CoreGraphics
import Foundation
import ImageIO
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Comparison board options")
struct ComparisonBoardOptionsTests {
    @Test func defaultsKeepTheHistoricalBoardDimensions() throws {
        let two = ComparisonBoardComposer.metrics(for: try board(count: 2))
        let four = ComparisonBoardComposer.metrics(for: try board(count: 4))

        #expect(two.pointSize == CGSize(width: 1164, height: 568))
        #expect(four.pointSize == CGSize(width: 1164, height: 1068))
        #expect(two.unit == 1)
        #expect(two.footerFrame == nil)
        #expect(two.cardFrames[1] == CGRect(x: 596, y: 48, width: 520, height: 472))
    }

    @Test func aPartialRowStaysCentered() throws {
        let metrics = ComparisonBoardComposer.metrics(for: try board(count: 3, layout: .grid))

        #expect(metrics.cardFrames[2].midX == metrics.pointSize.width / 2)
    }

    @Test(arguments: [ComparisonBoard.Size.widescreen, .openGraph, .square])
    func fixedSizesContainEveryArrangement(_ size: ComparisonBoard.Size) throws {
        let canvas = try #require(size.fixedPointSize)
        for count in ComparisonBoard.itemCountRange {
            for layout in ComparisonBoard.Layout.allCases {
                for gap in [
                    ComparisonBoard.gapRange.lowerBound, ComparisonBoard.gapRange.upperBound,
                ] {
                    for showsFooter in [false, true] {
                        let metrics = ComparisonBoardComposer.metrics(
                            itemCount: count, layout: layout, size: size, gap: gap,
                            showsFooter: showsFooter)
                        expectContained(metrics, canvas: canvas)
                    }
                }
            }
        }
    }

    @Test(arguments: [ComparisonBoard.Size.widescreen, .openGraph, .square])
    func fixedSizesRenderAtTheirExactDimensions(_ size: ComparisonBoard.Size) throws {
        let canvas = try #require(size.fixedPointSize)
        let value = try board(count: 4, size: size, showsFooter: true)

        let oneX = try ComparisonBoardComposer.compose(value, scale: 1)
        let twoX = try ComparisonBoardComposer.compose(value, scale: 2)

        #expect(oneX.pixelSize == canvas)
        #expect(twoX.pixelSize == CGSize(width: canvas.width * 2, height: canvas.height * 2))
    }

    @Test func gapIsBoundedAndMovesTheCards() throws {
        let tight = ComparisonBoardComposer.metrics(for: try board(count: 2, gap: 0))
        let wide = ComparisonBoardComposer.metrics(for: try board(count: 2, gap: 40))

        #expect(wide.pointSize.width - tight.pointSize.width == 40)
        #expect(wide.cardFrames[1].minX - wide.cardFrames[0].maxX == 40)
        #expect(tight.cardFrames[1].minX == tight.cardFrames[0].maxX)

        #expect(try board(count: 2, gap: 500).gap == ComparisonBoard.gapRange.upperBound)
        #expect(try board(count: 2, gap: -3).gap == ComparisonBoard.gapRange.lowerBound)
        #expect(try board(count: 2, gap: .nan).gap == ComparisonBoard.defaultGap)
    }

    @Test func footerAddsHeightOnlyToAnAutomaticBoard() throws {
        let plain = ComparisonBoardComposer.metrics(for: try board(count: 2))
        let footed = ComparisonBoardComposer.metrics(for: try board(count: 2, showsFooter: true))
        let fixed = ComparisonBoardComposer.metrics(
            for: try board(count: 2, size: .square, showsFooter: true))

        #expect(footed.pointSize.height == plain.pointSize.height + 40)
        #expect(footed.cardFrames == plain.cardFrames)
        #expect(fixed.pointSize == CGSize(width: 1080, height: 1080))
        #expect(fixed.footerFrame != nil)
    }

    /// Nothing typed or captured can reach the footer: its pixels match across boards that
    /// share only a capture count.
    @Test func footerPixelsDependOnTheCountAlone() throws {
        func compose(_ label: String, _ detail: String, color: CGColor) throws -> (CGImage, CGRect)
        {
            let board = try ComparisonBoard(
                items: (0..<2).map { _ in
                    ComparisonBoard.Item(
                        asset: RenderedAsset(cgImage: solidImage(color: color), profile: .sRGB),
                        label: label, detail: detail)
                },
                size: .widescreen, background: .card, showsFooter: true)
            let frame = try #require(ComparisonBoardComposer.metrics(for: board).footerFrame)
            return (try ComparisonBoardComposer.compose(board, scale: 1).cgImage, frame)
        }

        let (first, frame) = try compose(
            "One", "ghp_private_value", color: CGColor(gray: 0.2, alpha: 1))
        let (second, _) = try compose("Two words", "Other", color: CGColor(gray: 0.8, alpha: 1))

        let footerRect = frame.integral
        #expect(
            rgba(try #require(first.cropping(to: footerRect)))
                == rgba(try #require(second.cropping(to: footerRect))))

        let off = try ComparisonBoardComposer.compose(
            ComparisonBoard(
                items: (0..<2).map { _ in captionedItem(label: "One", detail: "ghp_private_value")
                },
                size: .widescreen, background: .card, showsFooter: false),
            scale: 1)
        #expect(
            Set(rgba(try #require(first.cropping(to: footerRect)))).count
                > Set(rgba(try #require(off.cgImage.cropping(to: footerRect)))).count,
            "the footer line should draw glyphs")
    }

    /// Through the real encoders, because a raster with alpha can still lose it when written.
    @Test(arguments: [ExportFormat.png, .heic, .avif])
    func encodedExportsKeepTransparencyOnlyWhenChosen(_ format: ExportFormat) throws {
        guard format.isEncodingAvailable else { return }
        let draft = try makeDraft(count: 2)
        for background in ComparisonBoard.Background.allCases {
            draft.background = background
            let payload = try ComparisonBoardExporter.encodedPayloadChecked(
                for: draft, format: format, profile: .sRGB)
            let source = try #require(CGImageSourceCreateWithData(payload.data as CFData, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let corner = rgba(decoded)[3]
            if background == .transparent {
                #expect(corner <= 2, "\(format) \(background): \(corner)")
                let card = ComparisonBoardComposer.metrics(for: try draft.board()).cardFrames[0]
                let inside = rgba(decoded)[
                    Int(card.midY) * decoded.width * 4 + Int(card.minX + 3) * 4 + 3]
                #expect(inside >= 250, "\(format): the card should stay opaque, got \(inside)")
            } else {
                #expect(corner >= 253, "\(format) \(background): \(corner)")
            }
        }
    }

    @Test func backgroundsAreDistinct() throws {
        let images = try ComparisonBoard.Background.allCases.map { background in
            rgba(
                try ComparisonBoardComposer.compose(
                    board(count: 2, background: background), scale: 1
                ).cgImage)
        }
        #expect(Set(images).count == images.count)
    }

    @Test(arguments: ComparisonBoard.Size.allCases)
    func compositionIsDeterministic(_ size: ComparisonBoard.Size) throws {
        for background in ComparisonBoard.Background.allCases {
            let value = try board(
                count: 3, size: size, gap: 12, background: background, showsFooter: true)
            let first = try ComparisonBoardComposer.compose(value, scale: 1)
            let second = try ComparisonBoardComposer.compose(value, scale: 1)
            #expect(rgba(first.cgImage) == rgba(second.cgImage))
        }
    }

    /// What the stage shows must equal the file a 1× export writes, byte for byte.
    @Test(arguments: ComparisonBoard.Size.allCases)
    func previewEqualsTheEncodedOneXExport(_ size: ComparisonBoard.Size) throws {
        let draft = try makeDraft(count: 3)
        applyAllOptions(to: draft, size: size)

        let preview = try draft.composePreview(profile: .sRGB)
        let payload = try ComparisonBoardExporter.encodedPayloadChecked(
            for: draft, format: .png, profile: .sRGB)
        let source = try #require(CGImageSourceCreateWithData(payload.data as CFData, nil))
        let exported = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(rgba(preview.cgImage) == rgba(exported))
    }

    /// A 2× export is the same composition with more pixels: reduced to the preview's size,
    /// only edge antialiasing may differ.
    @Test(arguments: [ComparisonBoard.Size.automatic, .widescreen, .square])
    func previewMatchesAHigherScaleExport(_ size: ComparisonBoard.Size) throws {
        let draft = try makeDraft(count: 3, renderScale: 2)
        applyAllOptions(to: draft, size: size)

        let preview = rgba(try draft.composePreview(profile: .sRGB).cgImage)
        let payload = try ComparisonBoardExporter.encodedPayloadChecked(
            for: draft, format: .png, profile: .sRGB)
        let source = try #require(CGImageSourceCreateWithData(payload.data as CFData, nil))
        let exported = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let metrics = draft.metrics
        #expect(CGFloat(exported.width) == metrics.pointSize.width * 2)

        let reduced = rgba(
            exported, width: Int(metrics.pointSize.width), height: Int(metrics.pointSize.height))
        #expect(reduced.count == preview.count)
        var total = 0
        for index in stride(from: 0, to: reduced.count, by: 4) {
            total += abs(Int(reduced[index]) - Int(preview[index]))
        }
        let average = Double(total) / Double(reduced.count / 4)
        #expect(average < 1.5, "mean red-channel difference \(average)")
    }

    /// Clicking a caption must land on what is drawn, whichever size and layout is active.
    @Test(arguments: ComparisonBoard.Size.allCases)
    func captionFramesCoverTheDrawnCaption(_ size: ComparisonBoard.Size) throws {
        for layout in ComparisonBoard.Layout.allCases {
            let items = (0..<3).map { captionedItem(label: "Capture \($0)", detail: "Detail") }
            var edited = items
            edited[1] = captionedItem(label: "Changed", detail: "Other words")
            let before = try ComparisonBoard(items: items, layout: layout, size: size, gap: 8)
            let after = try ComparisonBoard(items: edited, layout: layout, size: size, gap: 8)

            let changed = try #require(
                changedBounds(
                    try ComparisonBoardComposer.compose(before, scale: 1).cgImage,
                    try ComparisonBoardComposer.compose(after, scale: 1).cgImage),
                "\(size) \(layout) drew no caption change")
            let frame = ComparisonBoardComposer.metrics(for: before).captionFrame(at: 1)

            #expect(
                frame.insetBy(dx: -1, dy: -1).contains(changed),
                "\(size) \(layout): \(changed) outside \(frame)")
        }
    }

    @Test func captionFramesFollowTheirCaptureThroughAReorder() throws {
        let draft = try makeDraft(count: 2)
        let first = draft.items[0].id
        let original = try #require(draft.captionFrames[first])

        draft.moveItem(id: first, offset: 1)

        let moved = try #require(draft.captionFrames[first])
        #expect(moved.minX > original.minX)
        #expect(draft.captionFrames.count == 2)
    }

    /// Each control has to reach the picture and re-trigger the preview, not just be stored.
    @Test func everyOptionChangesThePreviewKeyAndThePixels() throws {
        let draft = try makeDraft(count: 2)
        var keys = [draft.previewKey(profile: .sRGB)]
        var images = [rgba(try draft.composePreview(profile: .sRGB).cgImage)]
        let changes: [() -> Void] = [
            { draft.layout = .vertical },
            { draft.size = .square },
            { draft.gap = 4 },
            { draft.background = .aurora },
            { draft.showsFooter = true },
        ]
        for change in changes {
            change()
            keys.append(draft.previewKey(profile: .sRGB))
            images.append(rgba(try draft.composePreview(profile: .sRGB).cgImage))
        }
        #expect(Set(keys).count == keys.count)
        #expect(Set(images).count == images.count)
    }

    /// Worst case of every arrangement: captions readable at 1× and an image worth showing.
    @Test(arguments: [ComparisonBoard.Size.widescreen, .openGraph, .square])
    func everyFixedArrangementStaysLegible(_ size: ComparisonBoard.Size) {
        for count in ComparisonBoard.itemCountRange {
            for layout in ComparisonBoard.Layout.allCases {
                for gap in [
                    ComparisonBoard.gapRange.lowerBound, ComparisonBoard.gapRange.upperBound,
                ] {
                    for showsFooter in [false, true] {
                        let metrics = ComparisonBoardComposer.metrics(
                            itemCount: count, layout: layout, size: size, gap: gap,
                            showsFooter: showsFooter)
                        let name = "\(size) \(layout) \(count) gap \(gap) footer \(showsFooter)"
                        #expect(18 * metrics.unit >= 12, "label: \(name)")
                        #expect(13 * metrics.unit >= 9, "detail: \(name)")
                        #expect(metrics.imageHeight >= 100, "image: \(name)")
                    }
                }
            }
        }
    }

    /// Measures the rendered tightest case rather than trusting the metrics.
    @Test func fourCapturesOnOpenGraphRenderLegibly() throws {
        func compose(label: String, red: CGFloat) throws -> CGImage {
            let items = (0..<4).map { index in
                ComparisonBoard.Item(
                    asset: RenderedAsset(
                        cgImage: solidImage(
                            width: 968, height: 720,
                            color: CGColor(
                                red: index == 0 ? red : 0.5, green: 0.3, blue: 0.7, alpha: 1)),
                        profile: .sRGB),
                    label: index == 0 ? label : "Same", detail: nil)
            }
            let board = try ComparisonBoard(items: items, layout: .vertical, size: .openGraph)
            return try ComparisonBoardComposer.compose(board, scale: 1).cgImage
        }

        let glyphs = try #require(
            changedBounds(
                try compose(label: "HEH", red: 0.5), try compose(label: "XIX", red: 0.5)))
        #expect(glyphs.height >= 8, "label cap height \(glyphs.height) px")

        let image = try #require(
            changedBounds(
                try compose(label: "Same", red: 0.1), try compose(label: "Same", red: 0.9)))
        #expect(image.height >= 100, "image height \(image.height) px")
        #expect(image.width >= 130, "image width \(image.width) px")
    }

    /// A neighbour's shadow must not darken one side of a card when cards touch.
    @Test(arguments: [ComparisonBoard.Background.card, .transparent])
    func neighbouringShadowsDoNotLandOnACard(_ background: ComparisonBoard.Background) throws {
        let wide = solidImage(width: 968, height: 720)
        let board = try ComparisonBoard(
            items: (0..<2).map { _ in
                ComparisonBoard.Item(
                    asset: RenderedAsset(cgImage: wide, profile: .sRGB), label: "Same", detail: nil)
            },
            gap: 0, background: background)
        let image = try ComparisonBoardComposer.compose(board, scale: 1).cgImage
        let pixels = rgba(image)
        let card = ComparisonBoardComposer.metrics(for: board).cardFrames[0]

        func red(_ x: CGFloat, _ y: CGFloat) -> Int {
            Int(pixels[(Int(y) * image.width + Int(x)) * 4])
        }
        for y in stride(from: card.midY, to: card.maxY - 24, by: 20) {
            let free = red(card.minX + 4, y)
            let beside = red(card.maxX - 5, y)
            #expect(abs(free - beside) <= 1, "row \(y): \(free) vs \(beside)")
        }
    }

    @Test func draftMetricsSurviveAnInvalidCaption() throws {
        let draft = try makeDraft(count: 2)
        let expected = draft.metrics
        draft.items[0].label = ""

        #expect(!draft.isValid)
        #expect(draft.metrics == expected)
    }

    @Test func openGraphExportsItsExactPixelsAtAnyDraftScale() throws {
        let draft = try ComparisonBoardDraft(
            captures: [
                Capture(code: "a", languageID: "swift", themeID: "one-dark"),
                Capture(code: "b", languageID: "swift", themeID: "one-dark"),
            ],
            baseConfig: SnapshotConfig(),
            profile: .sRGB,
            renderScale: 2,
            render: { _, _, _ in solidImage() })
        #expect(draft.resolvedExportScale == 2)
        draft.size = .openGraph
        #expect(draft.resolvedExportScale == 1)

        let png = try ComparisonBoardExporter.encodedPayloadChecked(
            for: draft, format: .png, profile: .sRGB)
        let source = try #require(CGImageSourceCreateWithData(png.data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 1200)
        #expect(decoded.height == 630)

        let pdf = try ComparisonBoardExporter.encodedPayloadChecked(
            for: draft, format: .pdf, profile: .sRGB)
        let provider = try #require(CGDataProvider(data: pdf.data as CFData))
        let page = try #require(CGPDFDocument(provider)?.page(at: 1))
        #expect(page.getBoxRect(.mediaBox).size == CGSize(width: 1200, height: 630))
    }

    @Test func squareExportKeepsTheDraftScale() throws {
        let draft = try ComparisonBoardDraft(
            captures: [
                Capture(code: "a", languageID: "swift", themeID: "one-dark"),
                Capture(code: "b", languageID: "swift", themeID: "one-dark"),
            ],
            baseConfig: SnapshotConfig(),
            profile: .sRGB,
            renderScale: 2,
            render: { _, _, _ in solidImage() })
        draft.size = .square

        let png = try ComparisonBoardExporter.encodedPayloadChecked(
            for: draft, format: .png, profile: .sRGB)
        let source = try #require(CGImageSourceCreateWithData(png.data as CFData, nil))
        #expect(CGImageSourceCreateImageAtIndex(source, 0, nil)?.width == 2160)
    }

    // MARK: - Helpers

    private func expectContained(_ metrics: ComparisonBoardComposer.Metrics, canvas: CGSize) {
        let bounds = CGRect(origin: .zero, size: canvas)
        #expect(metrics.pointSize == canvas)
        for (index, frame) in metrics.cardFrames.enumerated() {
            #expect(bounds.contains(frame))
            let caption = metrics.captionFrame(at: index)
            #expect(frame.contains(caption))
            // The image keeps real space above the caption, at any size.
            #expect(caption.minY - frame.minY > ComparisonBoardComposer.cardPadding * metrics.unit)
            if let footer = metrics.footerFrame {
                #expect(!frame.intersects(footer))
            }
            for other in metrics.cardFrames[(index + 1)...] {
                #expect(frame.intersection(other).isEmpty)
            }
        }
    }

    private func board(
        count: Int,
        layout: ComparisonBoard.Layout = .automatic,
        size: ComparisonBoard.Size = .automatic,
        gap: CGFloat = ComparisonBoard.defaultGap,
        background: ComparisonBoard.Background = .vitrine,
        showsFooter: Bool = false
    ) throws -> ComparisonBoard {
        try ComparisonBoard(
            items: (1...count).map { captionedItem(label: "Capture \($0)", detail: nil) },
            layout: layout,
            size: size,
            gap: gap,
            background: background,
            showsFooter: showsFooter)
    }

    private func makeDraft(count: Int, renderScale: CGFloat = 1) throws -> ComparisonBoardDraft {
        try ComparisonBoardDraft(
            captures: (1...count).map {
                Capture(code: "\($0)", languageID: "swift", themeID: "one-dark")
            },
            baseConfig: SnapshotConfig(),
            profile: .sRGB,
            renderScale: renderScale,
            render: { _, _, _ in solidImage() })
    }

    private func applyAllOptions(to draft: ComparisonBoardDraft, size: ComparisonBoard.Size) {
        draft.size = size
        draft.gap = 12
        draft.background = .aurora
        draft.showsFooter = true
    }

    private func captionedItem(label: String, detail: String?) -> ComparisonBoard.Item {
        ComparisonBoard.Item(
            asset: RenderedAsset(cgImage: solidImage(), profile: .sRGB),
            label: label,
            detail: detail)
    }

    private func solidImage(
        width: Int = 320,
        height: Int = 180,
        color: CGColor = CGColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1)
    ) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func rgba(_ image: CGImage, width: Int? = nil, height: Int? = nil) -> [UInt8] {
        let width = width ?? image.width
        let height = height ?? image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    /// The top-left-origin box around the glyphs that differ between two same-sized images.
    /// The card's soft shadow also reacts to its text, far more faintly, so a threshold
    /// separates the two.
    private func changedBounds(_ first: CGImage, _ second: CGImage) -> CGRect? {
        let glyphDifference = 48
        let a = rgba(first)
        let b = rgba(second)
        var minX = Int.max
        var minY = Int.max
        var maxX = -1
        var maxY = -1
        for y in 0..<first.height {
            for x in 0..<first.width {
                let offset = (y * first.width + x) * 4
                guard abs(Int(a[offset]) - Int(b[offset])) > glyphDifference else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
