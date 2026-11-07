import CoreGraphics
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@Suite("Annotation mark toolbar placement")
struct AnnotationMarkToolbarPlacementTests {
    private let stage = CGRect(x: 0, y: 0, width: 800, height: 500)
    private let toolbar = CGSize(width: 180, height: 34)

    private func placed(
        beside mark: CGRect, avoiding: [CGRect] = [], in bounds: CGRect? = nil
    ) -> (frame: CGRect, side: AnnotationMarkToolbarPlacement.Side) {
        let placement = AnnotationMarkToolbarPlacement.place(
            toolbar, beside: mark, avoiding: avoiding, in: bounds ?? stage)
        return (CGRect(origin: placement.origin, size: toolbar), placement.side)
    }

    @Test func sitsCenteredAboveAMarkWithRoom() {
        let mark = CGRect(x: 300, y: 200, width: 120, height: 60)
        let (frame, side) = placed(beside: mark)
        #expect(side == .above)
        #expect(frame.maxY <= mark.minY)
        #expect(frame.midX == mark.midX)
        #expect(stage.contains(frame))
    }

    @Test func flipsBelowAMarkAtTheTopOfTheStage() {
        let mark = CGRect(x: 300, y: 4, width: 120, height: 60)
        let (frame, side) = placed(beside: mark)
        #expect(side == .below)
        #expect(frame.minY >= mark.maxY)
        #expect(stage.contains(frame))
    }

    @Test func movesBesideAMarkTallerThanTheRoomAboveAndBelow() {
        let mark = CGRect(x: 100, y: 10, width: 40, height: 480)
        let (frame, side) = placed(beside: mark)
        #expect(side == .after)
        #expect(frame.minX >= mark.maxX)
        #expect(stage.contains(frame))
        let flush = CGRect(x: 650, y: 10, width: 140, height: 480)
        #expect(placed(beside: flush).frame.maxX <= flush.minX)
    }

    @Test func slidesInsideTheStageNearAnEdge() {
        let mark = CGRect(x: 760, y: 300, width: 40, height: 40)
        let frame = placed(beside: mark).frame
        #expect(stage.contains(frame))
        #expect(!frame.intersects(mark))
    }

    @Test func staysOnStageWhenTheMarkFillsIt() {
        let (frame, side) = placed(beside: stage)
        #expect(side == .overlapping)
        #expect(stage.contains(frame))
    }

    @Test func followsAStageThatDoesNotStartAtTheOrigin() {
        let offsetStage = stage.offsetBy(dx: 40, dy: 30)
        let mark = CGRect(x: 360, y: 40, width: 80, height: 40)
        let frame = placed(beside: mark, in: offsetStage).frame
        #expect(offsetStage.contains(frame))
        #expect(!frame.intersects(mark))
    }

    @Test func keepsOffTheStatusCapsule() {
        let capsule = CGRect(x: 250, y: 450, width: 300, height: 30)
        let mark = CGRect(x: 360, y: 10, width: 80, height: 420)
        #expect(placed(beside: mark).side == .below)
        let (frame, side) = placed(beside: mark, avoiding: [capsule])
        #expect(side == .after)
        #expect(!frame.intersects(capsule))
        #expect(!frame.intersects(mark))
    }

    @Test func curvedArrowBoundsFollowTheBowAndHead() {
        let canvas = CGSize(width: 800, height: 500)
        let arrow = Annotation(
            kind: .curvedArrow, start: CGPoint(x: 0.2, y: 0.5), end: CGPoint(x: 0.6, y: 0.5))
        let geometry = AnnotationInteractionGeometry(annotation: arrow, canvasSize: canvas)
        let drawn = AnnotationMarkBounds.drawn(arrow, in: canvas)
        #expect(drawn.height > geometry.selectionBounds.height + arrow.thickness)
        #expect(geometry.chromeBounds.contains(drawn))
    }

