import AppKit
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@Suite("Every-size board")
@MainActor
struct EverySizeBoardTests {
    private func config(lines: Int) -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = (1...lines).map { "let value\($0) = compute(\($0))" }.joined(separator: "\n")
        return config
    }

    private func png(_ config: SnapshotConfig, _ preset: ExportPreset) throws -> Data {
        var applied = config
        preset.apply(to: &applied)
        let image = try #require(
            ExportManager.renderCGImage(applied, scale: 1, fixedSize: preset.sizing.fixedSize))
        return try #require(ExportManager.pngData(from: image))
    }

    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineEverySize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Crop geometry

    @Test func contentThatFitsIsNeverReframed() {
        #expect(
            FocalCrop.crop(
                natural: CGSize(width: 600, height: 400), frame: CGSize(width: 1200, height: 630),
                focal: CGPoint(x: 1, y: 1), wrapsToWidth: true) == nil)
    }

    @Test func tallContentKeepsTheFocalPointInView() throws {
        let natural = CGSize(width: 800, height: 1500)
        let frame = CGSize(width: 1200, height: 600)
        func origin(_ y: CGFloat) throws -> CGPoint {
            try #require(
                FocalCrop.crop(
                    natural: natural, frame: frame, focal: CGPoint(x: 0.5, y: y),
                    wrapsToWidth: true)
            ).origin
        }
        #expect(try origin(0) == CGPoint(x: 0, y: 0))
        #expect(try origin(0.5) == CGPoint(x: 0, y: 450))
        #expect(try origin(1) == CGPoint(x: 0, y: 900))
        #expect(try origin(0.3) == CGPoint(x: 0, y: 150))
        let crop = try #require(
            FocalCrop.crop(
                natural: natural, frame: frame, focal: .zero, wrapsToWidth: true))
        #expect(crop.canvasSize == CGSize(width: 1200, height: 1500))
    }

    @Test func codeWiderThanTheFrameWrapsInsteadOfCropping() {
        #expect(
            FocalCrop.crop(
                natural: CGSize(width: 1400, height: 2000),
                frame: CGSize(width: 1080, height: 1920),
                focal: CGPoint(x: 0.5, y: 0.5), wrapsToWidth: true) == nil)
    }

    @Test func anImageWiderThanTheFrameCropsAcross() throws {
        let crop = try #require(
            FocalCrop.crop(
                natural: CGSize(width: 1300, height: 700), frame: CGSize(width: 1080, height: 1920),
                focal: CGPoint(x: 1, y: 0.5), wrapsToWidth: false))
        #expect(crop.canvasSize == CGSize(width: 1300, height: 1920))
        #expect(crop.origin == CGPoint(x: 220, y: 0))
    }

    @Test func tileGeometryRoundTripsTheFocalPoint() throws {
        let natural = CGSize(width: 800, height: 1500)
        let frame = CGSize(width: 1200, height: 600)
        let focal = CGPoint(x: 0.25, y: 0.6)
        let geometry = FocalTileGeometry(
            frame: frame, natural: natural,
            crop: FocalCrop.crop(natural: natural, frame: frame, focal: focal, wrapsToWidth: true))
        let point = geometry.point(for: focal)
        #expect(abs(point.y - frame.height / 2) < 1)
        let back = geometry.focal(at: point)
        #expect(abs(back.x - focal.x) < 0.001 && abs(back.y - focal.y) < 0.001)
        #expect(geometry.focal(at: CGPoint(x: -500, y: 5_000)) == CGPoint(x: 0, y: 1))
    }

    // MARK: - Rendering

    @Test func aFocalPointOnContentThatFitsKeepsEveryPixel() throws {
        let plain = config(lines: 3)
        var focused = plain
        focused.focalPoint = CGPoint(x: 0.1, y: 0.9)
        for preset in [ExportPreset.twitter, .instagramStory] {
            #expect(try png(focused, preset) == png(plain, preset))
        }
    }

    @Test func aFocalPointChoosesWhichPartOfTallCodeStaysInView() throws {
        let plain = config(lines: 60)
        var top = plain
        top.focalPoint = CGPoint(x: 0.5, y: 0)
        var bottom = plain
        bottom.focalPoint = CGPoint(x: 0.5, y: 1)

        let preset = ExportPreset.linkedIn
        let topData = try png(top, preset)
        #expect(topData != (try png(bottom, preset)))
        #expect(topData != (try png(plain, preset)))

        var applied = bottom
        preset.apply(to: &applied)
        let image = try #require(
            ExportManager.renderCGImage(applied, scale: 1, fixedSize: preset.sizing.fixedSize))
        #expect(image.width == 1200 && image.height == 628)
    }

    @Test func blurBoxesRefuseTheFocalPointSoNothingSlidesOutFromUnderThem() async throws {
        var plain = config(lines: 60)
        plain.annotations = [
            Annotation(kind: .blur, start: CGPoint(x: 0.2, y: 0.3), end: CGPoint(x: 0.8, y: 0.45))
        ]
        var focused = plain
        focused.focalPoint = CGPoint(x: 0.5, y: 1)
        #expect(FocalCrop.isBlocked(for: focused))

        let presets = [ExportPreset.linkedIn, .openGraph, .instagramStory]
        let plainDir = try tempDirectory()
        let focusedDir = try tempDirectory()
        defer {
            try? FileManager.default.removeItem(at: plainDir)
            try? FileManager.default.removeItem(at: focusedDir)
        }
        _ = await ExportManager.exportPresetSizes(plain, presets: presets, to: plainDir)
        _ = await ExportManager.exportPresetSizes(focused, presets: presets, to: focusedDir)
        for preset in presets {
            let name = "vitrine-\(preset.id).png"
            #expect(
                try Data(contentsOf: focusedDir.appendingPathComponent(name))
                    == Data(contentsOf: plainDir.appendingPathComponent(name)))
        }
    }

    @Test func anyMarkOrSlideCueBlocksTheFocalPoint() {
        var config = config(lines: 2)
        #expect(!FocalCrop.isBlocked(for: config))
        config.annotations = [
            Annotation(kind: .arrow, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.5, y: 0.5))
        ]
        #expect(FocalCrop.isBlocked(for: config))
        config.annotations = []
        config.slideCue = SlideCue(pageLabel: "1 / 2")
        #expect(FocalCrop.isBlocked(for: config))
    }

    @Test func multiSizeExportWritesTheFocalCrop() async throws {
        var focused = config(lines: 60)
        focused.focalPoint = CGPoint(x: 0.5, y: 1)
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let preset = ExportPreset.linkedIn

        _ = await ExportManager.exportPresetSizes(focused, presets: [preset], to: dir)

        #expect(
            try Data(contentsOf: dir.appendingPathComponent("vitrine-\(preset.id).png"))
                == png(focused, preset))
    }

    @Test func boardTilesUseTheExportCrop() async throws {
        var focused = config(lines: 60)
        focused.focalPoint = CGPoint(x: 0.5, y: 1)
        let model = EverySizeBoardModel(debounce: .zero)
        await model.render([.linkedIn], for: focused)
        let tile = try #require(model.tiles["linkedin"])
        let crop = try #require(tile.geometry.crop)
        #expect(crop.origin.y > 0)
        #expect(tile.geometry.frame == CGSize(width: 1200, height: 628))
        #expect(abs(tile.image.width - Int(EverySizeBoardModel.tilePixels)) <= 1)
    }

    @Test func codeWrappedByItsFrameTakesNoFocalPoint() async throws {
        var wide = SnapshotConfig()
        wide.code = String(repeating: "let wide = 1; ", count: 12)
        wide.focalPoint = CGPoint(x: 0.9, y: 0.5)
        let model = EverySizeBoardModel(debounce: .zero)
        await model.render([.instagramStory, .keynote], for: wide)

        let story = try #require(model.tiles["instagram-story"]).geometry
        #expect(story.natural.width > story.frame.width)
        #expect(story.crop == nil)
        #expect(!story.acceptsFocalPoint)
        #expect(try #require(model.tiles["keynote"]).geometry.acceptsFocalPoint)
    }

    @Test func anImageWiderThanItsFrameStillTakesAFocalPoint() {
        let geometry = FocalTileGeometry(
            frame: CGSize(width: 1080, height: 1920), natural: CGSize(width: 1300, height: 700),
            wrapsToWidth: false)
        #expect(geometry.acceptsFocalPoint)
    }

    // MARK: - Board model

    private static func stubImage() -> CGImage? {
        CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }

    /// Content 600 pt tall, so a 1200 × 628 frame reframes and a 1080 × 1920 one does not.
    private func renderer(
        measured: @escaping () -> Void = {},
        drawn: @escaping (ExportPreset) -> CGImage? = { _ in stubImage() }
    ) -> EverySizeBoardModel.Renderer {
        EverySizeBoardModel.Renderer(
            measure: { _ in
                measured()
                return CGSize(width: 600, height: 900)
            },
            draw: { _, preset, _ in drawn(preset) })
    }

    @Test func tilesRenderOncePerInput() async {
        var drawn: [String] = []
        var measured = 0
        let model = EverySizeBoardModel(
            debounce: .zero,
            renderer: renderer(
                measured: { measured += 1 },
                drawn: { preset in
                    drawn.append(preset.id)
                    return Self.stubImage()
                }))
        let presets = [ExportPreset.linkedIn, .instagramStory]
        let base = config(lines: 2)

        await model.render(presets, for: base)
        await model.render(presets, for: base)
        #expect(drawn == ["linkedin", "instagram-story"])
        #expect(Set(model.tiles.keys) == ["linkedin", "instagram-story"])

        // Only the size the point reframes is drawn again, and nothing is measured twice.
        var moved = base
        moved.focalPoint = CGPoint(x: 0.5, y: 0.2)
        await model.render(presets, for: moved)
        #expect(drawn == ["linkedin", "instagram-story", "linkedin"])
        #expect(measured == 2)
    }

    @Test func aFailedRenderRemovesTheStaleTile() async {
        var fails = false
        let model = EverySizeBoardModel(
            debounce: .zero, renderer: renderer(drawn: { _ in fails ? nil : Self.stubImage() }))
        await model.render([.linkedIn], for: config(lines: 2))
        #expect(model.tiles["linkedin"] != nil)

        fails = true
        await model.render([.linkedIn], for: config(lines: 3))
        #expect(model.tiles["linkedin"] == nil)
    }

    @Test func closingTheBoardStopsAtTheNextTile() async {
        var drawn = 0
        var task: Task<Void, Never>?
        let model = EverySizeBoardModel(
            debounce: .zero,
            renderer: renderer(drawn: { _ in
                drawn += 1
                task?.cancel()
                return Self.stubImage()
            }))
        let base = config(lines: 2)
        task = Task { await model.render(ExportPreset.all, for: base) }
        await task?.value
        #expect(drawn == 1)
    }

    @Test func aStoppedRunRendersNothingMore() async {
        var drawn = 0
        var model: EverySizeBoardModel?
        model = EverySizeBoardModel(
            debounce: .zero,
            renderer: renderer(drawn: { _ in
                drawn += 1
                model?.stop()
                return Self.stubImage()
            }))
        await model?.render(ExportPreset.all, for: config(lines: 2))
        #expect(drawn == 1)
    }

    @Test func aLongDocumentShowsSizesWithoutPictures() async {
        var drawn = 0
        let model = EverySizeBoardModel(
            debounce: .zero,
            renderer: renderer(drawn: { _ in
                drawn += 1
                return Self.stubImage()
            }))
        var long = SnapshotConfig()
        long.code = String(repeating: "x", count: EverySizeBoardModel.maximumRenderedBytes + 1)
        await model.render(ExportPreset.all, for: long)
        #expect(drawn == 0)
        #expect(model.tiles.isEmpty)
    }
}
