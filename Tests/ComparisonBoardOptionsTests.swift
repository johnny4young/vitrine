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

    @Test func footerIsGeneratedFromTheCountAlone() throws {
        let secret = "ghp_private_value"
        let draft = try ComparisonBoardDraft(
            captures: [
                Capture(code: secret, languageID: "swift", themeID: "one-dark"),
                Capture(code: secret, languageID: "swift", themeID: "one-dark"),
            ],
            baseConfig: SnapshotConfig(),
            profile: .sRGB,
            render: { _, _, _ in solidImage() })
        draft.showsFooter = true
        draft.items[0].label = "Named label"
        draft.items[0].detail = "Named detail"

        let footer = try #require(try draft.board().footerText)

        #expect(footer == ComparisonBoard.footerText(captureCount: 2))
        for hidden in [secret, "Named label", "Named detail"] {
            #expect(!footer.contains(hidden))
        }
        draft.showsFooter = false
        #expect(try draft.board().footerText == nil)
    }

    @Test func onlyTheTransparentBackgroundKeepsAlpha() throws {
        for background in ComparisonBoard.Background.allCases {
            let asset = try ComparisonBoardComposer.compose(
                board(count: 2, background: background), scale: 1)
            let corner = rgba(asset.cgImage)[3]
            #expect(corner == (background == .transparent ? 0 : 255), "\(background)")
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

    /// The preview and an export share a composer; only the budget differs.
    @Test(arguments: ComparisonBoard.Size.allCases)
    func previewMatchesTheExportPixels(_ size: ComparisonBoard.Size) throws {
        let draft = try makeDraft(count: 3)
        draft.size = size
        draft.gap = 12
        draft.background = .aurora
        draft.showsFooter = true

        let preview = try draft.compose(scale: 1, profile: .sRGB, budget: .preview)
        let export = try draft.compose(scale: 1, profile: .sRGB, budget: .export)

        #expect(rgba(preview.cgImage) == rgba(export.cgImage))
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

    @Test func draftCarriesEveryOptionIntoItsBoard() throws {
        let draft = try makeDraft(count: 2)
        draft.size = .square
        draft.gap = 12
        draft.background = .card
        draft.showsFooter = true

        let board = try draft.board()

        #expect(board.size == .square)
        #expect(board.gap == 12)
        #expect(board.background == .card)
        #expect(board.showsFooter)
        #expect(draft.metrics == ComparisonBoardComposer.metrics(for: board))
    }

    @Test func previewKeyTracksEveryOption() throws {
        let draft = try makeDraft(count: 2)
        var seen = [draft.previewKey(profile: .sRGB)]
        let changes: [() -> Void] = [
            { draft.size = .openGraph },
            { draft.gap = 4 },
            { draft.background = .aurora },
            { draft.showsFooter = true },
        ]
        for change in changes {
            change()
            let key = draft.previewKey(profile: .sRGB)
            #expect(!seen.contains(key))
            seen.append(key)
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

    private func makeDraft(count: Int) throws -> ComparisonBoardDraft {
        try ComparisonBoardDraft(
            captures: (1...count).map {
                Capture(code: "\($0)", languageID: "swift", themeID: "one-dark")
            },
            baseConfig: SnapshotConfig(),
            profile: .sRGB,
            render: { _, _, _ in solidImage() })
    }

    private func captionedItem(label: String, detail: String?) -> ComparisonBoard.Item {
        ComparisonBoard.Item(
            asset: RenderedAsset(cgImage: solidImage(), profile: .sRGB),
            label: label,
            detail: detail)
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
        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        return context.makeImage()!
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
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