    /// Wherever a side has room, the toolbar stays off the drawn mark and its handles.
    @Test func neverCoversAMarkThatLeavesRoomOnSomeSide() {
        let canvas = stage.size
        let marks: [Annotation] = [
            Annotation(
                kind: .arrow, start: .zero, end: CGPoint(x: 0.5, y: 0), thickness: 28),
            Annotation(
                kind: .curvedArrow, start: .zero, end: CGPoint(x: 0.25, y: 0.1), thickness: 12),
            Annotation(kind: .text, start: .zero, end: .zero, text: "Callout text", thickness: 20),
            Annotation(kind: .sticker, start: .zero, end: .zero, text: "🚀", thickness: 28),
            Annotation(kind: .counter, start: .zero, end: .zero, thickness: 28, number: 3),
            Annotation(
                kind: .rectangle, start: .zero, end: CGPoint(x: 0.3, y: 0.2), thickness: 28),
            Annotation(kind: .measure, start: .zero, end: CGPoint(x: 0.2, y: 0.3)),
        ]
        var sided = 0
        var total = 0
        for template in marks {
            for x in stride(from: 0.0, through: 1, by: 0.1) {
                for y in stride(from: 0.0, through: 1, by: 0.1) {
                    var mark = template
                    mark.nudge(
                        by: CGSize(width: x * canvas.width, height: y * canvas.height), in: canvas)
                    let geometry = AnnotationInteractionGeometry(
                        annotation: mark, canvasSize: canvas)
                    let (frame, side) = placed(beside: geometry.chromeBounds)
                    total += 1
                    #expect(stage.contains(frame))
                    guard side != .overlapping else { continue }
                    sided += 1
                    let reach = AnnotationInteractionGeometry.handleDiameter / 2
                    let keepOff =
                        [AnnotationMarkBounds.drawn(mark, in: canvas)]
                        + [geometry.start, geometry.end].map {
                            CGRect(
                                x: $0.x - reach, y: $0.y - reach, width: reach * 2,
                                height: reach * 2)
                        }
                    #expect(
                        !keepOff.contains(where: frame.intersects), "\(mark.kind) at \(x), \(y)")
                }
            }
        }
        #expect(sided > total / 2, "Too few placements had room to test")
    }

    @Test(arguments: Annotation.Kind.allCases)
    func chromeHoldsTheHandlesAndDeleteBadge(kind: Annotation.Kind) {
        let canvas = CGSize(width: 400, height: 200)
        let corners = [
            (CGPoint(x: 0.7, y: 0.6), CGPoint(x: 0.2, y: 0.3)), (CGPoint(x: 1, y: 0), .zero),
        ]
        for (start, end) in corners {
            let mark = Annotation(kind: kind, start: start, end: end)
            let geometry = AnnotationInteractionGeometry(annotation: mark, canvasSize: canvas)
            let chrome = geometry.chromeBounds
            #expect(chrome.contains(geometry.selectionBounds))
            if !kind.isPointPlaced {
                let reach = AnnotationInteractionGeometry.handleDiameter / 2
                for point in [geometry.start, geometry.end] {
                    #expect(chrome.contains(point.square(radius: reach)))
                }
            }
            let badge = geometry.deleteBadgeCenter.square(
                radius: AnnotationInteractionGeometry.deleteBadgeSize / 2)
            #expect(chrome.contains(badge))
        }
    }

    /// Applies size changes the way `AnnotationSizeSlider` does and counts the undo steps.
    private func undoSteps(dragging: Bool, changes: Int) -> Int {
        var history = AnnotationHistory()
        var tracker = SliderEditTracker()
        var marks = [Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 0.5, y: 0.5))]
        if dragging { _ = tracker.editingChanged(true) }
        for _ in 0..<changes {
            history.beginEdit(marks)
            marks[0].thickness += 1
            if tracker.closesChange(fromPointer: dragging) { history.endEdit(current: marks) }
        }
        if dragging, tracker.editingChanged(false) { history.endEdit(current: marks) }
        var steps = 0
        while let previous = history.undo(current: marks) {
            marks = previous
            steps += 1
        }
        return steps
    }

    @Test func eachKeyboardSizeChangeIsItsOwnUndoStep() {
        #expect(undoSteps(dragging: false, changes: 3) == 3)
    }

    @Test func aPointerDragIsOneUndoStep() {
        #expect(undoSteps(dragging: true, changes: 3) == 1)
    }
}

extension CGPoint {
    fileprivate func square(radius: CGFloat) -> CGRect {
        CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
    }
}
