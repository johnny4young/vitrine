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

    private func placed(_ text: String, row: CGRect) throws -> DiffCommentLayout.Placement {
        let note = comment(row: 1, text: text)
        return try #require(DiffCommentLayout.place([(note, row)])[note.id])
    }

    @Test func placementUsesTheRowAndTheCommentTextOnly() throws {
        let row = CGRect(x: 20, y: 100, width: 400, height: 22)
        let short = try placed("ok", row: row)
        let long = try placed("a longer note", row: row)
        #expect(short.center.y == row.midY)
        #expect(short.frame.maxX == long.frame.maxX)
        #expect(short.frame.minX > long.frame.minX)
        #expect(short.frame.maxX <= row.maxX)
    }

    @Test func aLongCommentWrapsInsideItsRow() throws {
        let row = CGRect(x: 20, y: 100, width: 300, height: 22)
        let text = String(repeating: "a long comment that keeps going ", count: 6)
        let long = try placed(text, row: row)
        #expect(long.frame.minX >= row.minX)
        #expect(long.frame.maxX <= row.maxX)
        #expect(long.frame.height > row.height * 2)
        #expect(long.textWidth < long.frame.width)
        // A row narrower than any comment still starts it on the row.
        let narrow = CGRect(x: 20, y: 100, width: 30, height: 22)
        #expect(try placed("wide note", row: narrow).frame.minX == narrow.minX)
    }

    @Test func commentsOnNeighboringLinesDoNotOverlap() {
        let first = comment(row: 4, text: "first comment")
        let second = comment(row: 5, text: "second comment")
        let third = comment(row: 6, text: "third")
        let rows = (0..<3).map { CGRect(x: 20, y: 100 + CGFloat($0) * 18, width: 600, height: 18) }
        let placed = DiffCommentLayout.place([
            (second, rows[1]), (first, rows[0]), (third, rows[2]),
        ])
        let frames = [first, second, third].compactMap { placed[$0.id]?.frame }
        #expect(frames.count == 3)
        for (index, frame) in frames.enumerated() {
            #expect(frame.minX >= rows[index].minX)
            for other in frames[(index + 1)...] { #expect(!frame.intersects(other)) }
        }
        // The first on the card keeps its spot at the trailing edge.
        #expect(frames[0].maxX == rows[0].maxX - DiffCommentLayout.trailingInset)
    }

    @Test func onlyShownDiffRowsTakeComments() {
        var config = diffConfig()
        #expect(config.showsDiffRow(3))
        #expect(!config.showsDiffRow(0))
        #expect(!config.showsDiffRow(40))
        config.diffHunks = [2]
        #expect(!config.showsDiffRow(3))
        #expect(config.showsDiffRow(8))
        config.language = .swift
        #expect(!config.showsDiffRow(8))
    }

    @Test @MainActor func theOverlayHandlesOnlyDrawnCommentsAndKeepsThemInPlace() {
        let free = Annotation(kind: .text, start: .zero, end: .zero, text: "free")
        let pinned = comment(row: 4)
        let placed = [pinned.id: CGPoint(x: 0.7, y: 0.4)]
        #expect(AnnotationEditingOverlay.isDrawn(free, placed: [:]))
        #expect(!AnnotationEditingOverlay.isDrawn(pinned, placed: [:]))
        #expect(AnnotationEditingOverlay.isDrawn(pinned, placed: placed))

        let shown = AnnotationEditingOverlay.shown(pinned, placed: placed)
        #expect(shown.start == CGPoint(x: 0.7, y: 0.4))
        var dragged = shown
        dragged.start = CGPoint(x: 0.1, y: 0.9)
        dragged.text = "edited"
        let stored = AnnotationEditingOverlay.stored(dragged, over: pinned, placed: placed)
        #expect(stored.start == pinned.start)
        #expect(stored.text == "edited")
        #expect(AnnotationEditingOverlay.stored(dragged, over: free, placed: placed) == dragged)
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

        settings.documentCode = " zero\n" + settings.documentCode
        #expect(settings.style.annotations.map { $0.lineAnchor?.row } == [9, 4])

        let typed = settings.documentCode
        settings.documentCode = typed.replacingOccurrences(of: "\"first\"", with: "\"FIRST\"")
        let anchors = settings.style.annotations.compactMap(\.lineAnchor)
        #expect(anchors.map(\.row) == [9, 4])
        #expect(anchors.map(\.isDetached) == [false, true])
        // Undoing the typo puts the line back, and the comment with it.
        settings.documentCode = typed
        #expect(settings.style.annotations.compactMap(\.lineAnchor?.isDetached) == [false, false])

        // A config write brings its own marks for its own text, as a new window's seed does.
        let seeded = AppSettings(defaults: testDefaults())
        var style = config
        style.code = ""
        seeded.config = style
        seeded.config = config
        #expect(seeded.style.annotations.compactMap(\.lineAnchor?.row) == [8, 3])
    }

    @Test @MainActor func annotationUndoFollowsEditsInsteadOfResetting() throws {
        let settings = AppSettings(defaults: testDefaults())
        var config = diffConfig()
        let pinned = comment(row: 8)
        let blur = Annotation(
            kind: .blur, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.4, y: 0.3))
        config.annotations = [pinned, blur]
        settings.config = config
        var history = AnnotationHistory()
        settings.lineEditObserver = { history.follow($0) }

        // Delete the blur box, then add a line above the comment.
        history.beginEdit(settings.style.annotations)
        settings.style.annotations.removeMark(blur.id)
        history.endEdit(current: settings.style.annotations)
        settings.documentCode = " zero\n" + settings.documentCode

        let undone = history.undo(current: settings.style.annotations)
        let restored = try #require(undone)
        #expect(restored.contains { $0.id == blur.id })
        #expect(restored.first { $0.id == pinned.id }?.lineAnchor?.row == 9)
        #expect(settings.style.annotations.first?.lineAnchor?.row == 9)
        // Free marks alone never parse the text.
        var plain = AnnotationHistory()
        plain.record([blur])
        plain.follow {
            Issue.record("parsed an edit no comment needs")
            return .init(from: "", to: "")
        }
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
