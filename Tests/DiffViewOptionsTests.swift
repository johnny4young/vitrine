import AppKit
import Foundation
import SwiftUI
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@Suite("Diff view options")
struct DiffViewOptionsTests {
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

    private func diffConfig() -> SnapshotConfig {
        var config = SnapshotConfig(code: Self.patch, language: .diff)
        config.diffDecorations = true
        return config
    }

    private func render(_ config: SnapshotConfig) throws -> CGImage {
        try #require(ExportManager.renderCGImage(config, scale: 1))
    }

    /// Exact comparisons retry on a settled run loop: a fonts-changed notification from a
    /// parallel test can nudge one frame, while a real difference fails every attempt.
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

    @Test func defaultsLeaveTheRenderUnchanged() throws {
        #expect(!SnapshotConfig().showDiffStats)
        #expect(SnapshotConfig().diffContextLines == nil)
        #expect(SnapshotConfig(code: Self.patch, language: .diff).diffDocument == nil)
    }

    @Test func statsHeaderAddsARowAndRendersDeterministically() throws {
        var config = diffConfig()
        let plain = try render(config)
        config.showDiffStats = true
        let first = try render(config)

        #expect(first.height > plain.height)
        #expect(first.width == plain.width)
        #expect(try differingPixels({ try render(config) }, { try render(config) }) == 0)
    }

    @Test func contextFoldShrinksTheCardMonotonically() throws {
        var config = diffConfig()
        let all = try render(config).height
        config.diffContextLines = 1
        let one = try render(config).height
        config.diffContextLines = 0
        let zero = try render(config).height
        #expect(zero < one)
        #expect(one < all)
    }

    @Test func enoughContextMatchesTheUnfoldedRender() throws {
        let all = diffConfig()
        var config = all
        config.diffContextLines = 5
        #expect(try differingPixels({ try render(all) }, { try render(config) }) == 0)
    }

    @Test func redactedPathAndSeveralFilesRenderWithoutAPath() throws {
        var config = diffConfig()
        config.showDiffStats = true
        config.redactedLineRanges = [3...3]
        #expect(config.diffDocument?.singleFilePath(redacting: config.redactedLineRanges) == nil)
        #expect(try render(config).height > 0)

        config.redactedLineRanges = []
        config.code = "diff --git a/one b/one\ndiff --git a/two b/two\n"
        #expect(config.diffDocument?.files.count == 2)
        #expect(try render(config).height > 0)
    }

    @Test func longPathKeepsItsEnd() {
        let path = String(repeating: "dir/", count: 40) + "File.swift"
        let shown = DiffStatsHeader.truncated(path)
        #expect(shown.count == DiffStatsHeader.maximumPathLength)
        #expect(shown.hasPrefix("…"))
        #expect(shown.hasSuffix("File.swift"))
        #expect(DiffStatsHeader.truncated("File.swift") == "File.swift")
    }

    // MARK: - Gating

    @Test func optionsApplyOnlyToDiffContent() {
        var config = SnapshotConfig(code: "+a", language: .swift)
        config.showDiffStats = true
        config.diffContextLines = 0
        config.diffDecorations = true
        #expect(!config.diffOptionsApply)
        #expect(config.diffDocument == nil)

        config.language = .terminal
        #expect(!config.diffOptionsApply)
        config.language = .diff
        #expect(config.diffOptionsApply)
        #expect(config.diffDocument != nil)
        config.foregroundImage = ImageReference(fileName: "x.png")
        #expect(!config.diffOptionsApply)
    }

    @Test func diffLanguageWithoutBandsStillFolds() {
        var config = SnapshotConfig(code: Self.patch, language: .diff)
        #expect(!config.usesLineRows)
        config.diffContextLines = 1
        #expect(config.usesLineRows)
    }

    // MARK: - Review reproductions

    @Test func yamlAfterADiffSessionKeepsEveryRow() throws {
        let yaml = "first: 1\nsecond: 2\n- item\nthird: 3\nfourth: 4\nfifth: 5\n- other\nlast: 6"
        var plain = SnapshotConfig(code: yaml, language: .yaml)
        plain.diffDecorations = true
        var leftover = plain
        leftover.diffContextLines = 0
        leftover.showDiffStats = true
        #expect(try differingPixels({ try render(plain) }, { try render(leftover) }) == 0)
    }

