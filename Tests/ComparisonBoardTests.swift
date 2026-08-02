import CoreGraphics
import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Comparison boards")
struct ComparisonBoardTests {
    @Test func itemCountStaysWithinThePortableContract() throws {
        #expect(throws: ComparisonBoard.ValidationError.itemCount(1)) {
            try ComparisonBoard(items: [item(label: "Only")])
        }
        #expect(throws: ComparisonBoard.ValidationError.itemCount(5)) {
            try ComparisonBoard(
                items: (1...5).map { item(label: "Capture \($0)") })
        }
    }

    @Test func captionsAreTrimmedAndEmptyDetailsAreRemoved() throws {
        let board = try ComparisonBoard(items: [
            item(label: "  Before  ", detail: "  main  "),
            item(label: "After", detail: "   "),
        ])

        #expect(board.items[0].label == "Before")
        #expect(board.items[0].detail == "main")
        #expect(board.items[1].detail == nil)
    }

    @Test func captionsRejectEmptyMultilineAndOversizedValues() {
        #expect(throws: ComparisonBoard.ValidationError.emptyLabel(index: 0)) {
            try ComparisonBoard(items: [item(label: "  "), item(label: "After")])
        }
        #expect(throws: ComparisonBoard.ValidationError.multilineCaption(index: 1)) {
            try ComparisonBoard(items: [item(label: "Before"), item(label: "After\nNow")])
        }
        #expect(throws: ComparisonBoard.ValidationError.labelTooLong(index: 0)) {
            try ComparisonBoard(items: [
                item(label: String(repeating: "a", count: 49)), item(label: "After"),
            ])
        }
        #expect(throws: ComparisonBoard.ValidationError.detailTooLong(index: 1)) {
            try ComparisonBoard(items: [
                item(label: "Before"),
                item(label: "After", detail: String(repeating: "b", count: 81)),
            ])
        }
    }

    @Test func automaticLayoutUsesOneRowUntilFourItems() throws {
        let two = try board(count: 2)
        let three = try board(count: 3)
        let four = try board(count: 4)

        #expect(ComparisonBoardComposer.metrics(for: two).columns == 2)
        #expect(ComparisonBoardComposer.metrics(for: two).rows == 1)
        #expect(ComparisonBoardComposer.metrics(for: three).columns == 3)
        #expect(ComparisonBoardComposer.metrics(for: three).rows == 1)
        #expect(ComparisonBoardComposer.metrics(for: four).columns == 2)
        #expect(ComparisonBoardComposer.metrics(for: four).rows == 2)
    }

    @Test func explicitLayoutsResolveDeterministically() throws {
        let horizontal = try board(count: 4, layout: .horizontal)
        let vertical = try board(count: 4, layout: .vertical)
        let grid = try board(count: 3, layout: .grid)

        #expect(ComparisonBoardComposer.metrics(for: horizontal).columns == 4)
        #expect(ComparisonBoardComposer.metrics(for: horizontal).rows == 1)
        #expect(ComparisonBoardComposer.metrics(for: vertical).columns == 1)
        #expect(ComparisonBoardComposer.metrics(for: vertical).rows == 4)
        #expect(ComparisonBoardComposer.metrics(for: grid).columns == 2)
        #expect(ComparisonBoardComposer.metrics(for: grid).rows == 2)
    }

    @Test func renderedDimensionsFollowMetricsAndScale() throws {
        let board = try board(count: 3)
        let metrics = ComparisonBoardComposer.metrics(for: board)
        let oneX = try ComparisonBoardComposer.compose(board, scale: 1, profile: .sRGB)
        let twoX = try ComparisonBoardComposer.compose(board, scale: 2, profile: .displayP3)

        #expect(abs(CGFloat(oneX.pixelWidth) - metrics.pointSize.width) <= 1)
        #expect(abs(CGFloat(oneX.pixelHeight) - metrics.pointSize.height) <= 1)
        #expect(abs(CGFloat(twoX.pixelWidth) - metrics.pointSize.width * 2) <= 1)
        #expect(abs(CGFloat(twoX.pixelHeight) - metrics.pointSize.height * 2) <= 1)
        #expect(oneX.profile == .sRGB)
        #expect(twoX.profile == .displayP3)
    }

    @Test func differentlyShapedCapturesKeepTheSameBoardDimensions() throws {
        let portrait = try ComparisonBoard(items: [
            item(width: 160, height: 360, label: "Before"),
            item(width: 900, height: 220, label: "After"),
        ])
        let landscape = try ComparisonBoard(items: [
            item(width: 900, height: 220, label: "Before"),
            item(width: 900, height: 220, label: "After"),
        ])

        let first = try ComparisonBoardComposer.compose(portrait, scale: 1)
        let second = try ComparisonBoardComposer.compose(landscape, scale: 1)
        #expect(first.pixelSize == second.pixelSize)
    }

    @Test func scaleMustBeFiniteAndWithinTheSupportedRange() throws {
        let value = try board(count: 2)
        for scale in [CGFloat.zero, 4, .nan, .infinity] {
            #expect(throws: ComparisonBoardComposer.CompositionError.invalidScale) {
                try ComparisonBoardComposer.compose(value, scale: scale)
            }
        }
    }

    @Test func finishedBoardUsesTheSharedEncoders() throws {
        let asset = try ComparisonBoardComposer.compose(board(count: 2), scale: 1)

        #expect(ExportManager.pngData(from: asset.cgImage)?.isEmpty == false)
        #expect(ExportManager.pdfData(from: asset.cgImage)?.isEmpty == false)
    }

    @Test func recordRepresentativeBoardWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["VITRINE_RECORD_COMPARISON_BOARD"] == "1"
        else { return }

        let board = try ComparisonBoard(items: [
            item(
                width: 900,
                height: 480,
                color: CGColor(red: 0.22, green: 0.18, blue: 0.48, alpha: 1),
                label: "Before",
                detail: "Initial capture"),
            item(
                width: 900,
                height: 480,
                color: CGColor(red: 0.08, green: 0.48, blue: 0.56, alpha: 1),
                label: "After",
                detail: "Refined capture"),
        ])
        let asset = try ComparisonBoardComposer.compose(board, scale: 1)
        let data = try #require(ExportManager.pngData(from: asset.cgImage))
        let output = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vitrine-comparison-board-core.png")
        try data.write(to: output, options: .atomic)
        print("COMPARISON BOARD OUTPUT \(output.path)")
    }

    private func board(
        count: Int,
        layout: ComparisonBoard.Layout = .automatic
    ) throws -> ComparisonBoard {
        try ComparisonBoard(
            items: (1...count).map { item(label: "Capture \($0)") },
            layout: layout)
    }

    private func item(
        width: Int = 320,
        height: Int = 180,
        color: CGColor = CGColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1),
        label: String,
        detail: String? = nil
    ) -> ComparisonBoard.Item {
        ComparisonBoard.Item(
            asset: RenderedAsset(
                cgImage: solidImage(width: width, height: height, color: color),
                profile: .sRGB),
            label: label,
            detail: detail)
    }

    private func solidImage(width: Int, height: Int, color: CGColor) -> CGImage {
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
