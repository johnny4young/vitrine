import CoreGraphics
import SwiftUI
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@Suite("Annotation snapping")
struct AnnotationSnappingTests {
    // Three 16 pt rows 4 pt apart (pitch 20), 8 pt columns, inside a 320 × 200 card.
    private let canvas = CGSize(width: 400, height: 280)
    private let layout = CanvasSnapLayout(
        card: CGRect(x: 40, y: 40, width: 320, height: 200),
        code: CGRect(x: 66, y: 62, width: 268, height: 56),
        metrics: .init(source: "let token = 1\nfoo(bar)\n\tx", lineSpacing: 4, advance: 8))

    private var targets: AnnotationSnapTargets { AnnotationSnapTargets(layout: layout) }

    private func mark(_ kind: Annotation.Kind, from start: CGPoint, to end: CGPoint) -> Annotation {
        Annotation(
            kind: kind,
            start: CGPoint(x: start.x / canvas.width, y: start.y / canvas.height),
            end: CGPoint(x: end.x / canvas.width, y: end.y / canvas.height))
    }

    @Test func tokenEdgesCoverIdentifiersAndWholeStringLiterals() {
        #expect(
            AnnotationSnapTargets.tokenEdgeColumns(in: #"  let token = "sk-\"live""#)
                == [2, 5, 6, 11, 14, 25])
        #expect(AnnotationSnapTargets.tokenEdgeColumns(in: "foo(bar)") == [0, 3, 4, 7])
        #expect(AnnotationSnapTargets.tokenEdgeColumns(in: "\tx").isEmpty)
        #expect(AnnotationSnapTargets.tokenEdgeColumns(in: "let café = 1").isEmpty)
    }

    @Test func rowsComeFromTheReportedCodeFrame() {
        #expect(targets.rowEdges.map(\.position) == [60, 80, 100, 120])
        #expect(targets.rowCenters.map(\.position) == [70, 90, 110])
        // The tabbed third row has no column grid, so no token edges.
        #expect(targets.tokenEdges.count == 10)
    }

    @Test func anArrowEndSnapsToATokenEdgeAndRowCenterWithGuides() {
        let (point, guides) = targets.snapEnd(
            CGPoint(x: 92, y: 71), anchor: CGPoint(x: 300, y: 200), kind: .arrow)
        #expect(point == CGPoint(x: 90, y: 70))
        #expect(
            guides == [
                SnapGuide(axis: .vertical, position: 90, span: 60...80),
                SnapGuide(axis: .horizontal, position: 70, span: 66...334),
            ])
    }

    @Test func aPointOutsideTheThresholdStaysWhereItIs() {
        let (point, guides) = targets.snapEnd(
            CGPoint(x: 250, y: 180), anchor: .zero, kind: .arrow)
        #expect(point == CGPoint(x: 250, y: 180))
        #expect(guides.isEmpty)
    }

    @Test func aRectangleEdgeSnapsInEitherDirection() {
        let (point, _) = targets.snapEnd(
            CGPoint(x: 141, y: 78), anchor: CGPoint(x: 60, y: 50), kind: .rectangle)
        #expect(point == CGPoint(x: 138, y: 80))
    }

    @Test func aBlurEdgeOnlySnapsOutward() {
        let grows = targets.snapEnd(
            CGPoint(x: 136, y: 78), anchor: CGPoint(x: 60, y: 50), kind: .blur)
        #expect(grows.0 == CGPoint(x: 138, y: 80))
        // Snapping back to 138 would uncover the end of `token`.
        let stays = targets.snapEnd(
            CGPoint(x: 141, y: 82), anchor: CGPoint(x: 60, y: 50), kind: .blur)
        #expect(stays.0 == CGPoint(x: 141, y: 82))
        // Dragged up and left of its anchor, outward is toward smaller values.
        let leftward = targets.snapEnd(
            CGPoint(x: 100, y: 83), anchor: CGPoint(x: 300, y: 115), kind: .blur)
        #expect(leftward.0 == CGPoint(x: 98, y: 80))
    }

    @Test func aMovedRectangleSnapsItsNearestEdge() {
        let moved = mark(.rectangle, from: CGPoint(x: 43, y: 101), to: CGPoint(x: 200, y: 150))
        let (delta, guides) = targets.snapMove(moved, in: canvas)
        #expect(abs(delta.width + 3) < 0.001)
        #expect(abs(delta.height + 1) < 0.001)
        #expect(guides.map(\.axis) == [.vertical, .horizontal])
    }

    @Test func aMovedBlurBoxNeverSnaps() {
        let moved = mark(.blur, from: CGPoint(x: 43, y: 101), to: CGPoint(x: 200, y: 150))
        let (delta, guides) = targets.snapMove(moved, in: canvas)
        #expect(delta == .zero)
        #expect(guides.isEmpty)
    }

    @Test func aMovedCounterSnapsItsAnchor() {
        let moved = mark(.counter, from: CGPoint(x: 64, y: 92), to: .zero)
        let (delta, _) = targets.snapMove(moved, in: canvas)
        #expect(abs(delta.width - 2) < 0.001)
        #expect(abs(delta.height + 2) < 0.001)
    }

    @Test func withoutSourceOnlyTheFrameSnaps() {
        var wrapped = layout
        wrapped.metrics?.source = nil
        let frameOnly = AnnotationSnapTargets(layout: wrapped)
        #expect(frameOnly.rowEdges.isEmpty && frameOnly.tokenEdges.isEmpty)
        #expect(frameOnly.frameXs.map(\.position) == [40, 360, 66, 334])
    }

    @Test func theSnapperIsSilentWhileBypassedOrBeforeLayout() {
        let snapper = AnnotationSnapper()
        #expect(snapper.targets(bypassed: false) == nil)
        snapper.layout = layout
        #expect(snapper.targets(bypassed: true) == nil)
        #expect(snapper.targets(bypassed: false)?.rowCenters.count == 3)
    }

    @Test(arguments: [false, true])
    func theCanvasReportsRowsThatMatchItsLayout(lineNumbers: Bool) throws {
        func report(_ code: String) throws -> CanvasSnapLayout {
            var config = SnapshotConfig()
            config.code = code
            config.showLineNumbers = lineNumbers
            let probe = LayoutProbe()
            let renderer = ImageRenderer(
                content: SnapshotCanvas(config: config)
                    .backgroundPreferenceValue(CanvasSnapAnchorsKey.self) { anchors in
                        GeometryReader { proxy in
                            probe.record(anchors.resolved(in: proxy))
                        }
                    })
            renderer.scale = 1
            _ = renderer.cgImage
            return try #require(probe.layout)
        }
        let one = try report("let a = 1")
        let three = try report("let a = 1\nlet b = 2\nlet c = 3")
        let code = try #require(three.code)
        let metrics = try #require(three.metrics)
        #expect(three.card.contains(code))
        #expect(metrics.source == "let a = 1\nlet b = 2\nlet c = 3")
        #expect((metrics.columnInset > 0) == lineNumbers)
        // Rows are evenly pitched with no gap after the last one.
        let oneRow = try #require(one.code).height + metrics.lineSpacing
        #expect(abs((code.height + metrics.lineSpacing) / 3 - oneRow) < 0.5)
    }
}

private final class LayoutProbe {
    var layout: CanvasSnapLayout?

    func record(_ layout: CanvasSnapLayout?) -> Color {
        if let layout { self.layout = layout }
        return .clear
    }
}