    @Test func foldKeepsHighlightedRows() throws {
        var config = diffConfig()
        config.diffContextLines = 0
        let folded = try render(config).height
        config.highlightedLineRanges = [5...5]
        config.focusHighlightedLines = true
        #expect(try render(config).height > folded)
    }

    @Test func redactedShareLinkKeepsTheReceiversDiffStable() throws {
        var config = diffConfig()
        config.showDiffStats = true
        config.diffContextLines = 0
        config.redactedLineRanges = [8...9]
        var target = SnapshotConfig()
        SharedSnapshot(capturing: config).apply(to: &target)
        let sent = try #require(config.diffDocument)
        let received = try #require(target.diffDocument)
        #expect(target.code.contains("four") == false)
        #expect(received.additions == sent.additions)
        #expect(received.deletions == sent.deletions)
        #expect(received.rowKinds == sent.rowKinds)
    }

    @Test func redactingAHunkHeaderKeepsTheReceiversDiffStable() throws {
        var config = diffConfig()
        config.diffContextLines = 0
        config.redactedLineRanges = [4...4]
        var target = SnapshotConfig()
        SharedSnapshot(capturing: config).apply(to: &target)
        #expect(target.diffDocument?.rowKinds == config.diffDocument?.rowKinds)
    }

    @Test func nonDiffRedactionKeepsTheBarePlaceholder() {
        var config = SnapshotConfig(code: "+a\nb", language: .swift)
        config.redactedLineRanges = [1...1]
        #expect(config.sidecarText == "\(SnapshotConfig.redactedLinePlaceholder)\nb")
    }

    @Test func redactionHoldsUnderAFold() throws {
        func folded(_ secret: String, redacted: Bool) throws -> CGImage {
            var config = diffConfig()
            config.code = Self.patch.replacingOccurrences(of: "-four", with: "-\(secret)")
            config.diffContextLines = 0
            config.redactedLineRanges = redacted ? [8...8] : []
            return try render(config)
        }
        // Fresh values per attempt: the highlight cache would otherwise keep a perturbed frame.
        var hidden = 0
        for attempt in 1...RenderSettling.strictRenderAttempts {
            hidden = try FontLigatureTests.compareRenderedPixels(
                try folded("alpha\(attempt)", redacted: true),
                try folded("omega\(attempt)", redacted: true)
            ).differingPixels
            print("DIAG attempt \(attempt) hidden=\(hidden)")
            if hidden == 0 { break }
            if attempt == 1 {
                func png(_ image: CGImage) -> String {
                    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                        .base64EncodedString()
                }
                print("DIAG PNGA \(png(try folded("alpha1", redacted: true)))")
                print("DIAG PNGO \(png(try folded("omega1", redacted: true)))")
                let same = try FontLigatureTests.compareRenderedPixels(
                    try folded("alpha1", redacted: true), try folded("alpha1", redacted: true))
                print("DIAG same-secret differing=\(same.differingPixels) max=\(same.maxChannelDelta)")
                var plain = diffConfig()
                plain.code = Self.patch.replacingOccurrences(of: "-four", with: "-alpha1")
                plain.diffContextLines = 0
                print("DIAG PNGP \(png(try render(plain)))")
                print("DIAG fonts \(CodeFont.resolved(family: "JetBrains Mono", size: 14, ligatures: false))")
            }
            RenderSettling.settleFontCaches()
        }
        #expect(hidden == 0)
        let visible = try FontLigatureTests.compareRenderedPixels(
            try folded("alpha", redacted: false), try folded("omega", redacted: false))
        #expect(visible.differingPixels > 0)
    }

    @Test func blurBoxKeepsTheCanvasWhenTheControlsMove() throws {
        let settings = AppSettings(defaults: testDefaults())
        settings.config = diffConfig()
        settings.style.diffContextLines = 1
        settings.style.annotations = [
            Annotation(kind: .blur, start: CGPoint(x: 0.1, y: 0.4), end: CGPoint(x: 0.5, y: 0.5))
        ]
        let before = settings.config
        settings.diffContextSliderValue.wrappedValue = 0
        settings.diffStatsEnabled.wrappedValue = true
        let after = settings.config
        #expect(try differingPixels({ try render(before) }, { try render(after) }) == 0)
        #expect(!settings.style.showDiffStats)

        settings.style.annotations = []
        settings.diffStatsEnabled.wrappedValue = true
        #expect(settings.style.showDiffStats)
    }

