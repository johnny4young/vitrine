import CoreGraphics
import Testing
import VitrineDomain

@testable import Vitrine

@Suite("Annotation mark toolbar placement")
struct AnnotationMarkToolbarPlacementTests {
    private let stage = CGRect(x: 0, y: 0, width: 800, height: 500)
    private let toolbar = CGSize(width: 180, height: 34)

    private func frame(beside mark: CGRect, in bounds: CGRect? = nil) -> CGRect {
        let bounds = bounds ?? stage
        let origin = AnnotationMarkToolbarPlacement.origin(
            for: toolbar, beside: mark, in: bounds)
        return CGRect(origin: origin, size: toolbar)
    }

    @Test func sitsCenteredAboveAMarkWithRoom() {
        let mark = CGRect(x: 300, y: 200, width: 120, height: 60)
        let placed = frame(beside: mark)
        #expect(placed.maxY <= mark.minY)
        #expect(placed.midX == mark.midX)
        #expect(stage.contains(placed))
    }

    @Test func flipsBelowAMarkAtTheTopOfTheStage() {
        let mark = CGRect(x: 300, y: 4, width: 120, height: 60)
        let placed = frame(beside: mark)
        #expect(placed.minY >= mark.maxY)
        #expect(stage.contains(placed))
    }

    @Test func movesBesideAMarkTallerThanTheRoomAboveAndBelow() {
        let mark = CGRect(x: 100, y: 10, width: 40, height: 480)
        let placed = frame(beside: mark)
        #expect(placed.minX >= mark.maxX)
        #expect(stage.contains(placed))
        let flush = CGRect(x: 650, y: 10, width: 140, height: 480)
        #expect(frame(beside: flush).maxX <= flush.minX)
    }

    @Test func slidesInsideTheStageNearAnEdge() {
        let mark = CGRect(x: 760, y: 300, width: 40, height: 40)
        let placed = frame(beside: mark)
        #expect(stage.contains(placed))
        #expect(!placed.intersects(mark))
    }

    @Test func staysOnStageWhenTheMarkFillsIt() {
        #expect(stage.contains(frame(beside: stage)))
    }

    @Test func followsAStageThatDoesNotStartAtTheOrigin() {
        let offsetStage = stage.offsetBy(dx: 40, dy: 30)
        let mark = CGRect(x: 360, y: 40, width: 80, height: 40)
        let placed = frame(beside: mark, in: offsetStage)
        #expect(offsetStage.contains(placed))
        #expect(!placed.intersects(mark))
    }

    /// Wherever a side has room, the toolbar never covers the mark or leaves the stage.
    @Test func neverCoversAMarkThatLeavesRoomOnSomeSide() {
        for x in stride(from: 0.0, through: 760, by: 40) {
            for y in stride(from: 0.0, through: 460, by: 20) {
                for size in [CGSize(width: 40, height: 40), CGSize(width: 300, height: 200)] {
                    let mark = CGRect(origin: CGPoint(x: x, y: y), size: size)
                        .intersection(stage)
                    let placed = frame(beside: mark)
                    #expect(stage.contains(placed))
                    #expect(!placed.intersects(mark), "mark \(mark)")
                }
            }
        }
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

    @Test(arguments: Annotation.Kind.allCases)
    func chromeHoldsStillWhileTheSizeChanges(kind: Annotation.Kind) {
        let canvas = CGSize(width: 400, height: 200)
        let range = Annotation.thicknessRange
        let bounds = stride(from: range.lowerBound, through: range.upperBound, by: 1).map {
            thickness in
            var mark = Annotation(
                kind: kind, start: CGPoint(x: 0.5, y: 0.05), end: CGPoint(x: 0.8, y: 0.6))
            mark.thickness = thickness
            return AnnotationInteractionGeometry(annotation: mark, canvasSize: canvas)
                .chromeBounds
        }
        #expect(bounds.allSatisfy { $0 == bounds[0] })
    }
}

extension CGPoint {
    fileprivate func square(radius: CGFloat) -> CGRect {
        CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
    }
}
