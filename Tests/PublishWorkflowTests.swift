import AppKit
import Testing

@testable import Vitrine

/// Covers carousel pagination and share-sheet compose targets.
@Suite("Carousel export and compose")
@MainActor
struct PublishWorkflowTests {
    // MARK: - Carousel pagination

    @Test func balancedSplitNeverLeavesATinyLastSlide() {
        // 25 lines at a 12-line cap: 3 slides of 9/8/8 — never 12/12/1.
        let code = (1...25).map { "line \($0)" }.joined(separator: "\n")
        let pages = CarouselPaginator.pages(for: code, maxLinesPerSlide: 12)
        let counts = pages.map { $0.components(separatedBy: "\n").count }
        #expect(counts == [9, 8, 8])
        // Nothing lost, order preserved.
        #expect(pages.joined(separator: "\n") == code)
    }

    @Test func shortSnippetIsASingleSlide() {
        let pages = CarouselPaginator.pages(for: "a\nb\nc", maxLinesPerSlide: 12)
        #expect(pages == ["a\nb\nc"])
    }

    @Test func trailingNewlineAndEmptyInputDegenerateSafely() {
        // The trailing-newline artifact never opens a blank slide: "a\nb\n" is two
        // lines, one slide at a 2-line cap — and splits in two at a 1-line cap.
        #expect(CarouselPaginator.pages(for: "a\nb\n", maxLinesPerSlide: 2) == ["a\nb"])
        #expect(CarouselPaginator.pages(for: "a\nb\n", maxLinesPerSlide: 1) == ["a", "b"])
        #expect(CarouselPaginator.pages(for: "", maxLinesPerSlide: 12).isEmpty)
        #expect(CarouselPaginator.pages(for: "\n\n", maxLinesPerSlide: 12).isEmpty)
    }

    /// The export writes one numbered PNG per page at the 4:5 slide frame, and each
    /// slide matches a single render of that page at the normalized-pixel layer.
    /// ImageIO may encode identical pixels into different PNG byte streams, so the
    /// compressed container bytes are deliberately outside this rendering contract.
    @Test func carouselWritesNumberedSlidesMatchingSingleRenders() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineCarousel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var base = SnapshotConfig()
        base.code = "one\ntwo\nthree\nfour"
        let pages = CarouselPaginator.pages(for: base.code, maxLinesPerSlide: 2)
        #expect(pages.count == 2)

        let result = await ExportManager.exportCarousel(base, pages: pages, to: dir)
        #expect(result.written == 2)
        #expect(result.failed == 0)

        for (index, page) in pages.enumerated() {
            let url = dir.appendingPathComponent(String(format: "carousel-%02d.png", index + 1))
            let written = try #require(
                GoldenComparator.loadImage(at: url),
                "carousel slide \(index + 1) is not a decodable image")
            var single = base
            single.clearContentMarks()
            single.code = page
            // Slides render at the carousel font floor so they stay legible at feed size.
            single.fontSize = max(single.fontSize, ExportManager.carouselMinimumFontSize)
            let reference = try #require(
                ExportManager.renderCGImage(
                    single, scale: 1, fixedSize: ExportManager.carouselSlideSize))
            let comparison = try Self.pixelComparison(written, reference)
            #expect(
                comparison.matches,
                "carousel slide \(index + 1) changed \(comparison.differingPixels)/\(comparison.pixelCount) pixels (max channel delta \(comparison.maxChannelDelta))"
            )
        }
    }

    /// Uses the same canonical RGBA8 comparison as the cross-version golden suite,
    /// preserving dimension checks and a narrow anti-aliasing tolerance without
    /// coupling this workflow test to PNG metadata or compression decisions.
    private static func pixelComparison(
        _ lhs: CGImage, _ rhs: CGImage
    ) throws -> GoldenComparator.Result {
        switch GoldenComparator.compare(lhs, rhs) {
        case .success(let result):
            return result
        case .failure(let failure):
            throw failure
        }
    }

    // MARK: - Compose URLs

    @Test func composeURLsEncodeTheTextPerNetwork() throws {
        let text = "Shipped! #swift & more"
        let x = try #require(SocialComposer.composeURL(for: .x, text: text))
        #expect(x.absoluteString.hasPrefix("https://x.com/intent/post?"))
        let bluesky = try #require(SocialComposer.composeURL(for: .bluesky, text: text))
        #expect(bluesky.absoluteString.hasPrefix("https://bsky.app/intent/compose?"))
        let linkedIn = try #require(SocialComposer.composeURL(for: .linkedIn, text: text))
        #expect(linkedIn.absoluteString.contains("shareActive=true"))

        // The text round-trips through the query encoding on every network.
        for url in [x, bluesky, linkedIn] {
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let value = components.queryItems?.first { $0.name == "text" }?.value
            #expect(value == text)
        }
    }
}

// MARK: - Share-sheet compose targets

extension PublishWorkflowTests {
    /// The picker only offers compose targets when the shared items carry an image;
    /// anything else falls through to the system services untouched.
    @Test func composeTargetsRequireAnImageItem() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        #expect(ShareManager.shareableImage(in: [image]) === image)
        #expect(ShareManager.shareableImage(in: []) == nil)
        #expect(ShareManager.shareableImage(in: ["not an image"]) == nil)
    }
}
