import CoreGraphics
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@MainActor
@Suite("VitrineRendering boundary")
struct VitrineRenderingBoundaryTests {
    @Test func sharedFacadeRendersAndEncodesAConfiguredSnapshot() throws {
        var config = SnapshotConfig()
        config.code = "let release = \"1.2.1\"\nprint(release)"
        config.language = .swift
        config.theme = .oneDark
        config.showLineNumbers = true

        let image = try ExportManager.renderCGImageChecked(config, scale: 1)
        let data = try #require(ExportManager.pngData(from: image))

        #expect(image.width > 0)
        #expect(image.height > 0)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func markdownUsesTheRenderedConfigurationsSafeSidecar() {
        var config = SnapshotConfig()
        config.code = "let visible = 1\nlet secret = 2\n"
        config.language = .swift
        config.redactedLineRanges = [2...2]

        let markdown = MarkdownExport.document(for: config, imageSource: "snapshot.png")

        #expect(markdown.contains("let visible = 1\n[redacted]\n"))
        #expect(!markdown.contains("let secret = 2"))
    }

    @Test func imagePolicyDownsamplesBeforeAllocatingPastInteractiveBudget() throws {
        let maximum = try ImageDecodePolicy.thumbnailMaximumPixelSize(
            for: 20_000,
            height: 10_000
        )

        #expect(maximum > 0)
        #expect(maximum <= RenderBudget.preview.maximumDimension)
    }

    @Test func largeDocumentsSelectTheExplicitPlainTextFallback() {
        let code = String(
            repeating: "x",
            count: HighlightPolicy.maximumHighlightedByteCount + 1
        )

        #expect(HighlightPolicy.mode(for: code, language: .swift).usesPlainTextFallback)
        #expect(!HighlightPolicy.shouldCache(code))
    }
}
