import AppKit
import Foundation
import SwiftUI
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@Suite("Diff split view")
struct DiffSplitViewTests {
    private static let patch = """
        diff --git a/Sources/Client.swift b/Sources/Client.swift
        --- a/Sources/Client.swift
        +++ b/Sources/Client.swift
        @@ -1,8 +1,8 @@
         one
         two
         three
        -four
        +FOUR
         five
         six
         seven
        """

    private func diffConfig(_ view: DiffViewMode = .split) -> SnapshotConfig {
        var config = SnapshotConfig(code: Self.patch, language: .diff)
        config.diffDecorations = true
        config.showLineNumbers = true
        config.diffView = view
        return config
    }

    private func render(_ config: SnapshotConfig) throws -> CGImage {
        try #require(ExportManager.renderCGImage(config, scale: 1))
    }

    private func differingPixels(
        _ first: () throws -> CGImage, _ second: () throws -> CGImage
    ) throws -> Int {
        var differing = 0
        for _ in 1...RenderSettling.strictRenderAttempts {
            differing = try FontLigatureTests.compareRenderedPixels(first(), second())
                .differingPixels
            if differing == 0 { break }
            RenderSettling.settleFontCaches()
        }
        return differing
    }

    // MARK: - Rendering

    @Test func unifiedIsTheDefaultAndNeedsNoParse() {
        #expect(SnapshotConfig().diffView == .unified)
        #expect(SnapshotConfig(code: Self.patch, language: .diff).diffDocument == nil)
        #expect(diffConfig().diffDocument != nil)
    }

