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
        let second = try render(config)

        #expect(first.height > plain.height)
        #expect(first.width == plain.width)
        let comparison = try FontLigatureTests.compareRenderedPixels(first, second)
        #expect(comparison.differingPixels == 0)
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
        var config = diffConfig()
        let all = try render(config)
        config.diffContextLines = 5
        let comparison = try FontLigatureTests.compareRenderedPixels(
            all, try render(config))
        #expect(comparison.differingPixels == 0)
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
        #expect(!config.diffOptionsApply)
        #expect(config.diffDocument == nil)
        #expect(!config.usesLineRows)

        config.diffDecorations = true
        #expect(config.diffOptionsApply)
        #expect(config.diffDocument != nil)

        config.language = .terminal
        #expect(!config.diffOptionsApply)
        config.language = .diff
        config.foregroundImage = ImageReference(fileName: "x.png")
        #expect(!config.diffOptionsApply)
    }

    @Test func diffLanguageWithoutBandsStillFolds() {
        var config = SnapshotConfig(code: Self.patch, language: .diff)
        #expect(!config.usesLineRows)
        config.diffContextLines = 1
        #expect(config.usesLineRows)
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

        let slideConfig = ExportManager.carouselSlideConfig(config, slide: slide)
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
