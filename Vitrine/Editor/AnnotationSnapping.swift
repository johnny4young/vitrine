import CoreGraphics
import Foundation
import VitrineDomain
import VitrineRendering

/// A guide drawn on the stage while a dragged mark sits on a snap target, in canvas points.
struct SnapGuide: Hashable {
    enum Axis: Hashable { case vertical, horizontal }
    let axis: Axis
    let position: CGFloat
    let span: ClosedRange<CGFloat>
}

/// The card edges, code rows and tokens a mark can snap to, built once per canvas layout.
struct AnnotationSnapTargets {
    struct Target: Equatable {
        let position: CGFloat
        /// The guide's extent along the other axis.
        let span: ClosedRange<CGFloat>
        /// Where along the other axis the target applies; `nil` applies everywhere.
        var band: ClosedRange<CGFloat>?
    }

    /// Only an edge that grows a mark may snap, so a redaction never uncovers text.
    enum Direction { case free, decreasing, increasing }

    static let threshold: CGFloat = 5

    private(set) var frameXs: [Target] = []
    private(set) var frameYs: [Target] = []
    /// Boundaries between code rows, for box edges.
    private(set) var rowEdges: [Target] = []
    /// Row centers, for arrow ends and placed marks.
    private(set) var rowCenters: [Target] = []
    /// Token starts and ends, each limited to its row.
    private(set) var tokenEdges: [Target] = []

    init(layout: CanvasSnapLayout) {
        let card = layout.card
        let cardYs = card.minY...card.maxY
        let cardXs = card.minX...card.maxX
        frameXs = [card.minX, card.maxX].map { Target(position: $0, span: cardYs) }
        frameYs = [card.minY, card.maxY].map { Target(position: $0, span: cardXs) }
        guard let code = layout.code, let metrics = layout.metrics else { return }
        let columnX = code.minX + metrics.columnInset
        frameXs += [columnX, code.maxX].map { Target(position: $0, span: code.minY...code.maxY) }
        guard let source = metrics.source else { return }

        let lines = source.split(omittingEmptySubsequences: false) {
            $0 == "\n" || $0 == "\r\n"
        }
        let gap = metrics.lineSpacing
        let pitch = (code.height + gap) / CGFloat(lines.count)
        let textHeight = pitch - gap - 2 * metrics.rowInset
        guard pitch > 0, textHeight > 0 else { return }
        let codeXs = code.minX...code.maxX
        for row in 0...lines.count {
            let edge = min(max(code.minY + CGFloat(row) * pitch - gap / 2, card.minY), card.maxY)
            rowEdges.append(Target(position: edge, span: codeXs, band: cardXs))
        }
        for (row, line) in lines.enumerated() {
            let top = code.minY + CGFloat(row) * pitch + metrics.rowInset
            let band = (top - gap / 2)...(top + textHeight + gap / 2)
            rowCenters.append(
                Target(position: top + textHeight / 2, span: codeXs, band: cardXs))
            guard let advance = metrics.advance else { continue }
            for column in Self.tokenEdgeColumns(in: line) {
                tokenEdges.append(
                    Target(
                        position: columnX + CGFloat(column) * advance, span: band, band: band))
            }
        }
    }