    @Test func splitIsWiderShorterAndDeterministic() throws {
        let hunk = """
            @@ -1,3 +1,3 @@
             let first = "a fairly long line of context"
            -let second = "the old value of this line"
            +let second = "the new value of this line"
             let third = "another fairly long line"
            """
        var unified = diffConfig(.unified)
        unified.code = hunk
        var split = unified
        split.diffView = .split
        let unifiedImage = try render(unified)
        let splitImage = try render(split)
        #expect(splitImage.width > unifiedImage.width)
        #expect(splitImage.height < unifiedImage.height)

        // A spanning row wider than both columns sets the card's width.
        #expect(try render(diffConfig()).width == (try render(diffConfig(.unified)).width))
        #expect(
            try differingPixels({ try render(diffConfig()) }, { try render(diffConfig()) }) == 0)
    }

    @Test func splitAppliesOnlyToDiffContent() throws {
        var plain = SnapshotConfig(code: "+a\n-b\n c", language: .swift)
        plain.showLineNumbers = true
        var leftover = plain
        leftover.diffView = .split
        #expect(!leftover.diffUsesSplitView)
        #expect(try differingPixels({ try render(plain) }, { try render(leftover) }) == 0)
    }

    @Test func splitWorksWithoutBandsOrLineNumbers() {
        var config = SnapshotConfig(code: Self.patch, language: .diff)
        #expect(!config.usesLineRows)
        config.diffView = .split
        #expect(config.usesLineRows)
    }

    @Test func statsHeaderAndFoldWorkInSplit() throws {
        var config = diffConfig()
        let plain = try render(config)
        config.showDiffStats = true
        #expect(try render(config).height > plain.height)
        config.showDiffStats = false
        config.diffContextLines = 0
        #expect(try render(config).height < plain.height)
    }

    @Test func anEmptyCaptureShowsOnePlaceholder() throws {
        var unified = diffConfig(.unified)
        unified.code = ""
        var split = unified
        split.diffView = .split
        #expect(try differingPixels({ try render(unified) }, { try render(split) }) == 0)
    }

    @Test func wrappedSidesKeepTheUnifiedWidthAndBandsFillTheRow() throws {
        let long = String(repeating: "word ", count: 30)
        var unified = diffConfig(.unified)
        unified.wrapColumns = 60
        unified.code = "@@ -1 +1 @@\n-x\n+\(long)"
        var split = unified
        split.diffView = .split
        #expect(try render(split).width <= render(unified).width + 80)

        func removedBandRows(addition: String) throws -> Int {
            var config = split
            config.background = .solid(RGBAColor(hex: "#000000")!)
            config.code = "@@ -1 +1 @@\n-x\n+\(addition)"
            return try Self.redRows(in: render(config), atFraction: 0.4)
        }
        let single = try removedBandRows(addition: "short")
        #expect(single > 0)
        #expect(try removedBandRows(addition: long) > single * 2)
    }

    /// Rows of the column at `fraction` of the width tinted by the removed band.
    private static func redRows(in image: CGImage, atFraction fraction: Double) throws -> Int {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(
            CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let x = Int(Double(width) * fraction)
        return (0..<height).filter { y in
            let offset = (y * width + x) * 4
            return Int(pixels[offset]) > Int(pixels[offset + 1]) + 15
        }.count
    }

    // MARK: - Carousel

    @Test func carouselSlidesRenderUnified() {
        let config = diffConfig()
        let slide = CarouselPaginator.slides(for: config.code, maxLinesPerSlide: 4)[1]
        let slideConfig = CarouselPaginator.slideConfig(
            config, slide: slide, at: 1, of: 2, cues: .none)
        #expect(slideConfig.diffView == .unified)
    }

    // MARK: - Privacy

    @Test(arguments: [5...5, 8...8])
    func redactedRowsHideTheirTextOnBothSides(_ redacted: ClosedRange<Int>) throws {
        func split(_ secret: String, redacting: Bool) throws -> CGImage {
            var config = diffConfig()
            let lines = Self.patch.components(separatedBy: "\n")
            var replaced = lines
            let marker = lines[redacted.lowerBound - 1].prefix(1)
            replaced[redacted.lowerBound - 1] = String(marker) + secret
            config.code = replaced.joined(separator: "\n")
            config.redactedLineRanges = redacting ? [redacted] : []
            return try render(config)
        }
        #expect(
            try differingPixels(
                { try split("alpha", redacting: true) }, { try split("omega", redacting: true) })
                == 0)
        let visible = try FontLigatureTests.compareRenderedPixels(
            try split("alpha", redacting: false), try split("omega", redacting: false))
        #expect(visible.differingPixels > 0)
    }

    @Test func blurBoxRefusesTheSwitchAndKeepsTheCanvas() throws {
        let settings = AppSettings(defaults: testDefaults())
        settings.config = diffConfig(.unified)
        settings.style.annotations = [
            Annotation(kind: .blur, start: CGPoint(x: 0.1, y: 0.4), end: CGPoint(x: 0.5, y: 0.5))
        ]
        let before = settings.config
        settings.diffViewSelection.wrappedValue = .split
        #expect(settings.style.diffView == .unified)
        #expect(try differingPixels({ try render(before) }, { try render(settings.config) }) == 0)

        settings.style.diffView = .split
        settings.diffViewSelection.wrappedValue = .unified
        #expect(settings.style.diffView == .split)

        settings.style.annotations = []
        settings.diffViewSelection.wrappedValue = .unified
        #expect(settings.style.diffView == .unified)
        #expect(settings.diffViewSelection.wrappedValue == .unified)
    }

    // MARK: - Persistence

    @Test func unifiedLinksEncodeAsBefore() throws {
        func keys(_ config: SnapshotConfig) throws -> [String: Any] {
            try #require(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(SharedSnapshot(capturing: config)))
                    as? [String: Any])
        }
        #expect(try keys(diffConfig(.unified))["diffView"] == nil)
        #expect(try keys(diffConfig())["diffView"] as? String == "split")
    }

    @Test func shareLinkRoundTripsAndOlderPayloadsReadUnified() throws {
        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: diffConfig()))
        var target = SnapshotConfig()
        try SnapshotShareLink.snapshot(from: url).apply(to: &target)
        #expect(target.diffView == .split)

        var encoded = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(SharedSnapshot(capturing: diffConfig())))
                as? [String: Any])
        for value in [nil, "sideways"] as [String?] {
            encoded["diffView"] = value
            let older = try JSONSerialization.data(withJSONObject: encoded)
            var olderTarget = SnapshotConfig()
            olderTarget.diffView = .split
            try JSONDecoder().decode(SharedSnapshot.self, from: older).apply(to: &olderTarget)
            #expect(olderTarget.diffView == .unified)
        }
    }

    @Test func windowStateRestoresTheLayout() throws {
        let state = EditorWindowState(config: diffConfig())
        let restored = try #require(EditorWindowState.decoded(from: state.encoded()))
        #expect(restored.config().diffView == .split)

        var older = state
        older.diffView = nil
        #expect(older.config().diffView == .unified)
    }

    @Test func settingsCodecIgnoresAnUnknownLayout() {
        let defaults = testDefaults()
        SettingsCodec.persistStyle(diffConfig(), to: defaults)
        #expect(SettingsCodec.readConfig(from: defaults).diffView == .split)

        defaults.set("sideways", forKey: SettingsCodec.Keys.diffView)
        #expect(SettingsCodec.readConfig(from: defaults).diffView == .unified)
    }
}
