import AppKit
import Foundation
import SwiftUI
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@Suite("Diff hunk picker and numbering")
struct DiffHunkPickerTests {
    private static let patch = """
        --- a/Sources/Client.swift
        +++ b/Sources/Client.swift
        @@ -10,3 +10,3 @@ struct Client {
         ten
        -eleven
        +ELEVEN
         twelve
        @@ -40,3 +40,4 @@ extension Client {
         forty
        -let token = "first"
        +let token = "second"
        +let retries = 3
         forty-two
        """

    private func diffConfig() -> SnapshotConfig {
        var config = SnapshotConfig(code: Self.patch, language: .diff)
        config.diffDecorations = true
        config.showLineNumbers = true
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

    @Test func defaultsDrawEveryRowAsBefore() throws {
        let config = diffConfig()
        #expect(config.diffHunks == nil)
        #expect(config.diffLineNumbers == nil)
        #expect(config.diffDocument == nil)
        #expect(config.diffDisplayRows(of: DiffDocument(source: Self.patch)) == nil)

        var everyHunk = config
        everyHunk.diffHunks = [1, 2]
        #expect(try differingPixels({ try render(config) }, { try render(everyHunk) }) == 0)
    }

    @Test func numberingWithoutAGutterRendersAsBefore() throws {
        var config = diffConfig()
        config.showLineNumbers = false
        var numbered = config
        numbered.diffLineNumbers = .both
        #expect(numbered.diffFileNumbering == nil)
        #expect(try differingPixels({ try render(config) }, { try render(numbered) }) == 0)
    }

    @Test(arguments: [DiffViewMode.unified, .split])
    func anUnpickedHunkFoldsToOneRow(_ view: DiffViewMode) throws {
        var all = diffConfig()
        all.diffView = view
        var picked = all
        picked.diffHunks = [2]
        let full = try render(all)
        let folded = try render(picked)
        #expect(folded.height < full.height)
        #expect(try differingPixels({ try render(picked) }, { try render(picked) }) == 0)
    }

    /// A folded hunk draws only its counts, so its text cannot change a pixel, redacted or not.
    @Test(arguments: [false, true])
    func aFoldedHunkShowsNoneOfItsText(_ redacted: Bool) throws {
        func folded(_ secret: String) throws -> CGImage {
            var config = diffConfig()
            config.code = Self.patch.replacingOccurrences(of: "\"first\"", with: "\"\(secret)\"")
                .replacingOccurrences(of: "extension Client", with: "extension \(secret)")
            config.diffHunks = [1]
            config.redactedLineRanges = redacted ? [8...9] : []
            return try render(config)
        }
        #expect(try differingPixels({ try folded("alpha") }, { try folded("omega") }) == 0)

        var shown = diffConfig()
        shown.diffHunks = [2]
        var other = shown
        other.code = Self.patch.replacingOccurrences(of: "\"first\"", with: "\"other\"")
        #expect(
            try FontLigatureTests.compareRenderedPixels(render(shown), render(other))
                .differingPixels > 0)
    }

    @Test(arguments: [DiffLineNumbers.old, .new, .both])
    func fileNumberingReplacesPatchRows(_ numbering: DiffLineNumbers) throws {
        let rows = diffConfig()
        var numbered = rows
        numbered.diffLineNumbers = numbering
        #expect(numbered.usesLineRows)
        #expect(numbered.diffDocument != nil)
        let plain = try render(rows)
        let filed = try render(numbered)
        // Both needs two number columns, so its card is wider.
        #expect((filed.width > plain.width) == (numbering == .both))
        if numbering != .both {
            #expect(try FontLigatureTests.compareRenderedPixels(plain, filed).differingPixels > 0)
        }
        #expect(try differingPixels({ try render(numbered) }, { try render(numbered) }) == 0)
    }

