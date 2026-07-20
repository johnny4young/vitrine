import Foundation
import Testing

@testable import Vitrine

/// The annotation undo/redo stacks, extracted from `EditorView` so the
/// semantics are pinned without driving a view.
@Suite("Annotation history (undo/redo)")
struct AnnotationHistoryTests {
    private func mark(_ x: Double) -> Annotation {
        Annotation(kind: .arrow, start: CGPoint(x: x, y: 0), end: CGPoint(x: x, y: 1))
    }

    @Test func freshHistoryHasNothingToUndoOrRedo() {
        let history = AnnotationHistory()
        #expect(!history.canUndo)
        #expect(!history.canRedo)
    }

    @Test func undoAndRedoWalkTheStackBothWays() {
        var history = AnnotationHistory()
        let empty: [Annotation] = []
        let one = [mark(0.1)]
        let two = [mark(0.1), mark(0.2)]

        history.record(empty)  // before drawing the first mark
        history.record(one)  // before drawing the second

        #expect(history.undo(current: two) == one)
        #expect(history.undo(current: one) == empty)
        #expect(!history.canUndo)
        #expect(history.undo(current: empty) == nil, "undoing past the start must be a no-op")

        #expect(history.redo(current: empty) == one)
        #expect(history.redo(current: one) == two)
        #expect(!history.canRedo)
        #expect(history.redo(current: two) == nil, "redoing past the end must be a no-op")
    }

    /// The overlay records at the start of every gesture, including ones that change
    /// nothing (a click that only selects). Those must not each cost a dead ⌘Z.
    @Test func consecutiveIdenticalSnapshotsCoalesce() {
        var history = AnnotationHistory()
        let state = [mark(0.1)]
        history.record(state)
        history.record(state)
        history.record(state)

        #expect(history.undo(current: state) == state)
        #expect(!history.canUndo, "three identical records must leave a single undo step")
    }

    /// A record after an undo invalidates redo: replaying the old future would
    /// resurrect marks the new edit never knew about.
    @Test func recordingAfterUndoDropsTheRedoBranch() {
        var history = AnnotationHistory()
        let empty: [Annotation] = []
        let one = [mark(0.1)]
        history.record(empty)
        _ = history.undo(current: one)
        #expect(history.canRedo)

        history.record(empty + [mark(0.9)])
        #expect(!history.canRedo, "a new edit must drop the abandoned redo branch")
    }

    @Test func unchangedEditDoesNotCreateUndoOrInvalidateRedo() {
        var history = AnnotationHistory()
        let empty: [Annotation] = []
        let one = [mark(0.1)]
        history.record(empty)
        #expect(history.undo(current: one) == empty)
        #expect(history.canRedo)

        history.beginEdit(empty)
        history.endEdit(current: empty)

        #expect(!history.canUndo, "an unchanged interaction must not add a dead undo step")
        #expect(history.canRedo, "an unchanged interaction must preserve the redo branch")
        #expect(history.redo(current: empty) == one)
    }

    @Test func completedEditRecordsItsStartingState() {
        var history = AnnotationHistory()
        let empty: [Annotation] = []
        let one = [mark(0.1)]

        history.beginEdit(empty)
        history.endEdit(current: one)

        #expect(history.undo(current: one) == empty)
    }

    @Test func stackDepthIsCappedDroppingTheOldestState() {
        var history = AnnotationHistory()
        // One more state than the cap allows. Each is distinct (marks carry identity),
        // so the states are kept to compare against rather than rebuilt.
        let states = (0...AnnotationHistory.depthLimit).map { [mark(Double($0) / 1000)] }
        for state in states { history.record(state) }

        // The oldest state fell off the bottom: unwinding every step lands on
        // state 1, never state 0.
        var current = [mark(9)]
        var oldestReachable: [Annotation] = []
        var steps = 0
        while let previous = history.undo(current: current) {
            oldestReachable = previous
            current = previous
            steps += 1
        }
        #expect(steps == AnnotationHistory.depthLimit)
        #expect(oldestReachable == states[1])
    }

    @Test func resetClearsBothStacks() {
        var history = AnnotationHistory()
        history.record([])
        _ = history.undo(current: [mark(0.1)])
        #expect(history.canRedo)

        history.reset()
        #expect(!history.canUndo)
        #expect(!history.canRedo)
    }
}

/// The pure geometry behind moving the selected mark with the arrow keys.
@Suite("Annotation nudge")
struct AnnotationNudgeTests {
    private let canvas = CGSize(width: 400, height: 200)

