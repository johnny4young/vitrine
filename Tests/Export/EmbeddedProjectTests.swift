import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

private let token = "gh" + "p_" + String(repeating: "x", count: 36)

@Suite("Embedded project")
struct EmbeddedProjectTests {
    private func config(_ mutate: (inout SnapshotConfig) -> Void = { _ in }) -> SnapshotConfig {
        ExportTestFixtures.sampleConfig {
            $0.code = "func greet(_ name: String) -> String {\n    \"Hello, \\(name)\"\n}"
            $0.language = .swift
            $0.showChrome = true
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

    private func plan(_ config: SnapshotConfig) -> EmbeddedProject.Plan {
        EmbeddedProject.plan(for: config, format: .png, enabled: true)
    }

    private func link(for config: SnapshotConfig) throws -> String {
        try #require(plan(config).link)
    }

    private func reopened(_ config: SnapshotConfig) throws -> SnapshotConfig {
        let data = try #require(
            EmbeddedProject.pngData(from: try tinyImage(), embedding: try link(for: config)))
        var restored = SnapshotConfig()
        try #require(EmbeddedProject.snapshot(inPNG: data)).apply(to: &restored)
        return restored
    }

    private func temporaryFile(_ data: Data, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("embedded-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
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
        #expect(EmbeddedProject.snapshot(inPNG: data) == SharedSnapshot(capturing: original))
        let restored = try reopened(original)
        #expect(restored.code == original.code)
        #expect(restored.windowTitle == "Greeter.swift")
        #expect(restored.annotations.count == 1)
    }

    @Test func theFileReaderChecksTheSignatureFirst() async throws {
        let image = try tinyImage()
        let png = try temporaryFile(
            try #require(EmbeddedProject.pngData(from: image, embedding: try link(for: config()))),
            ext: "png")
        let heic = try temporaryFile(try #require(ExportManager.heicData(from: image)), ext: "png")
        defer {
            try? FileManager.default.removeItem(at: png)
            try? FileManager.default.removeItem(at: heic)
        }
        #expect(EmbeddedProject.hasPNGSignature(at: png))
        #expect(!EmbeddedProject.hasPNGSignature(at: heic))
        #expect(!EmbeddedProject.hasPNGSignature(at: FileManager.default.temporaryDirectory))
        #expect(await EmbeddedProject.snapshot(inPNGAt: png) != nil)
        #expect(await EmbeddedProject.snapshot(inPNGAt: heic) == nil)
        #expect(
            await EmbeddedProject.snapshot(inPNGAt: png.appendingPathExtension("missing")) == nil)
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
        let heic = try ExportManager.filePayload(
            document, scale: 1, format: .heic, fixedSize: nil, profile: .sRGB,
            embeddedProject: try link(for: document))
        #expect(heic.ext == "heic")
    }

    // MARK: - Opt-in and refusals

    @Test func theSettingsAreOptInPersistentAndResettable() {
        let defaults = testDefaults()
        let behavior = OutputBehavior(defaults: defaults)
        #expect(behavior.embedsEditableProject == false)
        #expect(behavior.asksToOpenEmbeddedProjects)
        behavior.embedsEditableProject = true
        behavior.asksToOpenEmbeddedProjects = false
        #expect(OutputBehavior(defaults: defaults).embedsEditableProject)
        #expect(OutputBehavior(defaults: defaults).asksToOpenEmbeddedProjects == false)
        behavior.resetToDefaults()
        #expect(OutputBehavior(defaults: defaults).embedsEditableProject == false)
        #expect(OutputBehavior(defaults: defaults).asksToOpenEmbeddedProjects)
        #expect(SettingsCodec.Keys.all.contains(SettingsCodec.Keys.embedEditableProject))
        #expect(SettingsCodec.Keys.all.contains(SettingsCodec.Keys.askToOpenEmbeddedProjects))
    }

    @Test func nothingIsEmbeddedUnlessEnabledForAPNGOfCode() {
        #expect(EmbeddedProject.plan(for: config(), format: .png, enabled: false) == .off)
        for format in [ExportFormat.pdf, .heic, .avif] {
            #expect(EmbeddedProject.plan(for: config(), format: format, enabled: true) == .off)
        }
        #expect(plan(config { $0.foregroundImage = ImageReference(fileName: "shot.png") }) == .off)
    }

    @Test func eachRefusalNamesItsCause() {
        #expect(plan(config { $0.redactedLineRanges = [2...2] }) == .withheld(.redactedLines))
        let blur = Annotation(
            kind: .blur, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.4, y: 0.3))
        #expect(plan(config { $0.annotations.append(blur) }) == .withheld(.blurBoxes))
        #expect(
            plan(
                config {
                    $0.language = .terminal
                    $0.code = "\u{1B}[2J\u{1B}[Hvisible"
                }) == .withheld(.terminal))
    }

