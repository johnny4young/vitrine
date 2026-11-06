import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@Suite("Embedded project")
struct EmbeddedProjectTests {
    private func config(_ mutate: (inout SnapshotConfig) -> Void = { _ in }) -> SnapshotConfig {
        ExportTestFixtures.sampleConfig {
            $0.code = "func greet(_ name: String) -> String {\n    \"Hello, \\(name)\"\n}"
            $0.language = .swift
            $0.windowTitle = "Greeter.swift"
            $0.annotations = [
                Annotation(
                    kind: .arrow, start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.5, y: 0.6))
            ]
            mutate(&$0)
        }
    }

    private func tinyImage() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try #require(context.makeImage())
    }

    private func link(for config: SnapshotConfig) throws -> String {
        try #require(EmbeddedProject.plan(for: config, format: .png, enabled: true).link)
    }

    /// The keywords of every PNG text chunk, walked by header only.
    private func textChunkKeywords(in data: Data) -> [String] {
        let bytes = [UInt8](data)
        var keywords: [String] = []
        var offset = 8
        while offset + 8 <= bytes.count {
            let length = bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            let type = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
            let body = offset + 8
            guard body + length <= bytes.count else { break }
            if ["iTXt", "tEXt", "zTXt"].contains(type) {
                let keyword = bytes[body..<body + length].prefix { $0 != 0 }
                keywords.append("\(type):\(String(decoding: keyword, as: UTF8.self))")
            }
            offset = body + length + 4
        }
        return keywords
    }

    // MARK: - Round trip

    @Test func aSavedPNGReopensAsTheSameShareLinkSnapshot() throws {
        let original = config()
        let data = try #require(
            EmbeddedProject.pngData(from: try tinyImage(), embedding: try link(for: original)))
        #expect(textChunkKeywords(in: data).contains("iTXt:XML:com.adobe.xmp"))
        let reopened = try #require(EmbeddedProject.snapshot(inPNG: data))
        #expect(reopened == SharedSnapshot(capturing: original))

        var restored = SnapshotConfig()
        reopened.apply(to: &restored)
        #expect(restored.code == original.code)
        #expect(restored.annotations.count == 1)
    }

    @Test func theFileReaderReadsAStoredCopy() throws {
        let data = try #require(
            EmbeddedProject.pngData(from: try tinyImage(), embedding: try link(for: config())))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("embedded-\(UUID().uuidString).png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(EmbeddedProject.snapshot(inPNGAt: url) != nil)
        #expect(EmbeddedProject.snapshot(inPNGAt: url.appendingPathExtension("missing")) == nil)
    }

    @Test func pixelsMatchThePlainEncoder() throws {
        let image = try tinyImage()
        let plain = try #require(ExportManager.pngData(from: image))
        let embedded = try #require(
            EmbeddedProject.pngData(from: image, embedding: try link(for: config())))
        func pixels(_ data: Data) throws -> Data {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            return try #require(decoded.dataProvider?.data as Data?)
        }
        #expect(try pixels(plain) == pixels(embedded))
        #expect(EmbeddedProject.snapshot(inPNG: plain) == nil)
        #expect(textChunkKeywords(in: plain).isEmpty)
    }

    @Test func theSavePayloadIsUnchangedWhenTheOptionIsOff() throws {
        let document = config()
        func payload(_ link: String?) throws -> Data {
            try ExportManager.filePayload(
                document, scale: 1, format: .png, fixedSize: nil, profile: .sRGB,
                embeddedProject: link
            ).data
        }
        let reference = try #require(
            ExportManager.pngData(
                from: try ExportManager.renderCGImageChecked(document, scale: 1)))
        #expect(try payload(nil) == reference)
        #expect(EmbeddedProject.snapshot(inPNG: try payload(try link(for: document))) != nil)
        // Other formats never carry a project, even with a link.
        let heic = try ExportManager.filePayload(
            document, scale: 1, format: .heic, fixedSize: nil, profile: .sRGB,
            embeddedProject: try link(for: document))
        #expect(heic.ext == "heic")
    }

    // MARK: - Opt-in and refusals

    @Test func theSettingIsOptInPersistentAndResettable() {
        let defaults = testDefaults()
        let behavior = OutputBehavior(defaults: defaults)
        #expect(behavior.embedsEditableProject == false)
        behavior.embedsEditableProject = true
        #expect(OutputBehavior(defaults: defaults).embedsEditableProject)
        behavior.resetToDefaults()
        #expect(OutputBehavior(defaults: defaults).embedsEditableProject == false)
        #expect(SettingsCodec.Keys.all.contains(SettingsCodec.Keys.embedEditableProject))
    }

    @Test func nothingIsEmbeddedUnlessEnabledForAPNGOfCode() {
        #expect(EmbeddedProject.plan(for: config(), format: .png, enabled: false) == .off)
        for format in [ExportFormat.pdf, .heic, .avif] {
            #expect(EmbeddedProject.plan(for: config(), format: format, enabled: true) == .off)
        }
        let image = config { $0.foregroundImage = ImageReference(fileName: "shot.png") }
        #expect(EmbeddedProject.plan(for: image, format: .png, enabled: true) == .off)
    }

    @Test func redactionsRefuseTheEmbed() {
        let redacted = config { $0.redactedLineRanges = [2...2] }
        #expect(
            EmbeddedProject.plan(for: redacted, format: .png, enabled: true)
                == .withheld(.redactions))
        let blurred = config {
            $0.annotations.append(
                Annotation(
                    kind: .blur, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.4, y: 0.3)))
        }
        #expect(
            EmbeddedProject.plan(for: blurred, format: .png, enabled: true)
                == .withheld(.redactions))
    }

    @Test func anOversizedProjectIsWithheld() {
        var generator = SystemRandomNumberGenerator()
        let noise = (0..<200_000).map { _ in
            Character(UnicodeScalar(UInt8.random(in: 33...126, using: &generator)))
        }
        let huge = config { $0.code = String(noise) }
        #expect(
            EmbeddedProject.plan(for: huge, format: .png, enabled: true) == .withheld(.tooLarge))
    }

    @Test func aFilenamePathIsReducedToItsName() throws {
        let document = config {
            $0.metadata = SnapshotMetadata(filename: "/Users/someone/Code/App/Greeter.swift")
        }
        let data = try #require(
            EmbeddedProject.pngData(from: try tinyImage(), embedding: try link(for: document)))
        let reopened = try #require(EmbeddedProject.snapshot(inPNG: data))
        var restored = SnapshotConfig()
        reopened.apply(to: &restored)
        #expect(restored.metadata.filename == "Greeter.swift")
        #expect(!(try link(for: document)).contains("someone"))
    }

    // MARK: - Untrusted input

    @Test func foreignOrCraftedImagesHaveNoProject() throws {
        let image = try tinyImage()
        #expect(EmbeddedProject.snapshot(inPNG: Data()) == nil)
        #expect(EmbeddedProject.snapshot(inPNG: Data("not an image".utf8)) == nil)
        #expect(
            EmbeddedProject.snapshot(inPNG: try #require(ExportManager.heicData(from: image)))
                == nil)

        for value in [
            "https://example.com/?d=abc", "vitrine://open?d=%%%", "vitrine://open?d=AAAA",
            "vitrine://edit?d=abc",
            String(repeating: "A", count: EmbeddedProject.maxLinkLength + 1),
        ] {
            let crafted = try #require(EmbeddedProject.pngData(from: image, embedding: value))
            #expect(EmbeddedProject.snapshot(inPNG: crafted) == nil)
        }

        let valid = try #require(
            EmbeddedProject.pngData(from: image, embedding: try link(for: config())))
        #expect(EmbeddedProject.snapshot(inPNG: valid.prefix(valid.count / 2)) == nil)
        var oversized = valid
        oversized.append(Data(count: BackgroundImageStore.maxImportBytes))
        #expect(EmbeddedProject.snapshot(inPNG: oversized) == nil)
    }

    @Test func anUnknownSchemaVersionIsRefused() throws {
        var snapshot = SharedSnapshot(capturing: config())
        snapshot.version = SharedSnapshot.schemaVersion + 1
        let json = try JSONEncoder().encode(snapshot)
        let encoded = Base64URL.encode(try Zlib.compress(json))
        let data = try #require(
            EmbeddedProject.pngData(
                from: try tinyImage(), embedding: "vitrine://open?d=\(encoded)"))
        #expect(EmbeddedProject.snapshot(inPNG: data) == nil)
    }

    // MARK: - App wiring

    @Test func clipboardCopiesNeverCarryTheProject() throws {
        let pasteboard = NSPasteboard(name: .init("EmbeddedProject-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let outcome = ExportManager.copyToPasteboardOutcome(
            config(), scale: 1, concealed: true, pasteboard: pasteboard)
        #expect(outcome == .copied)
        let png = try #require(pasteboard.data(forType: .png))
        #expect(EmbeddedProject.snapshot(inPNG: png) == nil)
    }

    @Test func anEmbeddingSaveIsPreflightedAsAShareLink() {
        let settings = AppSettings(defaults: testDefaults())
        settings.config = config()
        settings.export.format = .png
        #expect(EditorPresentation.savePayload(of: settings) == .image)
        settings.outputBehavior.embedsEditableProject = true
        #expect(EditorPresentation.savePayload(of: settings) == .transcript)
        settings.config.redactedLineRanges = [1...1]
        #expect(EditorPresentation.savePayload(of: settings) == .image)
        #expect(EditorImageSave.embeddingPlan(settings) == .withheld(.redactions))
    }

    @Test func quickCaptureEmbedsOnlyInAnAlsoSavedPNG() {
        let settings = AppSettings(defaults: testDefaults())
        settings.export.format = .png
        settings.outputBehavior.embedsEditableProject = true
        settings.outputBehavior.alsoSaveToFile = false
        #expect(QuickCapture.embeddedProject(for: config(), settings: settings) == nil)
        settings.outputBehavior.alsoSaveToFile = true
        #expect(QuickCapture.embeddedProject(for: config(), settings: settings) != nil)
    }

    @Test func aWithheldEmbedIsNamedInTheSaveFeedback() {
        #expect(
            ExportFeedback.saveOutcome(.saved, embedding: .withheld(.redactions))
                == Notifier.confirmation(
                    String(
                        localized:
                            "Image saved without the editable project: something is redacted")))
        #expect(
            ExportFeedback.saveOutcome(.saved, embedding: .withheld(.tooLarge))
                == Notifier.confirmation(
                    String(localized: "Image saved without the editable project: it's too large")))
        #expect(
            ExportFeedback.saveOutcome(.saved, embedding: .embed(link: "x"))
                == Notifier.confirmation(String(localized: "Image saved")))
        #expect(ExportFeedback.saveOutcome(.cancelled, embedding: .withheld(.tooLarge)) == nil)
    }
}
