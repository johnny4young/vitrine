import SwiftUI
import VitrineDomain

/// One drawn copy of a source row: the row and the diff side it shows.
struct DiffLineSlot: Hashable {
    let row: Int
    let side: DiffLineAnchor.Side
}

/// The bounds of each drawn row a comment is pinned to.
struct DiffLineFrameKey: PreferenceKey {
    static let defaultValue: [DiffLineSlot: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [DiffLineSlot: Anchor<CGRect>], nextValue: () -> [DiffLineSlot: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, next in next }
    }
}

/// Where the canvas placed each pinned comment, normalized to the canvas, so the editor's
/// handles follow the drawn mark. A comment missing here is not drawn.
public struct DiffCommentPositionsKey: PreferenceKey {
    public static let defaultValue: [UUID: CGPoint] = [:]
    public static func reduce(value: inout [UUID: CGPoint], nextValue: () -> [UUID: CGPoint]) {
        value.merge(nextValue()) { _, next in next }
    }
}

extension View {
    /// Reports this row's bounds for every side in `sides` that a comment is pinned to.
    @ViewBuilder
    func reportingDiffLine(
        row: Int, sides: [DiffLineAnchor.Side], wanted: Set<DiffLineSlot>
    ) -> some View {
        let slots = sides.map { DiffLineSlot(row: row, side: $0) }.filter(wanted.contains)
        if slots.isEmpty {
            self
        } else {
            anchorPreference(key: DiffLineFrameKey.self, value: .bounds) { anchor in
                Dictionary(uniqueKeysWithValues: slots.map { ($0, anchor) })
            }
        }
    }
}

extension SnapshotConfig {
    /// The rows pinned comments need placed. Only a diff draws them: other text has no
    /// sides, and a terminal crop renumbers its rows.
    var diffCommentSlots: Set<DiffLineSlot> {
        guard diffOptionsApply, !code.isEmpty else { return [] }
        return Set(
            annotations.compactMap { annotation in
                guard annotation.kind == .text, let anchor = annotation.lineAnchor,
                    !anchor.isDetached
                else { return nil }
                return DiffLineSlot(row: anchor.row, side: anchor.side)
            })
    }

    var hasLineAnchoredAnnotations: Bool {
        annotations.contains { $0.lineAnchor != nil }
    }
}

/// Places a pinned comment from its row: right-aligned at the row's trailing edge and
/// centered on it, so it reads as a note on that line in either layout.
public enum DiffCommentLayout {
    static let trailingInset: CGFloat = 8

    /// The callout's center in canvas points. Only the comment's own text sizes it, so a
    /// redacted row's length never shows.
    public static func center(of annotation: Annotation, rowFrame: CGRect) -> CGPoint {
        let fontSize = TextMark.fontSize(for: annotation.thickness)
        let text = annotation.text.isEmpty ? "Note" : annotation.text
        let textWidth = (text as NSString).size(
            withAttributes: [.font: TextMark.font(size: fontSize)]
        ).width
        let half = (textWidth + fontSize) / 2
        let x = max(rowFrame.maxX - trailingInset - half, rowFrame.minX + half)
        return CGPoint(x: x, y: rowFrame.midY)
    }
}

/// The annotation marks, with each pinned comment placed from its row's frame. A comment
/// whose row is folded away, detached or missing is left out.
struct AnchoredAnnotationMarks: View {
    let annotations: [Annotation]
    let anchors: [DiffLineSlot: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let placed = placements(in: proxy)
            ZStack {
                ForEach(annotations) { annotation in
                    if annotation.lineAnchor == nil {
                        AnnotationMarkView(annotation: annotation, size: size)
                    } else if let point = placed[annotation.id] {
                        AnnotationMarkView(
                            annotation: moved(annotation, to: normalized(point, in: size)),
                            size: size)
                    }
                }
            }
            .preference(
                key: DiffCommentPositionsKey.self,
                value: placed.mapValues { normalized($0, in: size) })
        }
    }

    private func placements(in proxy: GeometryProxy) -> [UUID: CGPoint] {
        var placed: [UUID: CGPoint] = [:]
        for annotation in annotations where annotation.kind == .text {
            guard let anchor = annotation.lineAnchor, !anchor.isDetached,
                let rowAnchor = anchors[DiffLineSlot(row: anchor.row, side: anchor.side)]
            else { continue }
            placed[annotation.id] = DiffCommentLayout.center(
                of: annotation, rowFrame: proxy[rowAnchor])
        }
        return placed
    }

    private func moved(_ annotation: Annotation, to point: CGPoint) -> Annotation {
        var moved = annotation
        moved.start = point
        moved.end = point
        return moved
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: point.x / size.width, y: point.y / size.height)
    }
}