    @Test func nudgeMovesTheWholeMarkByTheRequestedPoints() {
        var mark = Annotation(
            kind: .rectangle, start: CGPoint(x: 0.25, y: 0.5), end: CGPoint(x: 0.75, y: 0.9))
        mark.nudge(by: CGSize(width: 40, height: -20), in: canvas)
        // 40/400 = 0.1 of the width; -20/200 = -0.1 of the height.
        #expect(mark.start.x == 0.35)
        #expect(mark.end.x == 0.85)
        #expect(abs(mark.start.y - 0.4) < 1e-9)
        #expect(abs(mark.end.y - 0.8) < 1e-9)
    }

    /// The mark stops flush against the edge with its shape intact — clamping the
    /// endpoints independently would shear it (one end pinned, the other moving).
    @Test func nudgeStopsAtTheEdgeWithoutDeformingTheMark() {
        var mark = Annotation(
            kind: .rectangle, start: CGPoint(x: 0.6, y: 0.1), end: CGPoint(x: 0.9, y: 0.3))
        let width = mark.end.x - mark.start.x
        mark.nudge(by: CGSize(width: 400, height: 0), in: canvas)  // way past the edge

        #expect(mark.end.x == 1, "the leading edge parks flush against the canvas")
        #expect(abs((mark.end.x - mark.start.x) - width) < 1e-9, "the mark keeps its width")

        // And symmetrically against the near edge.
        mark.nudge(by: CGSize(width: -4000, height: 0), in: canvas)
        #expect(mark.start.x == 0)
        #expect(abs((mark.end.x - mark.start.x) - width) < 1e-9)
    }

    @Test func nudgeMovesAPointPlacedMarkAsASinglePoint() {
        var sticker = Annotation(
            kind: .sticker, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5))
        sticker.nudge(by: CGSize(width: 4, height: 4), in: canvas)
        #expect(sticker.start == sticker.end, "a point-placed mark stays a point")
        #expect(sticker.start.x == 0.51)
    }

    @Test func nudgeOnADegenerateCanvasIsANoOp() {
        var mark = Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 1, y: 1))
        mark.nudge(by: CGSize(width: 10, height: 10), in: .zero)
        #expect(mark.start == .zero)
        #expect(mark.end == CGPoint(x: 1, y: 1))
    }

    /// A mark already spanning the full canvas has nowhere to go.
    @Test func aFullBleedMarkCannotBeNudged() {
        var mark = Annotation(kind: .blur, start: .zero, end: CGPoint(x: 1, y: 1))
        mark.nudge(by: CGSize(width: 40, height: 40), in: canvas)
        #expect(mark.start == .zero)
        #expect(mark.end == CGPoint(x: 1, y: 1))
    }

    @Test func nudgeStepsAreFineAndCoarse() {
        #expect(Annotation.nudgeStep == 1)
        #expect(Annotation.coarseNudgeStep == 10)
    }
}

/// A duplicate gets its own identity and an offset so it reads as a new mark rather
/// than hiding under the original.
@Suite("Annotation duplicate")
struct AnnotationDuplicateTests {
    private let canvas = CGSize(width: 400, height: 200)

    @Test func duplicateGetsAFreshIdentityAndAnOffsetButKeepsItsStyle() {
        let original = Annotation(
            kind: .rectangle, start: CGPoint(x: 0.2, y: 0.2), end: CGPoint(x: 0.5, y: 0.6),
            color: RGBAColor(red: 0, green: 1, blue: 0, opacity: 1), thickness: 9)
        let copy = original.duplicated(in: canvas, counterNumber: 1)

        #expect(copy.id != original.id)
        #expect(copy.kind == original.kind)
        #expect(copy.color == original.color)
        #expect(copy.thickness == original.thickness)
        // 16/400 = 0.04 across, 16/200 = 0.08 down.
        #expect(abs(copy.start.x - 0.24) < 1e-9)
        #expect(abs(copy.start.y - 0.28) < 1e-9)
        #expect(copy.fingerprint != original.fingerprint, "the copy is visibly elsewhere")
    }

    /// A mark flush against the far corner has nowhere down-right to go; the copy
    /// must step back toward the origin rather than stack invisibly on the original.
    @Test func duplicateOfACornerMarkOffsetsBackTowardTheOrigin() {
        let corner = Annotation(
            kind: .rectangle, start: CGPoint(x: 0.9, y: 0.9), end: CGPoint(x: 1, y: 1))
        let copy = corner.duplicated(in: canvas, counterNumber: 1)

        #expect(copy.start != corner.start, "the copy must not hide under the original")
        #expect(copy.end.x < corner.end.x)
        #expect(copy.end.y < corner.end.y)
        // Shape preserved either way.
        #expect(abs((copy.end.x - copy.start.x) - 0.1) < 1e-9)
    }

