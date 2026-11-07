import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@Suite("Comparison board viewport")
struct ComparisonBoardViewportTests {
    @Test func wholeFramesTheBoard() {
        #expect(ComparisonBoardViewport.whole.rect == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(
            ComparisonBoardViewport.whole.pixelRect(width: 640, height: 360)
                == CGRect(x: 0, y: 0, width: 640, height: 360))
    }

    @Test func zoomAndCenterStayInsideTheBoard() {
        let corner = ComparisonBoardViewport(zoom: 2, center: CGPoint(x: -3, y: 5))
        #expect(corner.rect == CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
        #expect(ComparisonBoardViewport(zoom: 0.1).zoom == 1)
        #expect(ComparisonBoardViewport(zoom: 99).zoom == 4)
        #expect(ComparisonBoardViewport(zoom: .nan).zoom == 1)
        #expect(
            ComparisonBoardViewport(zoom: 2, center: CGPoint(x: CGFloat.nan, y: .infinity)).center
                == CGPoint(x: 0.5, y: 0.5))
    }

    /// Whatever a viewport holds, its crop is a nonempty part of the board image.
    @Test(arguments: [
        (CGFloat(1), CGPoint(x: 0.5, y: 0.5)), (4, CGPoint(x: 1, y: 1)), (4, CGPoint(x: 0, y: 0)),
        (3.7, CGPoint(x: 0.99, y: 0.01)), (.infinity, CGPoint(x: -1, y: 2)),
        (-2, CGPoint(x: CGFloat.nan, y: CGFloat.nan)),
    ])
    func pixelRectNeverLeavesTheImage(_ zoom: CGFloat, _ center: CGPoint) {
        for (width, height) in [(1, 1), (3, 7), (641, 359), (1600, 1000)] {
            let rect = ComparisonBoardViewport(zoom: zoom, center: center)
                .pixelRect(width: width, height: height)
            #expect(rect.width >= 1 && rect.height >= 1)
            #expect(CGRect(x: 0, y: 0, width: width, height: height).contains(rect))
            #expect(rect == rect.integral)
        }
        #expect(ComparisonBoardViewport.whole.pixelRect(width: 0, height: 10) == .zero)
    }

    @Test func slidersReadAndWritePercent() {
        let zoomed = ComparisonBoardViewport.whole.setting(.zoom, percent: 200)
        #expect(zoomed.percent(.zoom) == 200)
        let moved = zoomed.setting(.horizontal, percent: 10).setting(.vertical, percent: 90)
        #expect(moved.percent(.horizontal) == 25)
        #expect(moved.percent(.vertical) == 75)
        // At zoom 1 the whole board is framed, so there is nowhere to move.
        #expect(ComparisonBoardViewport.whole.setting(.horizontal, percent: 0).center.x == 0.5)
    }
}

@MainActor
@Suite("Comparison board scenes")
struct ComparisonBoardScenesTests {
    @Test func addSceneSavesTheCurrentView() throws {
        let draft = try makeDraft()
        draft.addSceneFromView()
        draft.camera = ComparisonBoardViewport(zoom: 2, center: CGPoint(x: 0.25, y: 0.25))
        draft.addSceneFromView()

        #expect(draft.scenes.map(\.viewport) == [.whole, draft.camera])
        #expect(draft.scenes.map(\.name) == ["Scene 1", "Scene 2"])
        #expect(draft.scenes.allSatisfy { $0.seconds == ComparisonBoardScene.defaultDuration })
    }

    @Test func scenesReorderRenameRetimeAndDelete() throws {
        let draft = try makeDraft()
        for _ in 0..<3 { draft.addSceneFromView() }
        let ids = draft.scenes.map(\.id)

        draft.moveScene(id: ids[2], offset: -1)
        draft.moveScene(id: ids[0], offset: -1)
        #expect(draft.scenes.map(\.id) == [ids[0], ids[2], ids[1]])

        draft.renameScene(id: ids[0], to: String(repeating: "a", count: 90))
        #expect(draft.scenes[0].name.count == ComparisonBoard.maximumLabelLength)
        draft.setSeconds(0, forScene: ids[0])
        #expect(draft.scenes[0].seconds == 1)
        draft.setSeconds(600, forScene: ids[1])
        #expect(draft.scenes.first { $0.id == ids[1] }?.seconds == 60)

        draft.removeScene(id: ids[2])
        #expect(draft.scenes.map(\.id) == [ids[0], ids[1]])
    }

    @Test func sceneCountIsBounded() throws {
        let draft = try makeDraft()
        for _ in 0..<(ComparisonBoardScene.maximumCount + 3) { draft.addSceneFromView() }
        #expect(draft.scenes.count == ComparisonBoardScene.maximumCount)
        #expect(!draft.canAddScene)
    }

