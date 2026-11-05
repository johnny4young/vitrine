import AppKit
import Foundation
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@MainActor
@Suite("Preset thumbnails")
struct PresetThumbnailTests {
    private final class RenderLog {
        var configs: [SnapshotConfig] = []
        var result: CGImage? = PresetThumbnailTests.pixel()
    }

    private static func pixel() -> CGImage? {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return context?.makeImage()
    }

    private func model(_ log: RenderLog, quietWindow: Duration = .zero) -> PresetThumbnailModel {
        PresetThumbnailModel(quietWindow: quietWindow, frameGap: .zero) { config in
            log.configs.append(config)
            return log.result
        }
    }

    private var tiles: [PresetThumbnailModel.Tile] {
        StylePreset.builtIns.map {
            PresetThumbnailModel.Tile(preset: $0, theme: Theme.theme(withID: $0.style.themeID))
        }
    }

    private func excerpt(
        _ code: String, language: Language = .swift,
        _ edit: (inout SnapshotConfig) -> Void = { _ in }
    ) -> SnapshotConfig {
        var style = SnapshotConfig()
        style.language = language
        edit(&style)
        return PresetThumbnailModel.excerpt(
            of: PresetThumbnailModel.source(style: style, code: code))
    }

    // MARK: - Excerpt

    @Test func theExcerptIsBoundedForAnyDocument() {
        let long = String(repeating: "x", count: 1_000_000)
        let code = (1...100).map { "line \($0) \(long.prefix(200))" }.joined(separator: "\n")
        let rows = excerpt(code).code.components(separatedBy: "\n")
        #expect(rows.count < 10)
        #expect(rows.allSatisfy { $0.count < 100 })
        #expect(rows[0].hasPrefix("line 1 "))

        let oneLine = excerpt(long).code
        #expect(oneLine.count < 100)
    }

