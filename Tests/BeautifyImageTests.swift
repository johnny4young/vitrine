import AppKit
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// "Beautify any image": dropping/pasting an arbitrary image renders it — optionally in a
/// window/browser frame — on the same background / padding / shadow the code path uses,
/// stored by reference like an image background. These pin the model, persistence, frame
/// gating, the foreground store, and that the image (and its frame) actually change pixels.
@MainActor
@Suite("Beautify any image")
struct BeautifyImageTests {
    // MARK: - Helpers

    /// An isolated foreground store in a unique temp directory, so import/resolve never
    /// touches the real app container.
    private func isolatedStore() -> BackgroundImageStore {
        BackgroundImageStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "VitrineForegroundTests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    /// A solid-color image of `size`, built at runtime so no image fixture lives in the repo.
    private func makeImageData(
        _ color: NSColor, _ size: CGSize, using fileType: NSBitmapImageRep.FileType
    ) throws -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        return try #require(rep.representation(using: fileType, properties: [:]))
    }

    /// A solid-color PNG of `size`, built at runtime so no image fixture lives in the repo.
    private func makePNG(_ color: NSColor, _ size: CGSize) throws -> Data {
        try makeImageData(color, size, using: .png)
    }

    /// Renders a config through the same `SnapshotCanvas` + `ImageRenderer` path the
    /// exporter uses, with `store` injected so a foreground reference resolves.
    private func png(
        _ config: SnapshotConfig, store: BackgroundImageStore,
        size: CGSize = CGSize(width: 360, height: 280)
    ) throws -> Data {
        let renderer = ImageRenderer(
            content: SnapshotCanvas(config: config, fixedSize: size)
                .environment(\.foregroundImageStore, store))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        let cg = try #require(renderer.cgImage)
        let normalized = ExportManager.normalized(cg, to: .sRGB)
        return try #require(ExportManager.pngData(from: normalized))
    }

    // MARK: - Model

    @Test func onlyAdvancedFramesArePro() {
        #expect(ImageFrame.none.isPro == false)
        #expect(ImageFrame.macOSWindow.isPro == false)
        #expect(ImageFrame.browser.isPro == true)
    }

    @Test func usesImageContentTracksTheForegroundImage() {
        var config = SnapshotConfig()
        #expect(config.usesImageContent == false)
        #expect(config.hasRenderableContent == false)
        config.foregroundImage = ImageReference(fileName: "abc.png")
        #expect(config.usesImageContent)
        #expect(config.hasRenderableContent)
    }

    @Test func imageContentDoesNotExportStaleCodeText() {
        var config = SnapshotConfig()
        config.code = "let stale = \"do not attach this to a photo\""
        config.foregroundImage = ImageReference(fileName: "photo.png")

        #expect(config.hasRenderableContent)
        #expect(config.sidecarText.isEmpty)
        #expect(config.richClipboardText.isEmpty)
    }

    @Test func clearContentMarksDropsTheForegroundImageButKeepsReusableFrame() {
        var config = SnapshotConfig()
        config.foregroundImage = ImageReference(fileName: "secret.png")
        config.imageFrame = .browser
        config.clearContentMarks()
        #expect(config.foregroundImage == nil)
        #expect(config.usesImageContent == false)
        // The frame is reusable style, not content, so it survives a new capture.
        #expect(config.imageFrame == .browser)
    }

    // MARK: - Persistence

    @Test func windowStateRoundTripsForegroundImageAndFrame() {
        var config = SnapshotConfig()
        config.foregroundImage = ImageReference(fileName: "deadbeef.png")
        config.imageFrame = .browser
        let restored = EditorWindowState(config: config).config()
        #expect(restored.foregroundImage == ImageReference(fileName: "deadbeef.png"))
        #expect(restored.imageFrame == .browser)
    }

    @Test func windowStateDefaultsToNoImageAndNoFrame() {
        let restored = EditorWindowState(config: SnapshotConfig()).config()
        #expect(restored.foregroundImage == nil)
        #expect(restored.imageFrame == .none)
    }

