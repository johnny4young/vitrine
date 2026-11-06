import AppKit
import CoreGraphics
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
    }

    /// Only an edge that grows a mark may snap, so a redaction never uncovers text.
    enum Direction { case free, decreasing, increasing }

    /// One code row: where it applies vertically, and its token edges.
    struct Row {
        let band: ClosedRange<CGFloat>
        let tokens: [Target]
    }

    /// Screen points, so snapping feels the same at every preview zoom.
    static let screenThreshold: CGFloat = 5
    static let screenMinimumSpan: CGFloat = 4

    /// The preview's zoom; the overlay's canvas points are this many screen points.
    var scale: CGFloat = 1
    var threshold: CGFloat { Self.screenThreshold / max(scale, 0.01) }
    var minimumSpan: CGFloat { Self.screenMinimumSpan / max(scale, 0.01) }

    private(set) var frameXs: [Target] = []
    private(set) var frameYs: [Target] = []
    /// Boundaries between code rows, for box edges.
    private(set) var rowEdges: [Target] = []
    /// Row centers, for arrow ends and placed marks.
    private(set) var rowCenters: [Target] = []
    private(set) var rows: [Row] = []
    private var codeXs: ClosedRange<CGFloat>?
    private var firstBandTop: CGFloat = 0
    private var pitch: CGFloat = 0

    init(layout: CanvasSnapLayout) {
        self.init(card: layout.card, code: layout.code, metrics: layout.text?.metrics())
    }

    init(card: CGRect, code: CGRect?, metrics: CanvasSnapLayout.CodeMetrics?) {
        let cardYs = card.minY...card.maxY
        let cardXs = card.minX...card.maxX
        frameXs = [card.minX, card.maxX].map { Target(position: $0, span: cardYs) }
        frameYs = [card.minY, card.maxY].map { Target(position: $0, span: cardXs) }
        guard let code, let metrics else { return }
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
        self.codeXs = codeXs
        self.pitch = pitch
        firstBandTop = code.minY + metrics.rowInset - gap / 2
        for row in 0...lines.count {
            let edge = min(max(code.minY + CGFloat(row) * pitch - gap / 2, card.minY), card.maxY)
            rowEdges.append(Target(position: edge, span: codeXs))
        }
        for (row, line) in lines.enumerated() {
            let top = code.minY + CGFloat(row) * pitch + metrics.rowInset
            let band = (top - gap / 2)...(top + textHeight + gap / 2)
            rowCenters.append(Target(position: top + textHeight / 2, span: codeXs))
            let tokens = metrics.advance.map { advance in
                Self.tokenEdgeColumns(in: line).map {
                    Target(position: columnX + CGFloat($0) * advance, span: band)
                }
            }
            rows.append(Row(band: band, tokens: tokens ?? []))
        }
    }

    /// Columns where an identifier, number or string literal starts or ends. Lines with a
    /// tab or a non-ASCII character are skipped: their columns don't map to a fixed advance.
    static func tokenEdgeColumns(in line: Substring) -> [Int] {
        let characters = Array(line)
        guard characters.allSatisfy({ $0.isASCII && $0 != "\t" }) else { return [] }
        func isWord(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }
        var edges: [Int] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let start = index
            if isWord(character) {
                while index < characters.count, isWord(characters[index]) { index += 1 }
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
        let xs: [Candidate]
        let ys: [Candidate]
        switch geometry.shape {
        case .box:
            guard annotation.kind != .blur else { return (.zero, []) }
            let rect = geometry.rect
            let xGroups = boxXGroups(rows: rect.minY...rect.maxY)
            let yGroups = boxYGroups(columns: rect.minX...rect.maxX)
            xs = [(rect.minX, xGroups, .free), (rect.maxX, xGroups, .free)]
            ys = [(rect.minY, yGroups, .free), (rect.maxY, yGroups, .free)]
        case .line:
            xs = [geometry.start, geometry.end].map { ($0.x, pointXGroups($0), .free) }
            ys = [geometry.start, geometry.end].map { ($0.y, pointYGroups($0), .free) }
        case .point:
            xs = [(geometry.start.x, pointXGroups(geometry.start), .free)]
            ys = [(geometry.start.y, pointYGroups(geometry.start), .free)]
        }
        let x = nearest(xs)
        let y = nearest(ys)
        return (
            CGSize(width: x?.delta ?? 0, height: y?.delta ?? 0),
            Self.guides(x: x?.target, y: y?.target)
        )
    }

    /// Snaps a dragged end or corner, or a placed mark's anchor; `anchor` is the other end.
    /// A box keeps at least `minimumSpan` on each axis: a snap that would collapse it is dropped.
    func snapEnd(_ point: CGPoint, anchor: CGPoint, kind: Annotation.Kind) -> (CGPoint, [SnapGuide])
    {
        guard Self.isBox(kind) else {
            let x = nearest([(point.x, pointXGroups(point), .free)])
            let y = nearest([(point.y, pointYGroups(point), .free)])
            return (
                CGPoint(x: point.x + (x?.delta ?? 0), y: point.y + (y?.delta ?? 0)),
                Self.guides(x: x?.target, y: y?.target)
            )
        }
        let grows = kind == .blur
        let xDirection: Direction =
            grows ? (point.x >= anchor.x ? .increasing : .decreasing) : .free
        let yDirection: Direction =
            grows ? (point.y >= anchor.y ? .increasing : .decreasing) : .free
        let rows = min(point.y, anchor.y)...max(point.y, anchor.y)
        let columns = min(point.x, anchor.x)...max(point.x, anchor.x)
        var x = nearest([(point.x, boxXGroups(rows: rows), xDirection)])
        var y = nearest([(point.y, boxYGroups(columns: columns), yDirection)])
        if let snap = x, abs(point.x + snap.delta - anchor.x) < minimumSpan { x = nil }
        if let snap = y, abs(point.y + snap.delta - anchor.y) < minimumSpan { y = nil }
        return (
            CGPoint(x: point.x + (x?.delta ?? 0), y: point.y + (y?.delta ?? 0)),
            Self.guides(x: x?.target, y: y?.target)
        )
    }

    /// Both ends of a shape being drawn. A box that the two snaps together would collapse
    /// on an axis keeps that axis as drawn.
    func snapEnds(
        start: CGPoint, end: CGPoint, kind: Annotation.Kind
    ) -> (
        (start: CGPoint, end: CGPoint), [SnapGuide]
    ) {
        var (snappedStart, startGuides) = snapEnd(start, anchor: end, kind: kind)
        var (snappedEnd, endGuides) = snapEnd(end, anchor: start, kind: kind)
        if Self.isBox(kind) {
            if abs(snappedEnd.x - snappedStart.x) < minimumSpan {
                (snappedStart.x, snappedEnd.x) = (start.x, end.x)
                startGuides.removeAll { $0.axis == .vertical }
                endGuides.removeAll { $0.axis == .vertical }
            }
            if abs(snappedEnd.y - snappedStart.y) < minimumSpan {
                (snappedStart.y, snappedEnd.y) = (start.y, end.y)
                startGuides.removeAll { $0.axis == .horizontal }
                endGuides.removeAll { $0.axis == .horizontal }
            }
        }
        return ((snappedStart, snappedEnd), startGuides + endGuides)
    }

    private static func isBox(_ kind: Annotation.Kind) -> Bool {
        switch kind {
        case .rectangle, .highlighter, .blur, .spotlight: true
        case .arrow, .curvedArrow, .line, .measure, .text, .counter, .sticker: false
        }
    }

    private typealias Candidate = (value: CGFloat, groups: [[Target]], direction: Direction)

    private func boxXGroups(rows range: ClosedRange<CGFloat>) -> [[Target]] {
        [frameXs] + rowIndices(overlapping: range).map { rows[$0].tokens }
    }

    private func boxYGroups(columns: ClosedRange<CGFloat>) -> [[Target]] {
        codeXs?.overlaps(columns) == true ? [frameYs, rowEdges] : [frameYs]
    }

    private func pointXGroups(_ point: CGPoint) -> [[Target]] {
        [frameXs] + rowIndices(overlapping: point.y...point.y).map { rows[$0].tokens }
    }

    private func pointYGroups(_ point: CGPoint) -> [[Target]] {
        codeXs?.contains(point.x) == true ? [frameYs, rowCenters] : [frameYs]
    }

    /// The rows whose band meets `range`, found by pitch rather than by scanning every row.
    private func rowIndices(overlapping range: ClosedRange<CGFloat>) -> [Int] {
        guard pitch > 0, !rows.isEmpty else { return [] }
        let first = Int(((range.lowerBound - firstBandTop) / pitch).rounded(.down))
        let last = Int(((range.upperBound - firstBandTop) / pitch).rounded(.down))
        let lower = max(first, 0)
        let upper = min(last, rows.count - 1)
        guard lower <= upper else { return [] }
        return (lower...upper).filter { rows[$0].band.overlaps(range) }
    }

    private func nearest(_ candidates: [Candidate]) -> (delta: CGFloat, target: Target)? {
        var best: (delta: CGFloat, target: Target)?
        for candidate in candidates {
            for group in candidate.groups {
                for target in group {
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

/// The stage's latest canvas layout and zoom. Targets are built on the first drag event
/// that needs them and reused until the canvas lays out differently.
final class AnnotationSnapper {
    /// Set as the canvas lays out; read only by gestures, so nothing observes it.
    var layout: CanvasSnapLayout?
    /// The preview's fit scale, set by the stage.
    var scale: CGFloat = 1
    private var cached: (layout: CanvasSnapLayout, targets: AnnotationSnapTargets)?

    static let screenGuideWidth: CGFloat = 1.5

    /// The guide stroke in canvas points, one screen width at the current zoom.
    var guideWidth: CGFloat { Self.screenGuideWidth / max(scale, 0.01) }

    /// Holding ⌘ while dragging places a mark freely, as alignment guides do in iWork.
    static func isBypassed(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.contains(.command)
    }

    /// What a finished drawing drag commits: the shape last previewed, so a ⌘ pressed or
    /// released at the moment of release can't change it.
    static func committedEnds(
        preview: (start: CGPoint, end: CGPoint)?, start: CGPoint, end: CGPoint
    ) -> (start: CGPoint, end: CGPoint) {
        preview ?? (start, end)
    }

    /// The targets for a drag event, or `nil` while snapping is bypassed or unknown.
    func targets(bypassed: Bool) -> AnnotationSnapTargets? {
        guard !bypassed, let layout else { return nil }
        var targets: AnnotationSnapTargets
        if let cached, cached.layout == layout {
            targets = cached.targets
        } else {
            targets = AnnotationSnapTargets(layout: layout)
            cached = (layout, targets)
        }
        targets.scale = scale
        return targets
    }

    /// Runs `snap` for one drag event and reports its guides, or keeps `free` (and clears
    /// the guides) while ⌘ is held or the layout is unknown.
    func apply<Value>(
        _ free: Value, bypassed: Bool = AnnotationSnapper.isBypassed(NSEvent.modifierFlags),
        onGuides: ([SnapGuide]) -> Void,
        _ snap: (AnnotationSnapTargets) -> (Value, [SnapGuide])
    ) -> Value {
        guard let targets = targets(bypassed: bypassed) else {
            onGuides([])
            return free
        }
        let (value, guides) = snap(targets)
        onGuides(guides)
        return value
    }
}
