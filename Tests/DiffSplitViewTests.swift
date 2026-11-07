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