    /// Scenes crop the composed board, so they hold its finished pixels and nothing else.
    @Test func sceneImagesAreCropsOfTheBoardExport() throws {
        let draft = try makeDraft()
        draft.camera = ComparisonBoardViewport(zoom: 3, center: CGPoint(x: 0.8, y: 0.3))
        draft.addSceneFromView()
        draft.camera = ComparisonBoardViewport(zoom: 99, center: CGPoint(x: 7, y: -7))
        draft.addSceneFromView()
        draft.camera = .whole
        draft.addSceneFromView()

        let board = try draft.compose(scale: draft.resolvedExportScale, profile: .sRGB).cgImage
        let boardPixels = rgba(board)
        let images = try ComparisonBoardExporter.sceneImagesChecked(for: draft, profile: .sRGB)

        #expect(images.count == 3)
        for (scene, image) in zip(draft.scenes, images) {
            let rect = scene.viewport.pixelRect(width: board.width, height: board.height)
            #expect(image.width == Int(rect.width) && image.height == Int(rect.height))
            #expect(rgba(image) == region(rect, of: boardPixels, width: board.width))
        }
        #expect(images[2].width == board.width && images[2].height == board.height)
    }

    @Test func pdfHasOnePageOfPixelsPerScene() throws {
        let draft = try makeDraft()
        draft.addSceneFromView()
        draft.camera = ComparisonBoardViewport(zoom: 2, center: CGPoint(x: 0, y: 1))
        draft.addSceneFromView()
        let images = try ComparisonBoardExporter.sceneImagesChecked(for: draft, profile: .sRGB)

        let data = try ComparisonBoardExporter.scenePDFChecked(for: draft, profile: .sRGB)

        #expect((try #require(PDFDocument(data: data)).string ?? "").isEmpty)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages == images.count)
        for (index, image) in images.enumerated() {
            let page = try #require(document.page(at: index + 1))
            let box = page.getBoxRect(.mediaBox)
            #expect(box.width == CGFloat(image.width) / draft.resolvedExportScale)
            #expect(box.height == CGFloat(image.height) / draft.resolvedExportScale)
        }
    }

    @Test func pngsAreWrittenInSceneOrderWithoutReplacing() throws {
        let draft = try makeDraft()
        draft.addSceneFromView()
        draft.camera = ComparisonBoardViewport(zoom: 4)
        draft.addSceneFromView()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent("scene-01.png"))
        let images = try ComparisonBoardExporter.sceneImagesChecked(for: draft, profile: .sRGB)

        var written: [(String, CGSize)] = []
        let count = try ComparisonBoardExporter.writeScenePNGs(
            for: draft, profile: .sRGB, to: directory
        ) { data, url in
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(CGImageSourceGetType(source) as String? == "public.png")
            written.append(
                (url.lastPathComponent, CGSize(width: image.width, height: image.height)))
        }

        #expect(count == 2)
        #expect(written.map(\.0) == ["scene-01-2.png", "scene-02.png"])
        #expect(
            written.map(\.1) == images.map { CGSize(width: $0.width, height: $0.height) })
    }

    @Test func noScenesExportNothing() throws {
        let draft = try makeDraft()
        #expect(try ComparisonBoardExporter.sceneImagesChecked(for: draft, profile: .sRGB).isEmpty)
        #expect(throws: RenderBudgetError.encodingFailed) {
            try ComparisonBoardExporter.scenePDFChecked(for: draft, profile: .sRGB)
        }
    }

    @Test func scenesLeaveTheBoardExportUnchanged() throws {
        let draft = try makeDraft()
        let before = try ComparisonBoardExporter.encodedPayloadChecked(
            for: draft, format: .png, profile: .sRGB)
        draft.camera = ComparisonBoardViewport(zoom: 2, center: CGPoint(x: 0.1, y: 0.9))
        draft.addSceneFromView()

        let after = try ComparisonBoardExporter.encodedPayloadChecked(
            for: draft, format: .png, profile: .sRGB)
        #expect(after.data == before.data)
    }

    private func makeDraft() throws -> ComparisonBoardDraft {
        try ComparisonBoardDraft(
            captures: [
                Capture(code: "before", languageID: "swift", themeID: "one-dark"),
                Capture(code: "after", languageID: "swift", themeID: "one-dark"),
            ],
            baseConfig: SnapshotConfig(), profile: .sRGB, renderScale: 2,
            render: { config, _, _ in Self.gradient(seed: config.code == "before" ? 40 : 200) })
    }

    private static func gradient(seed: UInt8) -> CGImage {
        let width = 320
        let height = 180
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8(x * 255 / width)
                bytes[offset + 1] = UInt8(y * 255 / height)
                bytes[offset + 2] = seed
            }
        }
        let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    private func region(_ rect: CGRect, of pixels: [UInt8], width: Int) -> [UInt8] {
        var out: [UInt8] = []
        for row in Int(rect.minY)..<Int(rect.maxY) {
            let start = (row * width + Int(rect.minX)) * 4
            out += pixels[start..<(start + Int(rect.width) * 4)]
        }
        return out
    }
}