    /// Columns where an identifier, number or string literal starts or ends. Lines with a
    /// tab or a non-ASCII character are skipped: their columns don't map to a fixed advance.
    static func tokenEdgeColumns(in line: Substring) -> [Int] {
        let characters = Array(line)
        guard characters.allSatisfy({ $0.isASCII && $0 != "\t" }) else { return [] }
        var edges: [Int] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let start = index
            if character.isLetter || character.isNumber || character == "_" {
                while index < characters.count,
                    characters[index].isLetter || characters[index].isNumber
                        || characters[index] == "_"
                {
                    index += 1
                }
            } else if character == "\"" || character == "'" || character == "`" {
                index += 1
                while index < characters.count, characters[index] != character {
                    index += characters[index] == "\\" ? 2 : 1
                }
                index = min(index + 1, characters.count)
            } else {
                index += 1
                continue
            }
            if edges.last != start { edges.append(start) }
            edges.append(index)
        }
        return edges
    }

    // MARK: Queries

    /// The translation that lands one of a moved mark's edges or ends on a target.
    /// Blur boxes don't snap while moving: shifting both edges could uncover text.
    func snapMove(_ annotation: Annotation, in canvasSize: CGSize) -> (CGSize, [SnapGuide]) {
        let geometry = AnnotationInteractionGeometry(annotation: annotation, canvasSize: canvasSize)
        let xs: [(CGFloat, [Target])]
        let ys: [(CGFloat, [Target])]
        switch geometry.shape {
        case .box:
            guard annotation.kind != .blur else { return (.zero, []) }
            let rect = geometry.rect
            let xTargets = boxXTargets(rows: rect.minY...rect.maxY)
            xs = [(rect.minX, xTargets), (rect.maxX, xTargets)]
            ys = [(rect.minY, frameYs + rowEdges), (rect.maxY, frameYs + rowEdges)]
        case .line:
            xs = [geometry.start, geometry.end].map { ($0.x, pointXTargets($0)) }
            ys = [geometry.start, geometry.end].map { ($0.y, pointYTargets($0)) }
        case .point:
            xs = [(geometry.start.x, pointXTargets(geometry.start))]
            ys = [(geometry.start.y, pointYTargets(geometry.start))]
        }
        let x = Self.nearest(xs.map { ($0.0, $0.1, Direction.free) })
        let y = Self.nearest(ys.map { ($0.0, $0.1, Direction.free) })
        return (
            CGSize(width: x?.delta ?? 0, height: y?.delta ?? 0),
            Self.guides(x: x?.target, y: y?.target)
        )
    }

    /// Snaps a dragged end or corner; `anchor` is the mark's other end.
    func snapEnd(_ point: CGPoint, anchor: CGPoint, kind: Annotation.Kind) -> (CGPoint, [SnapGuide])
    {
        let x: (delta: CGFloat, target: Target)?
        let y: (delta: CGFloat, target: Target)?
        switch kind {
        case .rectangle, .highlighter, .blur, .spotlight:
            let grows = kind == .blur
            let xDirection: Direction =
                grows ? (point.x >= anchor.x ? .increasing : .decreasing) : .free
            let yDirection: Direction =
                grows ? (point.y >= anchor.y ? .increasing : .decreasing) : .free
            let rows = min(point.y, anchor.y)...max(point.y, anchor.y)
            x = Self.nearest([(point.x, boxXTargets(rows: rows), xDirection)])
            y = Self.nearest([(point.y, frameYs + rowEdges, yDirection)])
        case .arrow, .curvedArrow, .line, .measure, .text, .counter, .sticker:
            x = Self.nearest([(point.x, pointXTargets(point), .free)])
            y = Self.nearest([(point.y, pointYTargets(point), .free)])
        }
        return (
            CGPoint(x: point.x + (x?.delta ?? 0), y: point.y + (y?.delta ?? 0)),
            Self.guides(x: x?.target, y: y?.target)
        )
    }

    private func boxXTargets(rows: ClosedRange<CGFloat>) -> [Target] {
        frameXs + tokenEdges.filter { $0.band?.overlaps(rows) ?? true }
    }

    private func pointXTargets(_ point: CGPoint) -> [Target] {
        frameXs + tokenEdges.filter { $0.band?.contains(point.y) ?? true }
    }

    private func pointYTargets(_ point: CGPoint) -> [Target] {
        frameYs + rowCenters.filter { $0.band?.contains(point.x) ?? true }
    }

    private static func nearest(
        _ candidates: [(value: CGFloat, targets: [Target], direction: Direction)]
    ) -> (delta: CGFloat, target: Target)? {
        var best: (delta: CGFloat, target: Target)?
        for candidate in candidates {
            for target in candidate.targets {
                let delta = target.position - candidate.value
                switch candidate.direction {
                case .free: break
                case .decreasing: if delta > 0 { continue }
                case .increasing: if delta < 0 { continue }
                }
                if abs(delta) <= threshold, abs(delta) < abs(best?.delta ?? .infinity) {
                    best = (delta, target)
                }
            }
        }
        return best
    }

    private static func guides(x: Target?, y: Target?) -> [SnapGuide] {
        var guides: [SnapGuide] = []
        if let x { guides.append(SnapGuide(axis: .vertical, position: x.position, span: x.span)) }
        if let y {
            guides.append(SnapGuide(axis: .horizontal, position: y.position, span: y.span))
        }
        return guides
    }
}

/// The stage's latest canvas layout and its targets, built on the first drag event that
/// needs them and reused until the canvas lays out differently.
final class AnnotationSnapper {
    /// Set as the canvas lays out; read only by gestures, so nothing observes it.
    var layout: CanvasSnapLayout?
    private var cached: (layout: CanvasSnapLayout, targets: AnnotationSnapTargets)?

    /// The targets for a drag event, or `nil` while snapping is bypassed or unknown.
    func targets(bypassed: Bool) -> AnnotationSnapTargets? {
        guard !bypassed, let layout else { return nil }
        if let cached, cached.layout == layout { return cached.targets }
        let targets = AnnotationSnapTargets(layout: layout)
        cached = (layout, targets)
        return targets
    }
}
