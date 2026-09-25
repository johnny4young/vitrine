import CoreGraphics
import Testing
import VitrineDomain

@testable import Vitrine

@Suite("Annotation interaction geometry")
struct AnnotationInteractionGeometryTests {
    private let canvas = CGSize(width: 400, height: 200)

    @Test(arguments: [Annotation.Kind.arrow, .line, .curvedArrow, .measure])
    func diagonalHitAreaFollowsTheWholeShaft(kind: Annotation.Kind) {
        let mark = Annotation(
            kind: kind, start: CGPoint(x: 0.9, y: 0.9), end: CGPoint(x: 0.1, y: 0.1))
        let geometry = AnnotationInteractionGeometry(annotation: mark, canvasSize: canvas)
        #expect(geometry.isLineLike)
        #expect(!geometry.isBoxLike)
        #expect(geometry.hitCenter == CGPoint(x: 200, y: 100))
        #expect(abs(geometry.hitSize.width - hypot(320, 160)) < 0.0001)
        #expect(geometry.hitSize.height >= 26)
        #expect(abs(geometry.shaftAngle - atan2(-160, -320)) < 0.0001)
    }

    @Test(arguments: [Annotation.Kind.rectangle, .highlighter, .blur, .spotlight])
    func reversedAndTinyBoxesRemainGrabbable(kind: Annotation.Kind) {
        let mark = Annotation(
            kind: kind, start: CGPoint(x: 0.51, y: 0.52), end: CGPoint(x: 0.5, y: 0.5))
        let geometry = AnnotationInteractionGeometry(annotation: mark, canvasSize: canvas)
        #expect(geometry.isBoxLike)
        #expect(!geometry.isLineLike)
        #expect(geometry.hitSize == CGSize(width: 24, height: 24))
        #expect(geometry.hitCenter == CGPoint(x: 202, y: 102))
        #expect(geometry.selectionRect == mark.rect(in: canvas))
    }

    @Test(arguments: [Annotation.Kind.text, .counter, .sticker])
    func pointMarksUseTheirAnchorAndDoNotRequireADrag(kind: Annotation.Kind) {
        let mark = Annotation(kind: kind, start: CGPoint(x: 0.25, y: 0.5), end: .zero)
        let geometry = AnnotationInteractionGeometry(annotation: mark, canvasSize: canvas)
        #expect(!geometry.isLineLike && !geometry.isBoxLike)
        #expect(geometry.hitCenter == CGPoint(x: 100, y: 100))
        #expect(geometry.selectionRect.contains(geometry.hitCenter))
        #expect(AnnotationInteractionGeometry.shouldCommit(kind: kind, from: .zero, to: .zero))
    }

    @Test(arguments: Annotation.Kind.allCases.filter { !$0.isPointPlaced })
    func accidentalClicksAndSixPointDragsDoNotCreateShapes(kind: Annotation.Kind) {
        #expect(!AnnotationInteractionGeometry.shouldCommit(kind: kind, from: .zero, to: .zero))
        #expect(
            !AnnotationInteractionGeometry.shouldCommit(
                kind: kind, from: .zero, to: CGPoint(x: 6, y: 0)))
        #expect(
            AnnotationInteractionGeometry.shouldCommit(
                kind: kind, from: .zero, to: CGPoint(x: 6.01, y: 0)))
        #expect(
            AnnotationInteractionGeometry.shouldCommit(
                kind: kind, from: .zero, to: CGPoint(x: 5, y: 5)))
    }

    @Test func resizeClampsToCanvasWithoutChangingTheOtherEndpoint() {
        var mark = Annotation(
            kind: .arrow, start: CGPoint(x: 0.2, y: 0.3), end: CGPoint(x: 0.7, y: 0.8))
        let start = mark.start
        mark.end = AnnotationInteractionGeometry.normalize(CGPoint(x: 900, y: -40), in: canvas)
        #expect(mark.start == start)
        #expect(mark.end == CGPoint(x: 1, y: 0))
        #expect(
            AnnotationInteractionGeometry.normalize(CGPoint(x: -1, y: 2), in: .zero)
                == CGPoint(x: 0, y: 1))
    }

    @Test func nudgeMovesByCanvasPoints() {
        var mark = Annotation(
            kind: .rectangle, start: CGPoint(x: 0.25, y: 0.75), end: CGPoint(x: 0.5, y: 0.9))
        let start = mark.start
        mark.nudge(by: CGSize(width: 8, height: -4), in: canvas)
        #expect(abs((mark.start.x - start.x) * canvas.width - 8) < 0.0001)
        #expect(abs((mark.start.y - start.y) * canvas.height + 4) < 0.0001)
    }

    @Test(arguments: Annotation.Kind.allCases)
    func pointShapesAreExactlyThePointPlacedKinds(kind: Annotation.Kind) {
        let mark = Annotation(kind: kind, start: .zero, end: CGPoint(x: 1, y: 1))
        let geometry = AnnotationInteractionGeometry(annotation: mark, canvasSize: canvas)
        #expect((geometry.shape == .point) == kind.isPointPlaced)
    }
}