    @Test func anySecretFindingBlocksTheEmbed() {
        #expect(plan(config { $0.code = "let key = \"\(token)\"" }) == .withheld(.secret))
        #expect(
            plan(config { $0.metadata = SnapshotMetadata(title: token) }) == .withheld(.secret))
        #expect(plan(config { $0.windowTitle = token }) == .withheld(.secret))
        #expect(
            plan(config { $0.altText = try? SnapshotAltText.normalized(token) })
                == .withheld(.secret))
    }

    @Test func aHiddenWindowTitleIsNotEmbedded() throws {
        let hidden = config {
            $0.showChrome = false
            $0.windowTitle = token
        }
        #expect(plan(hidden).link != nil)
        #expect(try reopened(hidden).windowTitle.isEmpty)
    }

    @Test func anOversizedProjectIsWithheld() {
        var generator = SystemRandomNumberGenerator()
        let noise = (0..<200_000).map { _ in
            Character(UnicodeScalar(UInt8.random(in: 48...57, using: &generator)))
        }
        let huge = config { $0.code = String(noise) }
        #expect(plan(huge) == .withheld(.tooLarge))
    }

    @Test func onlyRealPathsAreReducedToTheirName() throws {
        let cases = [
            "/Users/someone/Code/App/Greeter.swift": "Greeter.swift",
            "~/Code/App/Greeter.swift": "Greeter.swift",
            "file:///Users/someone/Greeter.swift": "Greeter.swift",
            "weather-app · feature/login": "weather-app · feature/login",
            "Sources/App/Greeter.swift": "Sources/App/Greeter.swift",
        ]
        for (typed, embedded) in cases {
            let restored = try reopened(config { $0.metadata = SnapshotMetadata(filename: typed) })
            #expect(restored.metadata.filename == embedded)
        }
    }

    // MARK: - Untrusted input

    @Test func foreignOrCraftedImagesHaveNoProject() throws {
        let image = try tinyImage()
        #expect(EmbeddedProject.snapshot(inPNG: Data()) == nil)
        #expect(EmbeddedProject.snapshot(inPNG: Data("not an image".utf8)) == nil)
        #expect(
            EmbeddedProject.snapshot(inPNG: try #require(ExportManager.heicData(from: image)))
                == nil)
        #expect(EmbeddedProject.maxLinkLength >= SnapshotShareLink.maxEncodedLength)

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

    @Test func theImagePreflightNeverCoversTheEmbed() {
        let settings = AppSettings(defaults: testDefaults())
        settings.config = config { $0.code = "let key = \"\(token)\"" }
        settings.export.format = .png
        settings.outputBehavior.embedsEditableProject = true
        #expect(EditorPresentation.savePayload(of: settings) == .image)
        settings.acknowledgedPreflights.insert(
            ExportPreflight(settings.config, payload: .image).acknowledgement(for: .save))
        #expect(EditorImageSave.embeddingPlan(settings) == .withheld(.secret))
    }

    @Test func quickCaptureEmbedsOnlyInAnAlsoSavedPNG() {
        let settings = AppSettings(defaults: testDefaults())
        settings.export.format = .png
        settings.outputBehavior.embedsEditableProject = true
        settings.outputBehavior.alsoSaveToFile = false
        #expect(QuickCapture.embeddingPlan(for: config(), settings: settings) == .off)
        settings.outputBehavior.alsoSaveToFile = true
        #expect(QuickCapture.embeddingPlan(for: config(), settings: settings).link != nil)
        #expect(
            QuickCapture.embeddingPlan(
                for: config { $0.redactedLineRanges = [1...1] }, settings: settings)
                == .withheld(.redactedLines))
    }

    @Test func aWithheldEmbedIsNamedInTheSaveFeedback() {
        let reasons: [EmbeddedProject.Withheld] = [
            .redactedLines, .blurBoxes, .terminal, .secret, .tooLarge,
        ]
        let details = reasons.map { ExportFeedback.withheldDetail($0).text }
        #expect(Set(details).count == reasons.count)
        #expect(
            ExportFeedback.saveOutcome(.saved, embedding: .withheld(.terminal))
                == Notifier.confirmation(
                    String(localized: "Image saved"),
                    detail: ExportFeedback.withheldDetail(.terminal)))
        #expect(
            ExportFeedback.saveOutcome(.saved, embedding: .embed(link: "x"))
                == Notifier.confirmation(String(localized: "Image saved")))
        #expect(ExportFeedback.saveOutcome(.cancelled, embedding: .withheld(.tooLarge)) == nil)
    }

    @Test func quickCaptureShowsTheWithheldReasonInTheHUD() {
        var shown: [Notifier.CaptureFeedback] = []
        let presenter = CaptureFeedbackPresenter(
            display: FeedbackDisplay { feedback, _ in shown.append(feedback) },
            routing: CaptureRecoveryRouting(
                loadPrimaryEditor: { _ in }, presentEditor: {}, presentWebSnapshot: { _ in }))
        let result = QuickCapture.Result(
            outcome: .copied, copiedToClipboard: true, savedToFile: true,
            withheldProject: .secret)
        presenter.present(result, environment: AppEnvironment(defaults: testDefaults()))
        #expect(shown.last?.detail == ExportFeedback.withheldDetail(.secret))
    }

    @Test func openingAProjectUndoesInOneStep() throws {
        let settings = AppSettings(defaults: testDefaults())
        settings.config = config { $0.code = "let previous = 1" }
        let before = settings.config
        let generation = settings.documentGeneration
        let snapshot = SharedSnapshot(capturing: config())

        let previous = EditorView.openProject(snapshot, in: settings)
        #expect(previous == before)
        #expect(settings.config.code == config().code)
        #expect(settings.documentGeneration != generation)

        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        EditorView.registerDocumentUndo(
            restoring: previous, in: settings, undoManager: undoManager)
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == String(localized: "Open Editable Project"))
        undoManager.undo()
        #expect(settings.config == before)
        #expect(!undoManager.canUndo)
    }
}
