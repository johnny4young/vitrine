import AppKit
import Foundation
import ImageIO
import Testing
import VitrineRendering

@testable import Vitrine

/// Clipboard delivery (`ExportManager+Pasteboard`).
///
/// Scoped to the plain-source copy; the multi-representation rich clipboard has its own
/// suite in `RichExportTests`. Serialized because pasteboard state is shared, and each
/// test uses a uniquely named scratch pasteboard so a parallel suite can never clobber
/// the developer's real clipboard.
@MainActor
@Suite("Export · source text clipboard", .serialized)
struct SourceTextClipboardTests {
    @Test("Copying source replaces other representations and preserves exact text")
    func copySource() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("VitrineSourceCopyTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        #expect(pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png))
        let source = "let greeting = \"¡Hola!\"\nprint(greeting)"

        #expect(ExportManager.copySourceToPasteboard(source, to: pasteboard))
        #expect(pasteboard.string(forType: .string) == source)
        #expect(pasteboard.data(forType: .png) == nil)
    }
}

@MainActor
@Suite("Export · PNG clipboard", .serialized)
struct PNGClipboardTests {
    @Test("The typed PNG writer replaces stale text and preserves raster dimensions")
    func copyRenderedPNG() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("VitrinePNGCopyTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.setString("old source", forType: .string))
        let image = try ExportManager.renderCGImageChecked(
            ExportTestFixtures.sampleConfig(), scale: 1)

        #expect(ExportManager.copyPNGToPasteboardOutcome(image, to: pasteboard) == .copied)
        #expect(pasteboard.string(forType: .string) == nil)
        let data = try #require(pasteboard.data(forType: .png))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == image.width)
        #expect(decoded.height == image.height)
    }
}
