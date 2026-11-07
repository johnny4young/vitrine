import SwiftUI
import VitrineDomain

/// The chevron head every arrow shape shares, sized from the tail-to-tip span.
nonisolated enum ArrowHead {
    static func add(
        to path: inout Path, tip: CGPoint, angle: CGFloat, span length: CGFloat, weight: CGFloat
    ) {
        // Bounded so a tiny arrow still has a visible head and a thick one is not all head.
        let head = min(max(length * 0.22, weight * 2.4), max(length * 0.6, 14))
        let spread = CGFloat.pi / 7  // ~26° each side
        let left = CGPoint(
            x: tip.x - head * cos(angle - spread), y: tip.y - head * sin(angle - spread))
        let right = CGPoint(
            x: tip.x - head * cos(angle + spread), y: tip.y - head * sin(angle + spread))
        path.move(to: left)
        path.addLine(to: tip)
        path.addLine(to: right)
    }
}

/// An elbow connector: legs along the dominant axis with one crossing at the midpoint, so
/// the head always points straight along the last leg.
nonisolated struct ElbowArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint
    var weight: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let horizontal = abs(to.x - from.x) >= abs(to.y - from.y)
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        var path = Path()
        path.move(to: from)
        if horizontal {
            path.addLine(to: CGPoint(x: mid.x, y: from.y))
            path.addLine(to: CGPoint(x: mid.x, y: to.y))
        } else {
            path.addLine(to: CGPoint(x: from.x, y: mid.y))
            path.addLine(to: CGPoint(x: to.x, y: mid.y))
        }
        path.addLine(to: to)
        let angle: CGFloat =
            horizontal ? (to.x >= from.x ? 0 : .pi) : (to.y >= from.y ? .pi / 2 : -.pi / 2)
        ArrowHead.add(
            to: &path, tip: to, angle: angle,
            span: max(hypot(to.x - from.x, to.y - from.y), 0.001), weight: weight)
        return path
    }
}

/// Redraws a path with a low-frequency wobble seeded by the mark, so a hand-drawn stroke is
/// identical on every render, export and share link. Only the first subpath wobbles, and its
/// ends stay put; later subpaths, such as an arrowhead, stay rigid on the shaft's end.
nonisolated enum HandDrawnStroke {
    static func amplitude(weight: CGFloat) -> CGFloat { min(max(1.5, weight * 0.45), 6) }

    static func path(_ path: Path, seed: UInt64, weight: CGFloat) -> Path {
        var random = SplitMix64(state: seed)
        var result = Path()
        for (index, points) in subpaths(of: path).enumerated() {
            guard index == 0, points.count > 1 else {
                result.addLines(points)
                continue
            }
            var lengths: [CGFloat] = [0]
            for index in 1..<points.count {
                lengths.append(lengths[index - 1] + distance(points[index - 1], points[index]))
            }
            let total = lengths[lengths.count - 1]
            let reach = amplitude(weight: weight) * min(1, total / 80)
            let phases = (random.unit * 2 * .pi, random.unit * 2 * .pi)
            var wobbled: [CGPoint] = []
            for index in points.indices {
                let along = lengths[index]
                let taper = max(0, min(1, along / 12, (total - along) / 12))
                let wave = 0.65 * sin(along / 23 + phases.0) + 0.35 * sin(along / 9 + phases.1)
                let previous = points[max(index - 1, 0)]
                let next = points[min(index + 1, points.count - 1)]
                let span = max(distance(previous, next), 0.001)
                let offset = reach * taper * wave
                wobbled.append(
                    CGPoint(
                        x: points[index].x - (next.y - previous.y) / span * offset,
                        y: points[index].y + (next.x - previous.x) / span * offset))
            }
            result.addLines(wobbled)
        }
        return result
    }

    /// The path's subpaths as points about 4 pt apart.
    static func subpaths(of path: Path) -> [[CGPoint]] {
        var subpaths: [[CGPoint]] = []
        func line(to point: CGPoint) {
            guard let last = subpaths.last?.last else { return }
            let steps = max(Int((distance(last, point) / 4).rounded(.up)), 1)
            for step in 1..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                subpaths[subpaths.count - 1].append(
                    CGPoint(x: last.x + (point.x - last.x) * t, y: last.y + (point.y - last.y) * t))
            }
            subpaths[subpaths.count - 1].append(point)
        }
        // swift-format-ignore: ReplaceForEachWithForLoop
        // Path is not a Sequence; flattening leaves only moves, lines and closes.
        Path(path.cgPath.flattened(threshold: 0.5)).forEach { element in
            switch element {
            case .move(let to): subpaths.append([to])
            case .line(let to): line(to: to)
            case .closeSubpath: if let first = subpaths.last?.first { line(to: first) }
            case .quadCurve, .curve: break
            }
        }
        return subpaths
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }
}

/// A tiny deterministic generator, so the wobble never depends on a system random source.
nonisolated struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0..<1`.
    var unit: CGFloat {
        mutating get { CGFloat(next() >> 11) / CGFloat(1 << 53) }
    }
}

/// A styled mark: a variant shape or a hand-drawn stroke, with the marks' shared shadow.
struct StyledStroke: View {
    let annotation: Annotation
    let path: Path

    var body: some View {
        path.stroke(
            annotation.color.color,
            style: StrokeStyle(lineWidth: annotation.thickness, lineCap: .round, lineJoin: .round)
        )
        .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 0.5)
    }
}

extension AnnotationMarkBounds {
    /// The stroke of a mark with a style, or `nil` for a plain mark, which keeps its own view.
    nonisolated static func styledPath(_ annotation: Annotation, in size: CGSize) -> Path? {
        guard annotation.arrowStyle == .elbow || annotation.stroke == .handDrawn,
            let base = shapePath(annotation, in: size)
        else { return nil }
        guard annotation.stroke == .handDrawn else { return base }
        return HandDrawnStroke.path(
            base, seed: annotation.strokeSeed, weight: annotation.thickness)
    }

    /// The outline a click selects a bent arrow by: its stroke, widened to the hit band.
    public nonisolated static func hitOutline(
        _ annotation: Annotation, in size: CGSize, width: CGFloat
    )
        -> Path?
    {
        guard annotation.arrowStyle == .curved || annotation.arrowStyle == .elbow,
            let path = shapePath(annotation, in: size)
        else { return nil }
        return path.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private nonisolated static func shapePath(_ annotation: Annotation, in size: CGSize) -> Path? {
        let from = annotation.startPoint(in: size)
        let to = annotation.endPoint(in: size)
        let weight = annotation.thickness
        switch annotation.kind {
        case .arrow where annotation.variant == .elbow:
            return ElbowArrowShape(from: from, to: to, weight: weight).path(in: .zero)
        case .arrow: return ArrowShape(from: from, to: to, weight: weight).path(in: .zero)
        case .curvedArrow:
            return CurvedArrowShape(from: from, to: to, weight: weight).path(in: .zero)
        case .line: return Path { $0.addLines([from, to]) }
        case .rectangle:
            return RoundedRectangle(cornerRadius: 8, style: .continuous)
                .path(in: annotation.rect(in: size))
        default: return nil
        }
    }
}
