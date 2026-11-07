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

    /// Whether the code layout draws source `row`: a diff row that no fold or hunk pick hides.
    public func showsDiffRow(_ row: Int) -> Bool {
        guard diffOptionsApply, !code.isEmpty else { return false }
        let document = DiffLayoutCache.shared.document(for: code)
        guard document.rowKinds.indices.contains(row - 1) else { return false }
        return diffDisplayRows(of: document)?.contains(.line(row)) ?? true
    }
}

/// Places pinned comments from their rows: right-aligned at the row's trailing edge and
/// centered on it, so each reads as a note on its line in either layout.
public enum DiffCommentLayout {
    static let trailingInset: CGFloat = 8
    static let gap: CGFloat = 4

    /// A comment's callout in canvas points, and the width its text wraps at.
    public struct Placement: Equatable, Sendable {
        public var frame: CGRect
        public var textWidth: CGFloat
        public var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    }

    /// Places each comment on its row. Text wraps past most of the row's width, so a long
    /// comment stays on the card, and a callout that would cover a neighbor's moves left of
    /// it. Only the comments' own text sizes them, so a redacted row's length never shows.
    public static func place(
        _ comments: [(annotation: Annotation, row: CGRect)]
    ) -> [UUID: Placement] {
        var placed: [UUID: Placement] = [:]
        var taken: [CGRect] = []
        let ordered = comments.enumerated().sorted {
            ($0.element.row.minY, $0.offset) < ($1.element.row.minY, $1.offset)
        }
        for (_, comment) in ordered {
            let row = comment.row
            let fontSize = TextMark.fontSize(for: comment.annotation.thickness)
            let limit = max(
                fontSize * 3, min(row.width * 0.6, row.width - fontSize - trailingInset))
            let text = comment.annotation.text.isEmpty ? "Note" : comment.annotation.text
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: limit, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: TextMark.font(size: fontSize)])
            let textWidth = min(ceil(bounds.width) + 1, limit)
            let size = CGSize(
                width: textWidth + fontSize, height: ceil(bounds.height) + fontSize * 0.56)
            var frame = CGRect(
                x: max(row.maxX - trailingInset - size.width, row.minX),
                y: row.midY - size.height / 2, width: size.width, height: size.height)
            for _ in 0...taken.count {
                guard
                    let other = taken.first(where: {
                        frame.insetBy(dx: -gap / 2, dy: -gap / 2).intersects($0)
                    })
                else { break }
                if other.minX - gap - size.width >= row.minX {
                    frame.origin.x = other.minX - gap - size.width
                } else {
                    frame.origin.y = other.maxY + gap
                }
            }
            taken.append(frame)
            placed[comment.annotation.id] = Placement(frame: frame, textWidth: textWidth)
        }
        return placed
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
                    } else if let placement = placed[annotation.id] {
                        TextMark(
                            annotation: moved(
                                annotation, to: normalized(placement.center, in: size)),
                            size: size, textWidth: placement.textWidth)
                    }
                }
            }
            .preference(
                key: DiffCommentPositionsKey.self,
                value: placed.mapValues { normalized($0.center, in: size) })
        }
    }

    private func placements(in proxy: GeometryProxy) -> [UUID: DiffCommentLayout.Placement] {
        DiffCommentLayout.place(
            annotations.compactMap { annotation in
                guard annotation.kind == .text, let anchor = annotation.lineAnchor,
                    !anchor.isDetached,
                    let rowAnchor = anchors[DiffLineSlot(row: anchor.row, side: anchor.side)]
                else { return nil }
                return (annotation, proxy[rowAnchor])
            })
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
