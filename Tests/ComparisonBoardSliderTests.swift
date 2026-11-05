import CoreGraphics
import Foundation
import ImageIO
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Comparison board slider")
struct ComparisonBoardSliderTests {
    private let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    private let magenta = CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
    private let clear = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)

    // MARK: - Divider

    /// A hard edge at whole pixels: no blended column on either side of the line.
    @Test(arguments: [CGFloat(1), 2, 3])
    func dividerFillsExactPixelsAtEveryScale(_ scale: CGFloat) throws {
        let value = try board(red, blue, dividerPercent: 37)
        let wipe = try #require(wipe(of: value))
        let image = Bitmap(try ComparisonBoardComposer.compose(value, scale: scale).cgImage)
        let y = Int(wipe.area.midY * scale)

        let drawn = try #require(image.whiteRun(row: y))
        #expect(drawn.lowerBound == Int((wipe.dividerX - 1) * scale))
        #expect(drawn.upperBound == Int((wipe.dividerX + 1) * scale))

        let left = image.pixel(drawn.lowerBound - 1, y)
        let right = image.pixel(drawn.upperBound, y)
        #expect(left.green <= 3 && left.blue <= 3, "left of the line: \(left)")
        #expect(right.red <= 3 && right.green <= 3, "right of the line: \(right)")
    }

    @Test func thePercentMovesTheDrawnLineAcrossTheCaptures() throws {
        func line(_ percent: Int) throws -> (run: Range<Int>, area: CGRect) {
            let value = try board(red, blue, dividerPercent: percent)
            let area = try #require(wipe(of: value)).area
            let image = Bitmap(try ComparisonBoardComposer.compose(value, scale: 1).cgImage)
            return (try #require(image.whiteRun(row: Int(area.midY))), area)
        }

        let (low, area) = try line(25)
        let (high, _) = try line(75)
        let travelled = CGFloat(high.lowerBound - low.lowerBound)
        #expect(abs(travelled - area.width / 2) <= 1)
    }

    /// Every format encodes the one composed raster, so each shows the line where the
    /// control placed it. Only PNG is lossless; the others may soften a pixel.
    @Test(arguments: ExportFormat.allCases)
    func everyFormatDrawsTheDividerWhereThePreviewDoes(_ format: ExportFormat) throws {
        guard format.isEncodingAvailable else { return }
        let draft = try makeDraft(renderScale: 2)
        draft.layout = .slider
        draft.dividerPercent = 62
        let wipe = try #require(draft.wipe)

        let preview = Bitmap(try draft.composePreview(profile: .sRGB).cgImage)
        let previewRun = try #require(preview.whiteRun(row: Int(wipe.area.midY)))
        #expect(previewRun == Int(wipe.dividerX - 1)..<Int(wipe.dividerX + 1))

        let payload = try ComparisonBoardExporter.encodedPayloadChecked(
            for: draft, format: format, profile: .sRGB)
        let exported = Bitmap(try decode(payload.data, format: format, scale: 2))
        let run = try #require(
            exported.whiteRun(row: Int(wipe.area.midY * 2), minimum: format == .png ? 250 : 200))
        let expected = Int(wipe.dividerX - 1) * 2..<Int(wipe.dividerX + 1) * 2
        if format == .png {
            #expect(run == expected)
        } else {
            #expect(abs(run.lowerBound - expected.lowerBound) <= 1)
            #expect(abs(run.upperBound - expected.upperBound) <= 1)
        }
    }

    @Test func previewEqualsTheEncodedOneXExport() throws {
        let draft = try makeDraft()
        draft.layout = .slider
        draft.dividerPercent = 30
        draft.size = .widescreen

        let preview = Bitmap(try draft.composePreview(profile: .sRGB).cgImage)
        let payload = try ComparisonBoardExporter.encodedPayloadChecked(
            for: draft, format: .png, profile: .sRGB)

        #expect(preview.bytes == Bitmap(try decode(payload.data, format: .png, scale: 1)).bytes)
    }

    @Test func thePercentIsBoundedAndSurvivesARoundTripThroughTheControl() throws {
        let range = ComparisonBoard.dividerRange
        #expect(try board(red, blue, dividerPercent: -4).dividerPercent == range.lowerBound)
        #expect(try board(red, blue, dividerPercent: 400).dividerPercent == range.upperBound)

        for percent in ComparisonBoard.dividerRange {
            let wipe = try #require(wipe(of: try board(red, blue, dividerPercent: percent)))
            #expect(wipe.percent(atX: wipe.dividerX) == percent)
            #expect(wipe.percent(atX: -10_000) == ComparisonBoard.dividerRange.lowerBound)
            #expect(wipe.percent(atX: 10_000) == ComparisonBoard.dividerRange.upperBound)
        }
    }

    // MARK: - Alignment

    /// Captures keep their relative size and top-left corner, so what is common lines up.
    @Test func differentSizesShareOneScaleAndTheirTopLeftCorner() throws {
        let value = try board(
            solid(red, width: 400, height: 300), solid(blue, width: 800, height: 200),
            dividerPercent: 75)
        let wipe = try #require(wipe(of: value))
        let image = Bitmap(try ComparisonBoardComposer.compose(value, scale: 1).cgImage)
        let area = wipe.area
        let leftWidth = area.width / 2
        let rightHeight = area.height * 2 / 3
        func color(_ x: CGFloat, _ y: CGFloat) -> Pixel {
            image.pixel(Int(area.minX + x), Int(area.minY + y))
        }

        #expect(color(8, 8).isRed, "the left capture starts at the corner")
        #expect(color(leftWidth - 4, area.height - 8).isRed, "and keeps its own size")
        #expect(!color(leftWidth + 4, 8).isRed, "it ends at half the width")
        #expect(!color(leftWidth + 4, 8).isBlue, "and the other capture does not fill in")

        let onRight = area.width * 0.9
        #expect(color(onRight, 8).isBlue, "the right capture starts at the same top")
        #expect(color(onRight, rightHeight - 4).isBlue)
        #expect(!color(onRight, rightHeight + 4).isBlue, "it ends at two thirds of the height")
        #expect(!color(onRight, rightHeight + 4).isRed, "and the other capture does not fill in")
    }

    // MARK: - Redaction

    /// A hole in one capture must show the card, never the pixels of the other capture.
    @Test(arguments: [10, 50, 90])
    func nothingShowsThroughFromTheOtherCapture(_ percent: Int) throws {
        for (first, second) in [(clear, blue), (magenta, clear)] {
            let value = try board(solid(first), solid(second), dividerPercent: percent)
            let wipe = try #require(wipe(of: value))
            let image = Bitmap(try ComparisonBoardComposer.compose(value, scale: 2).cgImage)
            let columns = 0..<image.width
            let split = Int(wipe.dividerX) * 2
            let rows = Int(wipe.area.minY) * 2..<Int(wipe.area.maxY) * 2

            for y in rows where y.isMultiple(of: 16) {
                for x in columns {
                    let pixel = image.pixel(x, y)
                    if x < split {
                        #expect(!pixel.isBlue, "the right capture reached (\(x), \(y))")
                    } else {
                        #expect(!pixel.isMagenta, "the left capture reached (\(x), \(y))")
                    }
                }
            }
        }
    }

    // MARK: - Captions

    /// Clicking a caption must land on what is drawn, whichever board size is active.
    @Test(arguments: ComparisonBoard.Size.allCases)
    func captionFramesCoverTheDrawnCaption(_ size: ComparisonBoard.Size) throws {
        func compose(_ labels: [String]) throws -> (image: CGImage, board: ComparisonBoard) {
            let value = try ComparisonBoard(
                items: labels.map {
                    ComparisonBoard.Item(
                        asset: RenderedAsset(cgImage: solid(red), profile: .sRGB),
                        label: $0, detail: "Detail")
                },
                layout: .slider, size: size)
            return (try ComparisonBoardComposer.compose(value, scale: 1).cgImage, value)
        }
        let original = try compose(["Before", "After"])
        let metrics = ComparisonBoardComposer.metrics(for: original.board)
        #expect(metrics.captionFrame(at: 0).maxX <= metrics.captionFrame(at: 1).minX)

        for (index, edited) in [["Changed", "After"], ["Before", "Changed"]].enumerated() {
            let changed = try #require(
                Bitmap(original.image).changedBounds(from: Bitmap(try compose(edited).image)))
            let frame = metrics.captionFrame(at: index)
            #expect(frame.insetBy(dx: -1, dy: -1).contains(changed), "\(changed) outside \(frame)")
            #expect(metrics.cardFrames[0].contains(frame))
        }
    }

    @Test func captionFramesFollowTheirCaptureThroughAReorder() throws {
        let draft = try makeDraft()
        draft.layout = .slider
        let first = draft.items[0].id
        let original = try #require(draft.captionFrames[first])

        draft.moveItem(id: first, offset: 1)

        #expect(try #require(draft.captionFrames[first]).minX > original.minX)
    }

    // MARK: - Capture count and other layouts

    /// A wipe needs a pair: any other count stays a complete board rather than losing a capture.
    @Test(arguments: [3, 4])
    func otherCountsDrawAsAutomatic(_ count: Int) throws {
        func compose(_ layout: ComparisonBoard.Layout) throws -> [UInt8] {
            let items = (0..<count).map { index in
                ComparisonBoard.Item(
                    asset: RenderedAsset(cgImage: solid(red), profile: .sRGB),
                    label: "Capture \(index)")
            }
            let value = try ComparisonBoard(items: items, layout: layout)
            return Bitmap(try ComparisonBoardComposer.compose(value, scale: 1).cgImage).bytes
        }

        #expect(try compose(.slider) == compose(.automatic))
        #expect(
            !ComparisonBoardComposer.metrics(
                itemCount: count, layout: .slider, size: .automatic, gap: 0, showsFooter: false
            ).isWipe)
    }

    @Test func onlyATwoCaptureDraftOffersTheSlider() throws {
        let three = try ComparisonBoardDraft(
            captures: ["a", "b", "c"].map {
                Capture(code: $0, languageID: "swift", themeID: "one-dark")
            },
            baseConfig: SnapshotConfig(),
            profile: .sRGB,
            render: { _, _, _ in solid(red) })
        #expect(!three.availableLayouts.contains(.slider))

        three.removeItem(id: three.items[0].id)
        #expect(three.availableLayouts.contains(.slider))

        three.layout = .slider
        three.removeItem(id: three.items[0].id)
        #expect(three.items.count == 2, "a wipe cannot lose one of its two captures")
        #expect(three.wipe != nil)
    }

    @Test func aWipeHasNoGapAndOtherLayoutsHaveNoDivider() throws {
        let draft = try makeDraft()
        let automatic = Bitmap(try draft.composePreview(profile: .sRGB).cgImage).bytes
        #expect(draft.wipe == nil)
        draft.dividerPercent = 20
        #expect(Bitmap(try draft.composePreview(profile: .sRGB).cgImage).bytes == automatic)

        draft.layout = .slider
        let wiped = Bitmap(try draft.composePreview(profile: .sRGB).cgImage).bytes
        draft.gap = 0
        #expect(Bitmap(try draft.composePreview(profile: .sRGB).cgImage).bytes == wiped)
    }

    @Test func movingTheDividerRefreshesThePreview() throws {
        let draft = try makeDraft()
        draft.layout = .slider
        let key = draft.previewKey(profile: .sRGB)
        let image = Bitmap(try draft.composePreview(profile: .sRGB).cgImage).bytes
        let line = try #require(draft.wipe).dividerX

        draft.dividerPercent = 20

        #expect(draft.previewKey(profile: .sRGB) != key)
        #expect(Bitmap(try draft.composePreview(profile: .sRGB).cgImage).bytes != image)
        #expect(try #require(draft.wipe).dividerX < line)
    }

    @Test(arguments: [ComparisonBoard.Size.widescreen, .openGraph, .square])
    func fixedSizesRenderAtTheirExactDimensions(_ size: ComparisonBoard.Size) throws {
        let canvas = try #require(size.fixedPointSize)
        let value = try board(red, blue, size: size, showsFooter: true)
        let wipe = try #require(wipe(of: value))
        let metrics = ComparisonBoardComposer.metrics(for: value)

        #expect(try ComparisonBoardComposer.compose(value, scale: 1).pixelSize == canvas)
        #expect(metrics.cardFrames[0].contains(wipe.area))
        #expect(wipe.area.maxY <= metrics.captionFrame(at: 0).minY)
        for edge in [wipe.area.minX, wipe.area.minY, wipe.area.width, wipe.dividerX] {
            #expect(edge == edge.rounded(), "\(edge) is not on the pixel grid")
        }
    }

    // MARK: - Helpers

    private struct Pixel: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        var isRed: Bool { red > 200 && green < 40 && blue < 40 }
        var isBlue: Bool { blue > 200 && red < 40 && green < 40 }
        var isMagenta: Bool { red > 200 && blue > 200 && green < 40 }
    }

    private struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) {
            let width = image.width
            let height = image.height
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
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            self.width = width
            self.height = height
            self.bytes = bytes
        }

        func pixel(_ x: Int, _ y: Int) -> Pixel {
            let offset = (y * width + x) * 4
            return Pixel(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2])
        }

        /// The columns of a row that read as white.
        func whiteRun(row: Int, minimum: UInt8 = 250) -> Range<Int>? {
            let columns = (0..<width).filter {
                let pixel = pixel($0, row)
                return pixel.red >= minimum && pixel.green >= minimum && pixel.blue >= minimum
            }
            guard let first = columns.first, let last = columns.last else { return nil }
            return first..<(last + 1)
        }

        /// The box around strong differences; the card's soft shadow reacts far more faintly.
        func changedBounds(from other: Bitmap) -> CGRect? {
            var box: CGRect?
            for y in 0..<height {
                for x in 0..<width
                where abs(Int(pixel(x, y).green) - Int(other.pixel(x, y).green)) > 48 {
                    let cell = CGRect(x: x, y: y, width: 1, height: 1)
                    box = box?.union(cell) ?? cell
                }
            }
            return box
        }
    }

    private func decode(_ data: Data, format: ExportFormat, scale: CGFloat) throws -> CGImage {
        guard format == .pdf else {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }
        let provider = try #require(CGDataProvider(data: data as CFData))
        let page = try #require(CGPDFDocument(provider)?.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let context = try #require(
            CGContext(
                data: nil,
                width: Int(box.width * scale),
                height: Int(box.height * scale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)
        return try #require(context.makeImage())
    }

    private func wipe(of board: ComparisonBoard) -> ComparisonBoardComposer.Wipe? {
        ComparisonBoardComposer.metrics(for: board).wipe(
            captureSizes: board.items.map(\.asset.pixelSize),
            dividerPercent: board.dividerPercent)
    }

    private func board(
        _ first: CGColor,
        _ second: CGColor,
        size: ComparisonBoard.Size = .automatic,
        showsFooter: Bool = false,
        dividerPercent: Int = ComparisonBoard.defaultDividerPercent
    ) throws -> ComparisonBoard {
        try board(
            solid(first), solid(second), size: size, showsFooter: showsFooter,
            dividerPercent: dividerPercent)
    }

    private func board(
        _ first: CGImage,
        _ second: CGImage,
        size: ComparisonBoard.Size = .automatic,
        showsFooter: Bool = false,
        dividerPercent: Int = ComparisonBoard.defaultDividerPercent
    ) throws -> ComparisonBoard {
        try ComparisonBoard(
            items: [
                ComparisonBoard.Item(
                    asset: RenderedAsset(cgImage: first, profile: .sRGB), label: "Before"),
                ComparisonBoard.Item(
                    asset: RenderedAsset(cgImage: second, profile: .sRGB), label: "After"),
            ],
            layout: .slider,
            size: size,
            background: .card,
            showsFooter: showsFooter,
            dividerPercent: dividerPercent)
    }

    private func makeDraft(renderScale: CGFloat = 1) throws -> ComparisonBoardDraft {
        var colors = [red, blue]
        return try ComparisonBoardDraft(
            captures: ["a", "b"].map {
                Capture(code: $0, languageID: "swift", themeID: "one-dark")
            },
            baseConfig: SnapshotConfig(),
            profile: .sRGB,
            renderScale: renderScale,
            render: { _, _, _ in solid(colors.removeFirst()) })
    }

    private func solid(_ color: CGColor, width: Int = 800, height: Int = 500) -> CGImage {
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
}