    @Test func makeDefaultDoesNotPromoteWorkingImageContent() {
        let defaults = UserDefaults(suiteName: "VitrineImageDefaultTests-\(UUID().uuidString)")!
        let sessionDefaults =
            UserDefaults(suiteName: "VitrineImageDefaultSession-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let session = AppSettings(defaults: sessionDefaults)
        session.config.code = "let working = \"do not seed future captures\""
        session.config.foregroundImage = ImageReference(fileName: "photo.png")
        session.config.imageFrame = .browser

        settings.makeDefault(from: session)

        #expect(settings.config.code.isEmpty)
        #expect(settings.config.foregroundImage == nil)
        #expect(settings.config.usesImageContent == false)
        #expect(settings.config.imageFrame == .browser)
    }

    // MARK: - Foreground store

    @Test func foregroundStoreImportsResolvesAndDedupesImageData() throws {
        let store = isolatedStore()
        let data = try makePNG(.systemBlue, CGSize(width: 24, height: 16))

        let reference = try store.importImage(data: data)
        #expect(store.image(for: reference) != nil)

        // Content-addressed: re-importing identical bytes returns the same reference.
        let again = try store.importImage(data: data)
        #expect(again == reference)
    }

    @Test func foregroundStoreRejectsNonImageData() {
        let store = isolatedStore()
        #expect(throws: BackgroundImageStore.ImportError.notAnImage) {
            _ = try store.importImage(data: Data("not an image".utf8))
        }
    }

    // MARK: - Rendering

    @Test func aBeautifiedImageRendersDifferentlyFromCode() throws {
        let store = isolatedStore()
        let reference = try store.importImage(
            data: makePNG(.systemPink, CGSize(width: 120, height: 80)))

        var code = SnapshotConfig()
        code.code = "let x = 1"

        var image = code
        image.foregroundImage = reference

        #expect(
            try png(code, store: store) != png(image, store: store),
            "rendering an image must differ from rendering code")
    }

    @Test func theFrameChangesTheRenderedPixels() throws {
        let store = isolatedStore()
        let reference = try store.importImage(
            data: makePNG(.systemGreen, CGSize(width: 120, height: 80)))

        var none = SnapshotConfig()
        none.foregroundImage = reference
        none.imageFrame = .none

        var window = none
        window.imageFrame = .macOSWindow

        #expect(
            try png(none, store: store) != png(window, store: store),
            "wrapping the image in a window frame must change the exported image")
    }

    @Test func aMissingForegroundImageDegradesInsteadOfBlanking() throws {
        let store = isolatedStore()
        var config = SnapshotConfig()
        // A reference the store cannot resolve (never imported).
        config.foregroundImage = ImageReference(fileName: "missing.png")
        // Rendering must still produce an image (the placeholder), not crash or fail.
        #expect(throws: Never.self) { _ = try png(config, store: store) }
    }

    // MARK: - Clipboard glue

    @Test func clipboardImageImportsToTheForegroundStore() throws {
        let store = isolatedStore()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("VitrineTest-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(
            try makePNG(.systemOrange, CGSize(width: 20, height: 20)), forType: .png)

        let reference = QuickCapture.clipboardForegroundImage(pasteboard: pasteboard, store: store)
        #expect(reference != nil)
        if let reference { #expect(store.image(for: reference) != nil) }
    }

    @Test func clipboardJPEGImportsToTheForegroundStore() throws {
        let store = isolatedStore()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("VitrineTest-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(
            try makeImageData(.systemPurple, CGSize(width: 24, height: 18), using: .jpeg),
            forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier))

        let reference = QuickCapture.clipboardForegroundImage(pasteboard: pasteboard, store: store)
        #expect(reference != nil)
        if let reference { #expect(store.image(for: reference) != nil) }
    }

    @Test func clipboardWithoutAnImageProducesNoReference() {
        let store = isolatedStore()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("VitrineTest-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("just text", forType: .string)
        #expect(QuickCapture.clipboardForegroundImage(pasteboard: pasteboard, store: store) == nil)
    }
}