    @Test func blurBoxLocksTheContextSlider() {
        let settings = AppSettings(defaults: testDefaults())
        settings.style.language = .diff
        settings.style.diffContextLines = 2
        settings.style.annotations = [
            Annotation(kind: .blur, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.5, y: 0.2))
        ]
        settings.diffContextSliderValue.wrappedValue = 0
        #expect(settings.style.diffContextLines == 2)
    }

    // MARK: - Text riders

    @Test func textRidersKeepTheFullPatch() {
        var config = diffConfig()
        config.diffContextLines = 0
        config.showDiffStats = true
        #expect(config.sidecarText == Self.patch)
        #expect(config.richClipboardText == Self.patch)
    }

    // MARK: - Carousel

    @Test func carouselSlidesDropWholePatchOptions() {
        var config = diffConfig()
        config.showDiffStats = true
        config.diffContextLines = 1
        config.highlightedLineRanges = [4...4]
        let slide = CarouselPaginator.slides(for: config.code, maxLinesPerSlide: 4)[1]

        let slideConfig = CarouselPaginator.slideConfig(
            config, slide: slide, at: 1, of: 2, cues: .none)
        #expect(slideConfig.code == slide.text)
        #expect(!slideConfig.showDiffStats)
        #expect(slideConfig.diffContextLines == nil)
        #expect(slideConfig.highlightedLineRanges == slide.localRanges([4...4]))
    }

    // MARK: - Persistence

    @Test func shareLinkRoundTripsAndClampsHostileValues() throws {
        var config = diffConfig()
        config.showDiffStats = true
        config.diffContextLines = 2
        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: config))
        var target = SnapshotConfig()
        try SnapshotShareLink.snapshot(from: url).apply(to: &target)
        #expect(target.showDiffStats)
        #expect(target.diffContextLines == 2)

        var encoded = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(SharedSnapshot(capturing: config)))
                as? [String: Any])
        encoded["diffContextLines"] = 900
        let hostile = try JSONSerialization.data(withJSONObject: encoded)
        var hostileTarget = SnapshotConfig()
        try JSONDecoder().decode(SharedSnapshot.self, from: hostile).apply(to: &hostileTarget)
        #expect(hostileTarget.diffContextLines == 5)
    }

    @Test func olderShareLinkPayloadReadsDefaults() throws {
        var encoded = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(SharedSnapshot(capturing: diffConfig())))
                as? [String: Any])
        encoded["showDiffStats"] = nil
        encoded["diffContextLines"] = nil
        let older = try JSONSerialization.data(withJSONObject: encoded)
        var target = SnapshotConfig()
        target.showDiffStats = true
        target.diffContextLines = 3
        try JSONDecoder().decode(SharedSnapshot.self, from: older).apply(to: &target)
        #expect(!target.showDiffStats)
        #expect(target.diffContextLines == nil)
    }

    @Test func windowStateClampsARestoredContextCount() throws {
        var state = EditorWindowState(config: diffConfig())
        state.diffContextLines = 99
        let restored = try #require(EditorWindowState.decoded(from: state.encoded()))
        #expect(restored.config().diffContextLines == 5)
    }

    @Test func settingsCodecClampsAndClearsTheContextCount() {
        let defaults = testDefaults()

        defaults.set(40, forKey: SettingsCodec.Keys.diffContextLines)
        #expect(SettingsCodec.readConfig(from: defaults).diffContextLines == 5)

        var config = SnapshotConfig()
        config.diffContextLines = nil
        SettingsCodec.persistStyle(config, to: defaults)
        #expect(defaults.object(forKey: SettingsCodec.Keys.diffContextLines) == nil)
    }

    // MARK: - Inspector binding

    @Test func sliderTopStopMeansAllLines() {
        let settings = AppSettings(defaults: testDefaults())
        let slider = settings.diffContextSliderValue
        #expect(slider.wrappedValue == AppSettings.diffContextSliderRange.upperBound)

        slider.wrappedValue = 2
        #expect(settings.style.diffContextLines == 2)
        #expect(slider.wrappedValue == 2)

        slider.wrappedValue = AppSettings.diffContextSliderRange.upperBound
        #expect(settings.style.diffContextLines == nil)
    }
}