    @Test func splitBothMatchesTheSplitDefault() throws {
        var split = diffConfig()
        split.diffView = .split
        var both = split
        both.diffLineNumbers = .both
        #expect(try differingPixels({ try render(split) }, { try render(both) }) == 0)
        var old = split
        old.diffLineNumbers = .old
        #expect(
            try FontLigatureTests.compareRenderedPixels(render(split), render(old))
                .differingPixels > 0)
    }

    @Test func optionsApplyOnlyToDiffs() {
        var swift = diffConfig()
        swift.language = .swift
        swift.diffHunks = [1]
        swift.diffLineNumbers = .old
        #expect(swift.diffFileNumbering == nil)
        #expect(swift.diffDocument == nil)
    }

    @Test func textRidersKeepTheFullPatch() {
        var config = diffConfig()
        config.diffHunks = [2]
        #expect(config.sidecarText == Self.patch)
    }

    @Test func carouselSlidesShowEveryHunkWithPatchRows() {
        var config = diffConfig()
        config.diffHunks = [2]
        config.diffLineNumbers = .both
        let slide = CarouselPaginator.slides(for: config.code, maxLinesPerSlide: 4)[1]
        let slideConfig = CarouselPaginator.slideConfig(
            config, slide: slide, at: 1, of: 2, cues: .none)
        #expect(slideConfig.diffHunks == nil)
        #expect(slideConfig.diffLineNumbers == nil)
    }

    // MARK: - Inspector bindings

    @Test func checkboxesPickHunksAndKeepOneShown() {
        let settings = AppSettings(defaults: testDefaults())
        settings.config = diffConfig()
        let first = settings.diffHunkShown(1, of: 2)
        let second = settings.diffHunkShown(2, of: 2)
        #expect(first.wrappedValue && second.wrappedValue)

        first.wrappedValue = false
        #expect(settings.style.diffHunks == [2])
        second.wrappedValue = false
        #expect(settings.style.diffHunks == [2])
        first.wrappedValue = true
        #expect(settings.style.diffHunks == nil)

        settings.style.annotations = [
            Annotation(kind: .blur, start: CGPoint(x: 0.1, y: 0.4), end: CGPoint(x: 0.5, y: 0.5))
        ]
        first.wrappedValue = false
        #expect(settings.style.diffHunks == nil)
    }

    @Test func numberingPickerDrivesTheGutter() {
        let settings = AppSettings(defaults: testDefaults())
        settings.config = diffConfig()
        let picker = settings.diffLineNumbersSelection
        #expect(picker.wrappedValue == nil)
        settings.style.diffView = .split
        #expect(picker.wrappedValue == .both)

        picker.wrappedValue = .hidden
        #expect(!settings.style.showLineNumbers)
        #expect(picker.wrappedValue == .hidden)
        picker.wrappedValue = .old
        #expect(settings.style.showLineNumbers)
        #expect(settings.style.diffLineNumbers == .old)
        picker.wrappedValue = nil
        #expect(settings.style.diffLineNumbers == .old)

        settings.style.annotations = [
            Annotation(kind: .blur, start: CGPoint(x: 0.1, y: 0.4), end: CGPoint(x: 0.5, y: 0.5))
        ]
        picker.wrappedValue = .new
        #expect(settings.style.diffLineNumbers == .old)
    }

    // MARK: - Persistence

    @Test func linksOmitBothOptionsUntilSetAndDropHostileValues() throws {
        func keys(_ config: SnapshotConfig) throws -> [String: Any] {
            try #require(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(SharedSnapshot(capturing: config)))
                    as? [String: Any])
        }
        let plain = try keys(diffConfig())
        #expect(plain["diffHunks"] == nil)
        #expect(plain["diffLineNumbers"] == nil)

        var encoded = plain
        encoded["diffHunks"] = [0, 3, 3, 1, 50_000]
        encoded["diffLineNumbers"] = "none"
        var target = SnapshotConfig()
        try JSONDecoder().decode(
            SharedSnapshot.self, from: JSONSerialization.data(withJSONObject: encoded)
        ).apply(to: &target)
        #expect(target.diffHunks == [1, 3])
        #expect(target.diffLineNumbers == nil)
    }

    @Test func settingsCodecWritesAndClearsBothOptions() {
        let defaults = testDefaults()
        var config = SnapshotConfig()
        config.diffHunks = [2]
        config.diffLineNumbers = .both
        SettingsCodec.persistStyle(config, to: defaults)
        let read = SettingsCodec.readConfig(from: defaults)
        #expect(read.diffHunks == [2])
        #expect(read.diffLineNumbers == .both)

        SettingsCodec.persistStyle(SnapshotConfig(), to: defaults)
        #expect(defaults.object(forKey: SettingsCodec.Keys.diffHunks) == nil)
        #expect(defaults.object(forKey: SettingsCodec.Keys.diffLineNumbers) == nil)
    }

    @Test func windowStateDropsHostileValues() throws {
        var state = EditorWindowState(config: diffConfig())
        state.diffHunks = [0, 4, 4]
        state.diffLineNumbers = .hidden
        let restored = try #require(EditorWindowState.decoded(from: state.encoded()))
        #expect(restored.config().diffHunks == [4])
        #expect(restored.config().diffLineNumbers == nil)
    }
}
