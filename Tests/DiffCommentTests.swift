import AppKit
import Foundation
import SwiftUI
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@Suite("Comments pinned to diff lines")
struct DiffCommentTests {
    private static let patch = """
        @@ -10,3 +10,3 @@ struct Client {
         ten
        -let token = "first"
        +let token = "second"
         twelve
        @@ -40,2 +40,3 @@ extension Client {
         forty
        +let retries = 3
         forty-one
        """

    private func diffConfig() -> SnapshotConfig {
        var config = SnapshotConfig(code: Self.patch, language: .diff)
        config.diffDecorations = true
        config.showLineNumbers = true
        return config
    }

    private func comment(
        row: Int, side: DiffLineAnchor.Side = .new, text: String = "why"
    ) -> Annotation {
        Annotation(
            kind: .text, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.1, y: 0.1),
            text: text, thickness: 3, lineAnchor: DiffLineAnchor(row: row, side: side))
    }

    private final class Box {
        var positions: [UUID: CGPoint] = [:]
    }

    /// Where the canvas places each pinned comment, read from the preference it reports.
    private func positions(_ config: SnapshotConfig) async throws -> [UUID: CGPoint] {
        let box = Box()
        let host = NSHostingView(
            rootView: SnapshotCanvas(config: config)
                .onPreferenceChange(DiffCommentPositionsKey.self) { box.positions = $0 })
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<40 where box.positions.isEmpty {
            try await Task.sleep(for: .milliseconds(25))
            host.layoutSubtreeIfNeeded()
        }
        return box.positions
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

    // MARK: - Layout

    @Test(arguments: [DiffViewMode.unified, .split])
    func aCommentFollowsItsLineInEitherLayout(_ view: DiffViewMode) async throws {
        var config = diffConfig()
        config.diffView = view
        let removed = comment(row: 3, side: .old)
        let added = comment(row: 4)
        let later = comment(row: 8)
        config.annotations = [removed, added, later]
        #expect(config.usesLineRows)

        let placed = try await positions(config)
        let first = try #require(placed[removed.id])
        let second = try #require(placed[added.id])
        let third = try #require(placed[later.id])
        #expect(third.y > second.y)
        // Split pairs the removal with its replacement on one row, in its own column.
        if view == .split {
            #expect(abs(first.y - second.y) < 0.001)
            #expect(first.x < second.x)
        } else {
            #expect(second.y > first.y)
        }
        // The cached point is ignored: the row decides.
        #expect(first != removed.start)
    }

    @Test func aFoldedOrMissingLineHidesItsComment() async throws {
        var config = diffConfig()
        let shown = comment(row: 8)
        let folded = comment(row: 3, side: .old)
        let missing = comment(row: 400)
        let wrongSide = comment(row: 8, side: .old)
        config.annotations = [shown, folded, missing, wrongSide]
        config.diffView = .split
        config.diffHunks = [2]
        let placed = try await positions(config)
        #expect(placed[shown.id] != nil)
        #expect(placed[folded.id] == nil)
        #expect(placed[missing.id] == nil)
        #expect(placed[wrongSide.id] == nil)
    }

    @Test func aCommentDrawsAndADetachedOneDrawsNothing() throws {
        let arrow = Annotation(
            kind: .arrow, start: CGPoint(x: 0.1, y: 0.9), end: CGPoint(x: 0.3, y: 0.8))
        var base = diffConfig()
        base.annotations = [arrow]
        var pinned = base
        pinned.annotations.append(comment(row: 4))
        var detached = base
        var gone = comment(row: 4)
        gone.lineAnchor?.isDetached = true
        detached.annotations.append(gone)

        #expect(try differingPixels({ try render(detached) }, { try render(base) }) == 0)
        #expect(
            try FontLigatureTests.compareRenderedPixels(render(pinned), render(base))
                .differingPixels > 0)
        #expect(try differingPixels({ try render(pinned) }, { try render(pinned) }) == 0)
    }

    @Test func otherContentNeverPlacesComments() {
        var config = diffConfig()
        config.annotations = [comment(row: 2)]
        #expect(!config.diffCommentSlots.isEmpty)
        config.language = .swift
        #expect(config.diffCommentSlots.isEmpty)
        config.language = .diff
        config.code = ""
        #expect(config.diffCommentSlots.isEmpty)
    }

    @Test func placementUsesTheRowAndTheCommentTextOnly() {
        let row = CGRect(x: 20, y: 100, width: 400, height: 22)
        let short = DiffCommentLayout.center(of: comment(row: 1, text: "ok"), rowFrame: row)
        let long = DiffCommentLayout.center(
            of: comment(row: 1, text: "a longer note"), rowFrame: row)
        #expect(short.y == row.midY)
        #expect(short.x > long.x)
        #expect(short.x < row.maxX)
        // Too wide for the row: it starts at the row's leading edge.
        let narrow = CGRect(x: 20, y: 100, width: 30, height: 22)
        let clamped = DiffCommentLayout.center(
            of: comment(row: 1, text: "wide note"), rowFrame: narrow)
        #expect(clamped.x > narrow.maxX - DiffCommentLayout.trailingInset)
    }

    @Test func aCommentOnARedactedLineShowsOnlyItsOwnText() throws {
        var config = diffConfig()
        config.redactedLineRanges = [3...3]
        config.annotations = [comment(row: 3, side: .old, text: "rotated")]
        var other = config
        other.code = Self.patch.replacingOccurrences(of: "\"first\"", with: "\"FIRST\"")
        #expect(try differingPixels({ try render(config) }, { try render(other) }) == 0)
    }

    // MARK: - Editing

    @Test @MainActor func editsMoveCommentsAndDetachTheEditedLine() {
        let settings = AppSettings(defaults: testDefaults())
        var config = diffConfig()
        let pinned = comment(row: 8)
        let edited = comment(row: 3, side: .old)
        config.annotations = [pinned, edited]
        settings.config = config
        let generation = settings.anchorRebaseGeneration

        settings.documentCode = " zero\n" + settings.documentCode
        #expect(settings.style.annotations.map { $0.lineAnchor?.row } == [9, 4])
        #expect(settings.anchorRebaseGeneration != generation)

        settings.documentCode = settings.documentCode.replacingOccurrences(
            of: "\"first\"", with: "\"FIRST\"")
        let anchors = settings.style.annotations.compactMap(\.lineAnchor)
        #expect(anchors.map(\.row) == [9, 4])
        #expect(anchors.map(\.isDetached) == [false, true])

        // A config write brings its own marks for its own text, as a new window's seed does.
        let seeded = AppSettings(defaults: testDefaults())
        var style = config
        style.code = ""
        seeded.config = style
        seeded.config = config
        #expect(seeded.style.annotations.compactMap(\.lineAnchor?.row) == [8, 3])
    }

    @Test func theCaretRowCountsLineFeeds() {
        let text = "one\ntwo\r\nthree"
        #expect(EditorView.caretRow(in: text, at: 0) == 1)
        #expect(EditorView.caretRow(in: text, at: 4) == 2)
        #expect(EditorView.caretRow(in: text, at: 9) == 3)
        #expect(EditorView.caretRow(in: text, at: 500) == 3)
        #expect(EditorView.caretRow(in: text, at: -2) == 1)
    }

    // MARK: - Command

    @Test @MainActor func theCommandIsShiftCommandMAndNeedsADiff() {
        let command = VitrineCommand.commentOnLine
        #expect(command.keyEquivalent == "m")
        #expect(command.modifiers == [.command, .shift])
        #expect(command.isEditorScoped)

        var config = diffConfig()
        #expect(
            EditorCommandResponder.canPerform(command, isEditorKey: true, config: config))
        #expect(
            !EditorCommandResponder.canPerform(command, isEditorKey: false, config: config))
        config.language = .swift
        #expect(
            !EditorCommandResponder.canPerform(command, isEditorKey: true, config: config))
        config.language = .diff
        config.code = ""
        #expect(
            !EditorCommandResponder.canPerform(command, isEditorKey: true, config: config))

        let edit = makeIsolatedAppMenu().make().items.compactMap(\.submenu).first {
            $0.title == "Edit"
        }
        let item = edit?.items.first { $0.accessibilityIdentifier() == "command-commentOnLine" }
        #expect(item?.keyEquivalent == "m")
        #expect(item?.keyEquivalentModifierMask == [.command, .shift])
    }

    // MARK: - Persistence

    @Test func commentsSurviveLinksAndWindowRestoration() throws {
        var config = diffConfig()
        config.annotations = [comment(row: 4)]
        let link = try SnapshotShareLink.snapshot(
            from: SnapshotShareLink.url(for: SharedSnapshot(capturing: config)))
        var target = SnapshotConfig()
        link.apply(to: &target)
        #expect(target.annotations.first?.lineAnchor == DiffLineAnchor(row: 4, side: .new))

        let restored = try #require(
            EditorWindowState.decoded(from: EditorWindowState(config: config).encoded()))
        #expect(
            restored.config().annotations.first?.lineAnchor == DiffLineAnchor(row: 4, side: .new))
    }
}