    @Test func aRedactedRowLosesItsTextBeforeTheRenderer() {
        let code = "let a = 1\nlet secret = \"hunter2\"\nlet b = 2"
        let result = excerpt(code) { $0.redactedLineRanges = [2...2] }
        #expect(!result.code.contains("hunter2"))
        #expect(
            result.code.components(separatedBy: "\n")[1] == SnapshotConfig.redactedLinePlaceholder)
        #expect(result.redactedLineRanges == [2...2])
    }

    @Test func redactionStaysOnItsRowInACRLFDocument() {
        let code = "let a = 1\r\nlet secret = \"hunter2\"\r\nlet b = 2"
        let result = excerpt(code) { $0.redactedLineRanges = [2...2] }
        #expect(!result.code.contains("hunter2"))
        #expect(result.code.contains("let a = 1"))
        #expect(result.code.contains("let b = 2"))
        #expect(!result.code.contains("\r"))
    }

    @Test func aTerminalRedactionAddressesTheFinalScreenRow() {
        // The carriage return redraws row 1, so raw transcript text never reaches the excerpt.
        let code = "hidden\rvisible\nrow two secret\nthird"
        let result = excerpt(code, language: .terminal) { $0.redactedLineRanges = [2...2] }
        #expect(!result.code.contains("secret"))
        #expect(result.code.components(separatedBy: "\n")[0] == "visible")
        #expect(!result.code.contains("hidden"))
    }

    @Test func aBlurBoxMasksEveryRowAndAnyImage() {
        let blur = Annotation(
            kind: .blur, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.2, y: 0.2))
        let code = excerpt("let secret = \"hunter2\"") { $0.annotations = [blur] }
        #expect(!code.code.contains("hunter2"))
        #expect(code.annotations.isEmpty)
        #expect(code.redactedLineRanges == [1...3])

        let image = excerpt("") {
            $0.annotations = [blur]
            $0.foregroundImage = ImageReference(fileName: "private.png")
        }
        #expect(image.foregroundImage == nil)
    }

    @Test func otherAnnotationsAndLabelsNeverReachAThumbnail() {
        var style = SnapshotConfig()
        var callout = Annotation(
            kind: .text, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.2, y: 0.2))
        callout.text = "private note"
        style.annotations = [callout]
        style.windowTitle = "secrets.env"
        style.metadata.title = "Private title"
        let result = PresetThumbnailModel.excerpt(
            of: PresetThumbnailModel.source(style: style, code: "let x = 1"))
        #expect(result.annotations.isEmpty)
        #expect(result.windowTitle.isEmpty)
        #expect(result.metadata.isEmpty)
        #expect(result.code == "let x = 1")
    }

    @Test func anOversizedTerminalIsMaskedWithoutParsing() {
        let code = String(repeating: "secret\n", count: 20_000)
        let result = excerpt(code, language: .terminal)
        #expect(!result.code.contains("secret"))
        #expect(result.language == .plaintext)
    }

    @Test func anEmptyDocumentShowsTheStagesSample() {
        #expect(excerpt(" \n ").code == EditorPreview.sampleCode)
        #expect(excerpt("").code == EditorPreview.sampleCode)
    }

    @Test func anImageCaptureKeepsItsImageAndFrame() {
        let reference = ImageReference(fileName: "capture.png")
        let result = excerpt("") {
            $0.foregroundImage = reference
            $0.imageFrame = .macOSWindow
        }
        #expect(result.foregroundImage == reference)
        #expect(result.imageFrame == .macOSWindow)
        #expect(result.code.isEmpty)
    }

    @Test func rangesPastTheExcerptAreDropped() {
        let code = (1...20).map { "let v\($0) = \($0)" }.joined(separator: "\n")
        let result = excerpt(code) {
            $0.highlightedLineRanges = [5...12, 15...16]
            $0.redactedLineRanges = [6...30]
        }
        #expect(result.highlightedLineRanges == [5...6])
        #expect(result.redactedLineRanges == [6...6])
    }

    // MARK: - Pixels

    private func pixels(_ image: CGImage?) -> Data? {
        image?.dataProvider?.data as Data?
    }

    @Test func redactedTextCannotChangeARenderedThumbnail() throws {
        func render(_ secret: String, redacted: Bool) throws -> CGImage {
            var config = excerpt("let a = 1\nlet key = \"\(secret)\"\nlet b = 2") {
                $0.redactedLineRanges = redacted ? [2...2] : []
            }
            StylePreset.aurora.style.apply(to: &config)
            return try #require(
                ExportManager.renderThumbnail(config, pixels: PresetThumbnailModel.pixelSize))
        }
        let first = try render("AAAAAAAAAAAAAAAA", redacted: true)
        let second = try render("MMMMMMMMMMMMMMMM", redacted: true)
        #expect(pixels(first) == pixels(second))

        let exposed = try render("AAAAAAAAAAAAAAAA", redacted: false)
        #expect(pixels(first) != pixels(exposed))
    }

    @Test func aThumbnailHasTheTilesExactProportions() throws {
        var config = excerpt("let a = 1")
        StylePreset.midnight.style.apply(to: &config) { Theme.theme(withID: $0) }
        let image = try #require(
            ExportManager.renderThumbnail(config, pixels: PresetThumbnailModel.pixelSize))
        #expect(abs(CGFloat(image.width) - PresetThumbnailModel.pixelSize.width) <= 1)
        #expect(abs(CGFloat(image.height) - PresetThumbnailModel.pixelSize.height) <= 1)
    }

    @Test func eachPresetLooksDifferent() {
        let images = tiles.map { tile -> Data? in
            var config = excerpt("let a = 1")
            tile.preset.style.apply(to: &config) { _ in tile.theme }
            return pixels(
                ExportManager.renderThumbnail(config, pixels: PresetThumbnailModel.pixelSize))
        }
        #expect(!images.contains(nil))
        #expect(Set(images).count == tiles.count)
    }

    @Test func aBlurBoxMakesTheHiddenTextUnableToChangeAThumbnail() throws {
        let blur = Annotation(
            kind: .blur, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.2, y: 0.2))
        func render(_ secret: String) throws -> CGImage {
            var config = excerpt("let key = \"\(secret)\"") { $0.annotations = [blur] }
            StylePreset.aurora.style.apply(to: &config)
            return try #require(
                ExportManager.renderThumbnail(config, pixels: PresetThumbnailModel.pixelSize))
        }
        #expect(pixels(try render("AAAAAAAA")) == pixels(try render("MMMMMMMM")))
    }

    @Test func anImageCaptureRendersItsImageUnlessABlurBoxHidesIt() throws {
        let store = BackgroundImageStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("PresetThumbnails-\(UUID().uuidString)", isDirectory: true))
        func reference(_ color: NSColor) throws -> ImageReference {
            let image = NSImage(size: CGSize(width: 40, height: 40))
            image.lockFocus()
            color.setFill()
            NSRect(x: 0, y: 0, width: 40, height: 40).fill()
            image.unlockFocus()
            return try store.importImage(
                data: try #require(image.tiffRepresentation), preferredExtension: "tiff")
        }
        func render(_ reference: ImageReference, blurred: Bool) throws -> CGImage {
            var config = excerpt("") {
                $0.foregroundImage = reference
                if blurred {
                    $0.annotations = [
                        Annotation(
                            kind: .blur, start: CGPoint(x: 0.1, y: 0.1),
                            end: CGPoint(x: 0.2, y: 0.2))
                    ]
                }
            }
            StylePreset.aurora.style.apply(to: &config)
            return try #require(
                ExportManager.renderThumbnail(
                    config, pixels: PresetThumbnailModel.pixelSize, foregroundImageStore: store))
        }
        let red = try reference(.red)
        let blue = try reference(.blue)
        #expect(pixels(try render(red, blurred: false)) != pixels(try render(blue, blurred: false)))
        #expect(pixels(try render(red, blurred: true)) == pixels(try render(blue, blurred: true)))
    }

    // MARK: - Refresh

    @Test func aSettleRendersEachTileOnceAndThenNothing() async {
        let log = RenderLog()
        let model = model(log)
        let source = PresetThumbnailModel.source(style: SnapshotConfig(), code: "let a = 1")
        await model.refresh(source: source, tiles: tiles)
        #expect(log.configs.count == tiles.count)
        #expect(model.images.count == tiles.count)

        await model.refresh(source: source, tiles: tiles)
        #expect(log.configs.count == tiles.count)
    }

    @Test func anEditOutsideTheExcerptRendersNothing() async {
        let log = RenderLog()
        let model = model(log)
        let head = (1...6).map { "let v\($0) = \($0)" }.joined(separator: "\n")
        await model.refresh(
            source: PresetThumbnailModel.source(style: SnapshotConfig(), code: head),
            tiles: tiles)
        let count = log.configs.count

        await model.refresh(
            source: PresetThumbnailModel.source(
                style: SnapshotConfig(), code: head + "\nlet below = 1"),
            tiles: tiles)
        #expect(log.configs.count == count)
    }

    @Test func styleTicksDoNotChangeTheSource() {
        var ticked = SnapshotConfig()
        ticked.padding = 80
        ticked.fontSize = 20
        ticked.theme = .dracula
        ticked.background = .gradient(.forest)
        ticked.annotations = [
            Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 1, y: 1))
        ]
        #expect(
            PresetThumbnailModel.source(style: ticked, code: "x")
                == PresetThumbnailModel.source(style: SnapshotConfig(), code: "x"))
    }

    @Test func anEditedCustomThemeRerendersOnlyItsTile() async throws {
        let log = RenderLog()
        let model = model(log)
        let source = PresetThumbnailModel.source(style: SnapshotConfig(), code: "let a = 1")
        func custom(_ background: String) throws -> Theme {
            Theme(
                id: "custom.tile", displayName: "Tile",
                palette: ThemePalette(
                    background: try #require(HexColor(background)),
                    foreground: try #require(HexColor("#000000"))))
        }
        let saved = StylePreset(
            name: "Saved",
            style: StyleSnapshot(themeID: "custom.tile", background: .gradient(.ocean)))
        await model.refresh(
            source: source,
            tiles: tiles + [PresetThumbnailModel.Tile(preset: saved, theme: try custom("#FFFFFF"))])
        log.configs = []

        await model.refresh(
            source: source,
            tiles: tiles + [PresetThumbnailModel.Tile(preset: saved, theme: try custom("#EEEEEE"))])
        #expect(log.configs.count == 1)
        #expect(log.configs.first?.theme.id == "custom.tile")
    }

    @Test func aDeletedPresetLeavesTheModel() async {
        let log = RenderLog()
        let model = model(log)
        let source = PresetThumbnailModel.source(style: SnapshotConfig(), code: "let a = 1")
        await model.refresh(source: source, tiles: tiles)
        await model.refresh(source: source, tiles: Array(tiles.prefix(1)))
        #expect(Set(model.images.keys) == [tiles[0].id])
    }

    @Test func aNewRedactionHidesTheTilesBeforeTheQuietWindow() async {
        let model = model(RenderLog())
        let code = "let a = 1\nlet key = 2"
        let tiles = tiles
        await model.refresh(
            source: PresetThumbnailModel.source(style: SnapshotConfig(), code: code), tiles: tiles)
        #expect(model.images.count == tiles.count)

        model.quietWindow = .seconds(60)
        var redacted = SnapshotConfig()
        redacted.redactedLineRanges = [2...2]
        let source = PresetThumbnailModel.source(style: redacted, code: code)
        let task = Task { await model.refresh(source: source, tiles: tiles) }
        for _ in 0..<10 { await Task.yield() }
        #expect(model.images.isEmpty)
        task.cancel()
        await task.value
    }

    @Test func aFirstBlurBoxHidesTilesWhoseRedactionsHappenToMatchTheMask() async {
        let model = model(RenderLog())
        let code = (1...6).map { "let v\($0) = \($0)" }.joined(separator: "\n")
        let tiles = tiles
        var style = SnapshotConfig()
        style.redactedLineRanges = [1...3]
        await model.refresh(
            source: PresetThumbnailModel.source(style: style, code: code), tiles: tiles)
        #expect(model.images.count == tiles.count)

        model.quietWindow = .seconds(60)
        style.annotations = [
            Annotation(kind: .blur, start: .zero, end: CGPoint(x: 0.5, y: 0.5))
        ]
        let source = PresetThumbnailModel.source(style: style, code: code)
        let task = Task { await model.refresh(source: source, tiles: tiles) }
        for _ in 0..<10 { await Task.yield() }
        #expect(model.images.isEmpty)
        task.cancel()
        await task.value
    }

    @Test func aFailedRenderDropsTheOldImage() async {
        let log = RenderLog()
        let model = model(log)
        await model.refresh(
            source: PresetThumbnailModel.source(style: SnapshotConfig(), code: "one"),
            tiles: tiles)
        log.result = nil
        await model.refresh(
            source: PresetThumbnailModel.source(style: SnapshotConfig(), code: "two"),
            tiles: tiles)
        #expect(model.images.isEmpty)
    }

    @Test func cancellationStopsBeforeTheNextTile() async {
        let log = RenderLog()
        let model = model(log)
        let tiles = tiles
        let source = PresetThumbnailModel.source(style: SnapshotConfig(), code: "let a = 1")
        let task = Task { await model.refresh(source: source, tiles: tiles) }
        task.cancel()
        await task.value
        #expect(log.configs.isEmpty)
    }

    // MARK: - Boundaries

    @Test func selectionFollowsTheStyleAndIgnoresAnImageBackground() {
        var style = SnapshotConfig()
        StylePreset.aurora.style.apply(to: &style)
        #expect(PresetThumbnailModel.selection(style: style, tiles: tiles) == ["builtin.aurora"])

        style.padding += 4
        #expect(PresetThumbnailModel.selection(style: style, tiles: tiles).isEmpty)

        style.padding -= 4
        style.background = .image(ImageBackground(reference: ImageReference(fileName: "a.png")))
        #expect(PresetThumbnailModel.selection(style: style, tiles: tiles).isEmpty)
    }
}
