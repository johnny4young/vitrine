import AppKit
import Foundation
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@Suite("Clipboard privacy", .serialized)
struct ClipboardPrivacyTests {
    @Test func preferenceIsOptInPersistentAndResettable() {
        let defaults = testDefaults()
        let settings = ExportSettings(defaults: defaults)
        #expect(settings.concealClipboard == false)
        settings.concealClipboard = true
        #expect(ExportSettings(defaults: defaults).concealClipboard)
        settings.resetToDefaults()
        #expect(ExportSettings(defaults: defaults).concealClipboard == false)
        defaults.set("not a boolean", forKey: SettingsCodec.Keys.concealClipboard)
        #expect(ExportSettings(defaults: defaults).concealClipboard == false)
        #expect(SettingsCodec.Keys.all.contains(SettingsCodec.Keys.concealClipboard))
        #expect(
            SettingsCodec.Keys.editorSessionSeed.contains(SettingsCodec.Keys.concealClipboard)
                == false)
    }

    @Test func writerMarksEveryRepresentationWithoutMutatingTheInputOrChangingBytes() throws {
        let pasteboard = NSPasteboard(name: .init("ClipboardPrivacy-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        let png = Data([0x89, 0x50, 0x4e, 0x47])
        #expect(item.setString("synthetic text", forType: .string))
        #expect(item.setData(png, forType: .png))
        #expect(ClipboardWriter.write([item], concealed: true, to: pasteboard))
        let written = try #require(pasteboard.pasteboardItems?.first)
        #expect(pasteboard.pasteboardItems?.count == 1)
        #expect(written.types.contains(ClipboardWriter.concealedType))
        #expect(written.string(forType: .string) == "synthetic text")
        #expect(written.data(forType: .png) == png)
        #expect(item.types.contains(ClipboardWriter.concealedType) == false)
        #expect(ClipboardWriter.write([item], to: pasteboard))
        #expect(pasteboard.types?.contains(ClipboardWriter.concealedType) == false)
    }

    @Test func emptyWritesDoNotClearTheExistingClipboard() {
        let pasteboard = NSPasteboard(name: .init("ClipboardPrivacy-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(ClipboardWriter.copy("keep", to: pasteboard))
        for concealed in [false, true] {
            #expect(ClipboardWriter.write([], concealed: concealed, to: pasteboard) == false)
            #expect(
                ClipboardWriter.write([NSPasteboardItem()], concealed: concealed, to: pasteboard)
                    == false)
        }
        #expect(pasteboard.string(forType: .string) == "keep")
    }

    @Test(arguments: [false, true])
    func unavailableRepresentationsDoNotFailTheCopy(_ concealed: Bool) {
        let pasteboard = NSPasteboard(name: .init("ClipboardPrivacy-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(ClipboardWriter.write([PartialWriter()], concealed: concealed, to: pasteboard))
        #expect(pasteboard.string(forType: .string) == PartialWriter.text)
        #expect(pasteboard.types?.contains(ClipboardWriter.concealedType) == concealed)
    }

    @Test(arguments: [false, true])
    func exportWritersHonorTheRequestedClassification(_ concealed: Bool) throws {
        let pasteboard = NSPasteboard(name: .init("ClipboardPrivacy-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let config = SnapshotConfig(code: "let visible = 1", language: .swift)
        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        func check(_ copied: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(copied, sourceLocation: sourceLocation)
            #expect(
                pasteboard.types?.contains(ClipboardWriter.concealedType) == concealed,
                sourceLocation: sourceLocation)
            #expect(pasteboard.pasteboardItems?.count == 1, sourceLocation: sourceLocation)
        }
        check(ExportManager.copySourceToPasteboard("source", concealed: concealed, to: pasteboard))
        check(
            ExportManager.copyPNGToPasteboardOutcome(image, concealed: concealed, to: pasteboard)
                == .copied)
        check(
            ExportManager.copyToPasteboard(
                config, scale: 1, concealed: concealed, pasteboard: pasteboard))
        check(
            ExportManager.copyToPasteboard(
                config, scale: 1, richText: true, plainText: true, concealed: concealed,
                pasteboard: pasteboard))
        #expect(pasteboard.data(forType: .png) != nil)
        #expect(pasteboard.data(forType: .rtf) != nil)
        #expect(pasteboard.data(forType: .html) != nil)
        check(
            RichPasteboard.copy(
                config, scale: 1, fixedSize: nil, profile: .sRGB, includeRichText: true,
                concealed: concealed, to: pasteboard))
        check(
            RichPasteboard.copy(
                cgImage: image, config: config, includeRichText: true, concealed: concealed,
                to: pasteboard))
        check(RichPasteboard.copyHighlightedCode(for: config, concealed: concealed, to: pasteboard))
        check(
            RichPasteboard.copyDataURI(
                for: config, scale: 1, fixedSize: nil, profile: .sRGB, concealed: concealed,
                to: pasteboard))
        check(
            RichPasteboard.copyMarkdown(
                for: config, scale: 1, fixedSize: nil, profile: .sRGB, concealed: concealed,
                to: pasteboard))
        let sharedImage = NSImage(
            cgImage: image, size: NSSize(width: image.width, height: image.height))
        check(ClipboardWriter.write([sharedImage], concealed: concealed, to: pasteboard))
        #expect(NSImage(pasteboard: pasteboard) != nil)
        check(
            SocialCardRenderer.copyToPasteboard(
                SocialCardModel(title: "Synthetic card"), scale: 1, concealed: concealed,
                pasteboard: pasteboard))
        #expect(NSImage(pasteboard: pasteboard) != nil)
    }
}

/// Offers a representation it cannot produce, like a lazily rendered or failed type.
private nonisolated final class PartialWriter: NSObject, NSPasteboardWriting {
    static let text = "partial"
    static let missing = NSPasteboard.PasteboardType("app.vitrine.tests.missing")

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.string, Self.missing]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .string ? Self.text : nil
    }
}
