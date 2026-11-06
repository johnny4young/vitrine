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
    private let card = CGRect(x: 40, y: 40, width: 320, height: 200)
    private let metrics = CanvasSnapLayout.CodeMetrics(
        source: "let token = 1\nfoo(bar)\n\tx", lineSpacing: 4, rowInset: 0, columnInset: 0,
        advance: 8)

    private var targets: AnnotationSnapTargets {
        AnnotationSnapTargets(
            card: card, code: CGRect(x: 66, y: 62, width: 268, height: 56), metrics: metrics)
    }

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
        #expect(targets.rows.map(\.tokens.count) == [6, 4, 0])
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
        let moved = mark(.counter, from: CGPoint(x: 68, y: 92), to: .zero)
        let (delta, _) = targets.snapMove(moved, in: canvas)
        #expect(abs(delta.width + 2) < 0.001)
        #expect(abs(delta.height + 2) < 0.001)
    }

    @Test func withoutSourceOnlyTheFrameSnaps() {
        var wrapped = metrics
        wrapped.source = nil
        let frameOnly = AnnotationSnapTargets(
            card: card, code: CGRect(x: 66, y: 62, width: 268, height: 56), metrics: wrapped)
        #expect(frameOnly.rowEdges.isEmpty && frameOnly.rows.isEmpty)
        #expect(frameOnly.frameXs.map(\.position) == [40, 360, 66, 334])
    }

    @Test func aBoxInTheBackgroundPaddingIgnoresCodeRows() {
        let (point, _) = targets.snapEnd(
            CGPoint(x: 350, y: 81), anchor: CGPoint(x: 345, y: 50), kind: .rectangle)
        #expect(point == CGPoint(x: 350, y: 81))
    }

    @Test func aSnapNeverCollapsesABox() {
        // Both edges of a thin highlight would land on the 80 pt row edge.
        let (ends, guides) = targets.snapEnds(
            start: CGPoint(x: 100, y: 79), end: CGPoint(x: 140, y: 81), kind: .highlighter)
        #expect(ends.start.y == 79 && ends.end.y == 81)
        #expect(!guides.contains { $0.axis == .horizontal })
        let (resized, _) = targets.snapEnd(
            CGPoint(x: 150, y: 82), anchor: CGPoint(x: 100, y: 79.5), kind: .rectangle)
        #expect(resized.y == 82)
        // An arrow may lie flat.
        let (arrow, _) = targets.snapEnds(
            start: CGPoint(x: 100, y: 71), end: CGPoint(x: 140, y: 69), kind: .arrow)
        #expect(arrow.start.y == 70 && arrow.end.y == 70)
    }

    @Test func thresholdAndGuideWidthFollowThePreviewZoom() throws {
        let snapper = AnnotationSnapper()
        snapper.layout = CanvasSnapLayout(card: card, code: nil, text: nil)
        let point = CGPoint(x: 52, y: 150)
        let full = try #require(snapper.targets(bypassed: false))
        #expect(full.snapEnd(point, anchor: .zero, kind: .arrow).0 == point)
        snapper.scale = 0.25
        let zoomedOut = try #require(snapper.targets(bypassed: false))
        #expect(zoomedOut.snapEnd(point, anchor: .zero, kind: .arrow).0 == CGPoint(x: 40, y: 150))
        #expect(snapper.guideWidth == 6)
    }

    @Test func commandBypassesSnappingAndTheDrawCommitsItsPreview() {
        #expect(AnnotationSnapper.isBypassed([.command]))
        #expect(!AnnotationSnapper.isBypassed([.option, .shift]))
        let snapper = AnnotationSnapper()
        snapper.layout = CanvasSnapLayout(card: card, code: nil, text: nil)
        var shown: [SnapGuide]? = nil
        let record: ([SnapGuide]) -> Void = { shown = $0 }
        let corner = CGPoint(x: 41, y: 41)
        let free = snapper.apply(corner, bypassed: true, onGuides: record) {
            $0.snapEnd(corner, anchor: .zero, kind: .arrow)
        }
        #expect(free == corner && shown == [])
        let snapped = snapper.apply(corner, bypassed: false, onGuides: record) {
            $0.snapEnd(corner, anchor: .zero, kind: .arrow)
        }
        #expect(snapped == CGPoint(x: 40, y: 40) && shown?.count == 2)
        let preview = (start: CGPoint(x: 40, y: 40), end: CGPoint(x: 90, y: 70))
        let committed = AnnotationSnapper.committedEnds(
            preview: preview, start: CGPoint(x: 41, y: 41), end: CGPoint(x: 92, y: 71))
        #expect(committed.start == preview.start && committed.end == preview.end)
        let unpreviewed = AnnotationSnapper.committedEnds(
            preview: nil, start: CGPoint(x: 41, y: 41), end: CGPoint(x: 92, y: 71))
        #expect(unpreviewed.end == CGPoint(x: 92, y: 71))
    }

    @Test func theSnapperIsSilentWhileBypassedOrBeforeLayout() {
        let snapper = AnnotationSnapper()
        #expect(snapper.targets(bypassed: false) == nil)
        snapper.layout = CanvasSnapLayout(card: card, code: nil, text: nil)
        #expect(snapper.targets(bypassed: true) == nil)
        #expect(snapper.targets(bypassed: false)?.frameYs.count == 2)
    }

    private func report(_ code: String, lineNumbers: Bool = false) throws -> CanvasSnapLayout {
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

    @Test(arguments: [false, true])
    func theCanvasReportsRowsThatMatchItsLayout(lineNumbers: Bool) throws {
        let one = try report("let a = 1", lineNumbers: lineNumbers)
        let three = try report("let a = 1\nlet b = 2\nlet c = 3", lineNumbers: lineNumbers)
        let code = try #require(three.code)
        let metrics = try #require(three.text?.metrics())
        #expect(three.card.contains(code))
        #expect(metrics.source == "let a = 1\nlet b = 2\nlet c = 3")
        #expect((metrics.columnInset > 0) == lineNumbers)
        // Rows are evenly pitched with no gap after the last one.
        let oneRow = try #require(one.code).height + metrics.lineSpacing
        #expect(abs((code.height + metrics.lineSpacing) / 3 - oneRow) < 0.5)
    }

    @Test func aTrailingNewlineIsARowInThePlainPath() throws {
        let one = try report("let a = 1")
        let trailing = try report("let a = 1\n")
        let metrics = try #require(trailing.text?.metrics())
        #expect(metrics.source == "let a = 1\n")
        let code = try #require(trailing.code)
        let oneRow = try #require(one.code).height + metrics.lineSpacing
        #expect(abs((code.height + metrics.lineSpacing) / 2 - oneRow) < 0.5)
    }

    @Test func emojiOrFallbackTextReportsNoRows() throws {
        let layout = try report("let a = 1\nlet party = \"🎉\"")
        #expect(layout.text?.metrics().source == nil)
        let targets = AnnotationSnapTargets(layout: layout)
        #expect(targets.rows.isEmpty && targets.rowEdges.isEmpty)
        #expect(targets.frameXs.count == 4)
    }
}

private final class LayoutProbe {
    var layout: CanvasSnapLayout?

    func record(_ layout: CanvasSnapLayout?) -> Color {
        if let layout { self.layout = layout }
        return .clear
    }
}
