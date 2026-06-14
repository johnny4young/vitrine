import SwiftUI

/// The exported visual of one annotation (CS-083 / CS-085). `SnapshotCanvas` draws
/// these, so a mark looks identical in the editor preview and the rendered PNG/PDF.
/// Coordinates arrive already denormalized to the canvas `size`. Blur is composited
/// separately by the canvas (a masked, blurred copy), so it renders nothing here.
struct AnnotationMarkView: View {
    let annotation: Annotation
    let size: CGSize

    var body: some View {
        switch annotation.kind {
        case .arrow: ArrowMark(annotation: annotation, size: size)
        case .line: LineMark(annotation: annotation, size: size)
        case .rectangle: RectangleMark(annotation: annotation, size: size)
        case .text: TextMark(annotation: annotation, size: size)
        case .highlighter: HighlighterMark(annotation: annotation, size: size)
        case .counter: CounterMark(annotation: annotation, size: size)
        case .blur: EmptyView()
        }
    }
}

/// An arrow: a straight shaft from tail to head with a chevron arrowhead.
struct ArrowMark: View {
    let annotation: Annotation
    let size: CGSize

    var body: some View {
        ArrowShape(
            from: annotation.startPoint(in: size), to: annotation.endPoint(in: size),
            weight: annotation.thickness
        )
        .stroke(
            annotation.color.color,
            style: StrokeStyle(lineWidth: annotation.thickness, lineCap: .round, lineJoin: .round)
        )
        .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 0.5)
    }
}

/// The shaft + chevron head of an arrow, in canvas points (CS-083).
struct ArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint
    var weight: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)

        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(hypot(dx, dy), 0.001)
        let angle = atan2(dy, dx)
        // The head scales with both the shaft length and the stroke weight, bounded
        // so a tiny arrow still has a visible head and a thick one is not all head.
        let head = min(max(length * 0.22, weight * 2.4), max(length * 0.6, 14))
        let spread = CGFloat.pi / 7  // ~26° each side

        let left = CGPoint(
            x: to.x - head * cos(angle - spread), y: to.y - head * sin(angle - spread))
        let right = CGPoint(
            x: to.x - head * cos(angle + spread), y: to.y - head * sin(angle + spread))
        path.move(to: left)
        path.addLine(to: to)
        path.addLine(to: right)
        return path
    }
}

/// A plain straight line (no head).
struct LineMark: View {
    let annotation: Annotation
    let size: CGSize

    var body: some View {
        Path { path in
            path.move(to: annotation.startPoint(in: size))
            path.addLine(to: annotation.endPoint(in: size))
        }
        .stroke(
            annotation.color.color,
            style: StrokeStyle(lineWidth: annotation.thickness, lineCap: .round)
        )
        .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 0.5)
    }
}

/// A stroked rounded rectangle outlining a region.
struct RectangleMark: View {
    let annotation: Annotation
    let size: CGSize

    var body: some View {
        let rect = annotation.rect(in: size)
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(annotation.color.color, lineWidth: annotation.thickness)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 0.5)
    }
}

/// A translucent highlighter band — like a marker swiped over the text, with softly
/// rounded ends so it reads as a highlight and not a filled box (CS-085). The content
/// stays legible through it.
struct HighlighterMark: View {
    let annotation: Annotation
    let size: CGSize

    var body: some View {
        let rect = annotation.rect(in: size)
        // Round to ~a third of the band's shorter side (capped) for the soft marker
        // ends, like a real highlighter.
        let radius = min(min(rect.width, rect.height) * 0.35, 16)
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(annotation.color.color.opacity(0.4))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

/// A text-callout: bold rounded text on a dark translucent pill so it stays legible
/// over any theme or background. An empty string renders nothing.
struct TextMark: View {
    let annotation: Annotation
    let size: CGSize

    var body: some View {
        if !annotation.text.isEmpty {
            Text(annotation.text)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(annotation.color.color)
                .padding(.horizontal, fontSize * 0.5)
                .padding(.vertical, fontSize * 0.28)
                .background(
                    RoundedRectangle(cornerRadius: fontSize * 0.5, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                )
                .position(annotation.startPoint(in: size))
        }
    }

    private var fontSize: CGFloat { max(12, annotation.thickness * 4) }
}

/// A numbered badge — a filled circle in the mark color with a white number, for
/// walking a viewer through steps (CS-085).
struct CounterMark: View {
    let annotation: Annotation
    let size: CGSize

    var body: some View {
        let diameter = max(24, annotation.thickness * 4 + 16)
        Circle()
            .fill(annotation.color.color)
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: max(1, diameter * 0.04)))
            .overlay(
                Text(verbatim: "\(annotation.number)")
                    .font(.system(size: diameter * 0.52, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
            .position(annotation.startPoint(in: size))
    }
}
