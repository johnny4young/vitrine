import AppKit
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

// P5 — quick capture renders the styled image once and feeds that single raster to
// both the clipboard copy and the file save, instead of re-rendering the identical
// config. These pin that the cgImage-based copy/payload produce byte-for-byte the same
// output as the full-render path they replace, so the optimization is invisible.

@MainActor
@Suite("Render-once copy/save primitives · P5")
struct RenderOnceExportTests {
    private func sampleConfig() -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "let answer = 42\nprint(answer)"
        return config
    }

    @Test func payloadFromCGImageEqualsTheFullRenderPayload() throws {
        let config = sampleConfig()
        let cgImage = try #require(ExportManager.renderCGImage(config, scale: 2))

        // The cgImage-based payload's PNG is exactly the pre-rendered image's PNG…
        let fromImage = try #require(
            RichPasteboard.makePayload(cgImage: cgImage, for: config, includeRichText: false))
        #expect(fromImage.png == ExportManager.pngData(from: cgImage))

        // …and byte-identical to the payload the full-render path builds for the same
        // config, so reusing one render never changes what lands on the pasteboard.
        let fromConfig = try #require(
            RichPasteboard.makePayload(
                for: config, scale: 2, fixedSize: nil, profile: .sRGB, includeRichText: false))
        #expect(fromImage.png == fromConfig.png)
    }

    @Test func copyFromCGImageWritesThatExactImage() throws {
        let config = sampleConfig()
        let cgImage = try #require(ExportManager.renderCGImage(config, scale: 2))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("VitrineP5-\(UUID().uuidString)"))

        #expect(
            RichPasteboard.copy(
                cgImage: cgImage, config: config, includeRichText: false, to: pasteboard))

        let png = try #require(pasteboard.data(forType: RichPasteboard.pngType))
        #expect(png == ExportManager.pngData(from: cgImage))
    }

    @Test func rasterSaveRejectsPDF() throws {
        // The cgImage save path is raster-only; PDF must go through the vector config path.
        // With a nil payload it returns `.failed` before ever showing a save panel.
        let cgImage = try #require(ExportManager.renderCGImage(sampleConfig(), scale: 1))
        let outcome = ExportManager.saveToFile(cgImage: cgImage, format: .pdf, suggestedName: "x")
        #expect(outcome == .failed)
    }
}
