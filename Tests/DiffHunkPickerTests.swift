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
        #expect(config.diffLineNumbers == .rows)
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
        // Old drops the new side's gutter, so the card narrows.
        var old = split
        old.diffLineNumbers = .old
        #expect(try render(old).width < render(split).width)
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
        #expect(slideConfig.diffLineNumbers == .rows)
    }

    // MARK: - Stale picks

    @Test func picksPastTheLastHunkNeverFoldEverything() throws {
        let document = DiffDocument(source: Self.patch)
        var stale = diffConfig()
        stale.diffHunks = [5]
        #expect(stale.diffShownHunks(count: 2) == nil)
        #expect(stale.diffDisplayRows(of: document) == nil)
        stale.diffHunks = [2, 5]
        #expect(stale.diffShownHunks(count: 2) == [2])

        var single = diffConfig()
        single.code = "@@ -1,2 +1,2 @@\n one\n-two\n+TWO"
        single.diffHunks = [2]
        var plain = single
        plain.diffHunks = nil
        #expect(try differingPixels({ try render(single) }, { try render(plain) }) == 0)
    }

    @Test func aPickBelongsToOnePatch() {
        var config = diffConfig()
        config.diffHunks = [2]
        config.clearContentMarks()
        #expect(config.diffHunks == nil)

        let settings = AppSettings(defaults: testDefaults())
        settings.config = diffConfig()
        settings.diffHunkShown(1, of: 2).wrappedValue = false
        #expect(settings.style.diffHunks == [2])
        // An edit inside a hunk keeps the pick; one that changes the hunk count drops it.
        settings.documentCode += "\n context"
        #expect(settings.style.diffHunks == [2])
        settings.config.code = "@@ -1 +1 @@\n-a\n+b"
        #expect(settings.style.diffHunks == nil)

        settings.config = diffConfig()
        settings.diffHunkShown(1, of: 2).wrappedValue = false
        settings.documentCode = "@@ -1 +1 @@\n-a\n+b"
        #expect(settings.style.diffHunks == nil)
    }

    @Test func parsesAreSharedAcrossStyleChanges() {
        let cache = DiffLayoutCache()
        let code = Self.patch + "\n"
        #expect(cache.hunks(in: code).count == 2)
        _ = cache.document(for: code)
        _ = cache.gutterLabels(.both, code: code, firstLineNumber: 1, redacting: [])
        _ = cache.gutterLabels(.both, code: code, firstLineNumber: 1, redacting: [])
        #expect(cache.misses == 1)
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

    @Test func numberingIsItsOwnSettingAndLeavesTheGutterSwitchAlone() {
        let settings = AppSettings(defaults: testDefaults())
        settings.config = diffConfig()
        settings.style.showLineNumbers = false
        let picker = settings.diffLineNumbersSelection
        #expect(picker.wrappedValue == .rows)

        picker.wrappedValue = .old
        #expect(settings.style.diffLineNumbers == .old)
        #expect(!settings.style.showLineNumbers)
        #expect(settings.style.diffFileNumbering == nil)
        settings.style.showLineNumbers = true
        #expect(settings.style.diffFileNumbering == .old)
        settings.style.language = .swift
        #expect(settings.style.diffFileNumbering == nil)
        settings.style.language = .diff

        picker.wrappedValue = .rows
        #expect(settings.style.diffFileNumbering == nil)

        settings.style.annotations = [
            Annotation(kind: .blur, start: CGPoint(x: 0.1, y: 0.4), end: CGPoint(x: 0.5, y: 0.5))
        ]
        picker.wrappedValue = .new
        #expect(settings.style.diffLineNumbers == .rows)
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
        encoded["diffLineNumbers"] = "sideways"
        var target = SnapshotConfig()
        target.diffLineNumbers = .both
        try JSONDecoder().decode(
            SharedSnapshot.self, from: JSONSerialization.data(withJSONObject: encoded)
        ).apply(to: &target)
        #expect(target.diffHunks == [1, 3])
        #expect(target.diffLineNumbers == .rows)
    }

    @Test func settingsKeepTheNumberingButNeverTheHunkPick() {
        let defaults = testDefaults()
        var config = SnapshotConfig()
        config.diffHunks = [2]
        config.diffLineNumbers = .both
        SettingsCodec.persistStyle(config, to: defaults)
        let read = SettingsCodec.readConfig(from: defaults)
        #expect(read.diffHunks == nil)
        #expect(read.diffLineNumbers == .both)
        #expect(defaults.object(forKey: "diffHunks") == nil)

        SettingsCodec.persistStyle(SnapshotConfig(), to: defaults)
        #expect(SettingsCodec.readConfig(from: defaults).diffLineNumbers == .rows)
    }

    @Test func windowStateRestoresThePickAndDropsHostileValues() throws {
        var state = EditorWindowState(config: diffConfig())
        state.diffHunks = [0, 4, 4]
        let restored = try #require(EditorWindowState.decoded(from: state.encoded()))
        #expect(restored.config().diffHunks == [4])
        #expect(restored.config().diffLineNumbers == .rows)

        let settings = AppSettings(defaults: testDefaults())
        var picked = diffConfig()
        picked.diffHunks = [2]
        settings.config = EditorWindowState(config: picked).config()
        #expect(settings.style.diffHunks == [2])
    }
}