    @Test func duplicatingACounterTakesTheNextBadgeNumber() {
        let badge = Annotation(
            kind: .counter, start: CGPoint(x: 0.4, y: 0.4), end: CGPoint(x: 0.4, y: 0.4),
            number: 3)
        #expect(badge.duplicated(in: canvas, counterNumber: 7).number == 7)
    }

    @Test func duplicatingANonCounterIgnoresTheBadgeNumber() {
        let arrow = Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 0.4, y: 0.4))
        #expect(arrow.duplicated(in: canvas, counterNumber: 7).number == arrow.number)
    }

    @Test func duplicateOfAPointPlacedMarkStaysAPoint() {
        let sticker = Annotation(
            kind: .sticker, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5),
            text: "🔥")
        let copy = sticker.duplicated(in: canvas, counterNumber: 1)
        #expect(copy.start == copy.end)
        #expect(copy.text == "🔥")
    }
}

/// Only marks painted in list order take part in z-order changes; blur and spotlight
/// are compositing effects at fixed depths, so reordering them would change nothing.
@Suite("Annotation z-order")
struct AnnotationZOrderTests {
    private func mark(_ kind: Annotation.Kind) -> Annotation {
        Annotation(kind: kind, start: .zero, end: CGPoint(x: 0.5, y: 0.5))
    }

    @Test func bringToFrontMovesTheMarkLastKeepingTheOthersInOrder() {
        let a = mark(.arrow)
        let b = mark(.rectangle)
        let c = mark(.text)
        var marks = [a, b, c]
        marks.moveMark(a.id, toFront: true)
        #expect(marks.map(\.id) == [b.id, c.id, a.id])
    }

    @Test func sendToBackMovesTheMarkFirstKeepingTheOthersInOrder() {
        let a = mark(.arrow)
        let b = mark(.rectangle)
        let c = mark(.text)
        var marks = [a, b, c]
        marks.moveMark(c.id, toFront: false)
        #expect(marks.map(\.id) == [c.id, a.id, b.id])
    }

    @Test func aMarkAlreadyAtTheEndHasNoMoveAvailable() {
        let a = mark(.arrow)
        let b = mark(.rectangle)
        let marks = [a, b]
        #expect(marks.frontmostMove(for: b.id) == nil, "b is already frontmost")
        #expect(marks.backmostMove(for: a.id) == nil, "a is already backmost")
        #expect(marks.frontmostMove(for: a.id) == 1)
        #expect(marks.backmostMove(for: b.id) == 0)
    }

    /// Blur and spotlight draw at fixed depths, so they have no draw order to change.
    @Test func compositingEffectsAreNotReorderable() {
        let blur = mark(.blur)
        let spotlight = mark(.spotlight)
        let arrow = mark(.arrow)
        var marks = [blur, spotlight, arrow]

        #expect(marks.frontmostMove(for: blur.id) == nil)
        #expect(marks.backmostMove(for: blur.id) == nil)
        #expect(marks.frontmostMove(for: spotlight.id) == nil)

        marks.moveMark(blur.id, toFront: true)
        #expect(marks.map(\.id) == [blur.id, spotlight.id, arrow.id], "the list is untouched")
    }

    /// An effect sitting at the end of the list is not "in front" of anything, so a
    /// lone painted mark must not be shuffled past it — that would look like nothing
    /// happened while still costing an undo step.
    @Test func onlyPaintedMarksBoundTheMove() {
        let arrow = mark(.arrow)
        let blur = mark(.blur)
        let marks = [arrow, blur]
        #expect(
            marks.frontmostMove(for: arrow.id) == nil,
            "the arrow is already the frontmost painted mark; the trailing blur is not above it")

        let text = mark(.text)
        var three = [blur, arrow, text]
        #expect(three.frontmostMove(for: arrow.id) == 2)
        three.moveMark(arrow.id, toFront: true)
        #expect(three.map(\.id) == [blur.id, text.id, arrow.id])
    }

    @Test func anUnknownIdIsANoOp() {
        let a = mark(.arrow)
        var marks = [a]
        #expect(marks.frontmostMove(for: UUID()) == nil)
        marks.moveMark(UUID(), toFront: true)
        #expect(marks.map(\.id) == [a.id])
    }

    @Test func everyKindDeclaresWhetherItTakesPartInTheDrawOrder() {
        for kind in Annotation.Kind.allCases {
            let expected = kind != .blur && kind != .spotlight
            #expect(kind.participatesInZOrder == expected, "\(kind) must be explicit")
        }
    }
}
