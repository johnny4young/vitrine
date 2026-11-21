import AppKit
import CoreGraphics
import SwiftUI
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

/// Arrow shapes and hand-drawn strokes: older marks keep their encoding and pixels, and
/// hand-drawn strokes repeat exactly with the head on the shaft's end.
@MainActor
@Suite("Annotation styles")
struct AnnotationStyleTests {
    private static let markID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    // MARK: - Model

    @Test func anOlderMarkDecodesAsCleanAndStandard() throws {
        let json = #"""
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"arrow",
             "start":[0.1,0.2],"end":[0.8,0.6]}
            """#
        let mark = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
        #expect(mark.variant == .standard)
        #expect(mark.stroke == .clean)
    }

    @Test func aPlainMarkEncodesWithoutStyleFields() throws {
        let mark = Annotation(
            id: Self.markID, kind: .rectangle, start: .zero, end: CGPoint(x: 0.5, y: 0.5))
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(mark)) as? [String: Any])
        #expect(
            Set(object.keys)
                == ["id", "kind", "start", "end", "text", "color", "thickness", "number"])
        #expect(mark.fingerprint.split(separator: "|", omittingEmptySubsequences: false).count == 7)
    }

    @Test func styleFieldsRoundTripAndChangeTheFingerprint() throws {
        var mark = Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 0.5, y: 0.5))
        let plain = mark.fingerprint
        mark.arrowStyle = .elbow
        mark.stroke = .handDrawn
        let decoded = try JSONDecoder().decode(
            Annotation.self, from: JSONEncoder().encode(mark))
        #expect(decoded == mark)
        #expect(decoded.fingerprint != plain)
    }

    @Test func anUnknownStyleFromALaterBuildFallsBack() throws {
        let json = #"""
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"arrow","start":[0,0],
             "end":[1,1],"variant":"spiral","stroke":"chalk"}
            """#
        let mark = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
        #expect(mark.variant == .standard)
        #expect(mark.stroke == .clean)
    }

    @Test func arrowStyleMovesBetweenTheArrowKinds() {
        var mark = Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 1, y: 1))
        #expect(mark.arrowStyle == .straight)
        mark.arrowStyle = .curved
        #expect(mark.kind == .curvedArrow)
        mark.arrowStyle = .elbow
        #expect(mark.kind == .arrow && mark.variant == .elbow)
        mark.arrowStyle = .straight
        #expect(mark.kind == .arrow && mark.variant == .standard)

        var box = Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 1, y: 1))
        box.arrowStyle = .elbow
        #expect(box.arrowStyle == nil && box.variant == .standard)
        #expect(box.supportsStrokeStyle)
        #expect(!Annotation(kind: .blur, start: .zero, end: .zero).supportsStrokeStyle)
    }

    @Test func nudgingAnElbowArrowKeepsItsStyle() {
        var mark = Annotation(
            kind: .arrow, start: CGPoint(x: 0.2, y: 0.2), end: CGPoint(x: 0.6, y: 0.5))
        mark.arrowStyle = .elbow
        mark.stroke = .handDrawn
        mark.nudge(by: CGSize(width: 10, height: 0), in: CGSize(width: 100, height: 100))
        #expect(
            abs(mark.start.x - 0.3) < 1e-9 && mark.variant == .elbow && mark.stroke == .handDrawn)
    }

    // MARK: - Shapes

    private func points(_ path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        // swift-format-ignore: ReplaceForEachWithForLoop
        // Path is not a Sequence.
        path.forEach { element in
            switch element {
            case .move(let to), .line(let to): points.append(to)
            case .quadCurve(let to, _), .curve(let to, _, _): points.append(to)
            case .closeSubpath: break
            }
        }
        return points
    }

    @Test func anElbowArrowCrossesAtTheMidpointAlongTheLongerAxis() {
        let path = ElbowArrowShape(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 210, y: 90))
            .path(in: .zero)
        #expect(
            Array(points(path).prefix(4)) == [
                CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10), CGPoint(x: 110, y: 90),
                CGPoint(x: 210, y: 90),
            ])
        let tall = ElbowArrowShape(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 210))
            .path(in: .zero)
        #expect(points(tall)[1] == CGPoint(x: 10, y: 110))
    }

    @Test func aHandDrawnStrokeRepeatsForTheSameMarkAndKeepsItsEnds() {
        let line = Path { $0.addLines([CGPoint(x: 10, y: 10), CGPoint(x: 310, y: 10)]) }
        let first = HandDrawnStroke.path(line, seed: 42, weight: 5)
        #expect(first.description == HandDrawnStroke.path(line, seed: 42, weight: 5).description)
        #expect(first.description != HandDrawnStroke.path(line, seed: 43, weight: 5).description)

        let wobbled = points(first)
        #expect(wobbled.first == CGPoint(x: 10, y: 10))
        #expect(wobbled.last == CGPoint(x: 310, y: 10))
        #expect(wobbled.contains { abs($0.y - 10) > 0.5 }, "a hand-drawn line must wobble")
        #expect(wobbled.allSatisfy { abs($0.y - 10) <= HandDrawnStroke.amplitude(weight: 5) })
    }

    @Test func theSeedComesFromTheMarkID() {
        let a = Annotation(id: Self.markID, kind: .line, start: .zero, end: .zero)
        let b = Annotation(id: Self.markID, kind: .line, start: .zero, end: .zero)
        #expect(a.strokeSeed == b.strokeSeed)
        #expect(a.strokeSeed != Annotation(kind: .line, start: .zero, end: .zero).strokeSeed)
    }

    @Test func drawnBoundsCoverTheWobble() throws {
        let size = CGSize(width: 400, height: 300)
        var mark = Annotation(
            id: Self.markID, kind: .rectangle, start: CGPoint(x: 0.2, y: 0.2),
            end: CGPoint(x: 0.8, y: 0.7))
        let clean = AnnotationMarkBounds.drawn(mark, in: size)
        mark.stroke = .handDrawn
        let wobbled = AnnotationMarkBounds.drawn(mark, in: size)
        let path = try #require(AnnotationMarkBounds.styledPath(mark, in: size))
        #expect(wobbled.contains(clean))
        #expect(wobbled.contains(path.boundingRect))
    }

    @Test func aHandDrawnArrowheadStaysOnTheShaftEnd() throws {
        let size = CGSize(width: 400, height: 300)
        for style in Annotation.ArrowStyle.allCases {
            var arrow = Annotation(
                id: Self.markID, kind: .arrow, start: CGPoint(x: 0.1, y: 0.2),
                end: CGPoint(x: 0.8, y: 0.7))
            arrow.arrowStyle = style
            arrow.stroke = .handDrawn
            let path = try #require(AnnotationMarkBounds.styledPath(arrow, in: size))
            let parts = HandDrawnStroke.subpaths(of: path)
            let tip = arrow.endPoint(in: size)
            #expect(parts.count == 2, "\(style)")
            #expect(parts.first?.last == tip, "the shaft ends on the tip (\(style))")
            #expect(parts.last?.contains(tip) == true, "the head stays on the tip (\(style))")
        }
    }

    /// A bent arrow is selected on its stroke, not on the empty tail-to-head diagonal.
    @Test func bentArrowsHitTestAlongTheirStroke() throws {
        let size = CGSize(width: 400, height: 300)
        var elbow = Annotation(
            kind: .arrow, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.9, y: 0.9))
        elbow.arrowStyle = .elbow
        let elbowHit = try #require(
            AnnotationInteractionGeometry(annotation: elbow, canvasSize: size).bentHitPath)
        #expect(elbowHit.contains(CGPoint(x: 120, y: 30)), "the first leg")
        #expect(elbowHit.contains(CGPoint(x: 200, y: 150)), "the crossing leg")
        #expect(!elbowHit.contains(CGPoint(x: 120, y: 90)), "the empty diagonal")

        elbow.arrowStyle = .curved
        let curveHit = try #require(
            AnnotationInteractionGeometry(annotation: elbow, canvasSize: size).bentHitPath)
        #expect(!curveHit.contains(CGPoint(x: 200, y: 150)), "the chord the curve bows away from")
        elbow.arrowStyle = .straight
        #expect(
            AnnotationInteractionGeometry(annotation: elbow, canvasSize: size).bentHitPath == nil)
    }

    // MARK: - Rendering

    private let size = CGSize(width: 480, height: 300)

    private func image(_ config: SnapshotConfig) throws -> CGImage {
        let renderer = ImageRenderer(content: SnapshotCanvas(config: config, fixedSize: size))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        return ExportManager.normalized(try #require(renderer.cgImage), to: .sRGB)
    }

    private func png(_ config: SnapshotConfig) throws -> Data {
        try #require(ExportManager.pngData(from: image(config)))
    }

    @Test func styledMarksRenderTheSameEveryTime() throws {
        var config = SnapshotConfig()
        config.code = "let x = 1"
        var arrow = Annotation(
            id: Self.markID, kind: .arrow, start: CGPoint(x: 0.1, y: 0.2),
            end: CGPoint(x: 0.9, y: 0.8))
        arrow.stroke = .handDrawn
        config.annotations = [arrow]
        let handDrawn = try png(config)
        #expect(try png(config) == handDrawn)

        config.annotations[0].stroke = .clean
        let clean = try png(config)
        #expect(clean != handDrawn)
        config.annotations[0].arrowStyle = .elbow
        #expect(try png(config) != clean)
    }
}
