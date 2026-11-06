import SwiftUI
import VitrineRendering

/// What the mark's toolbar is placed against: the selected mark, reported from inside the
/// scaled preview, and stage chrome it must not cover, such as the status capsule.
struct MarkToolbarAnchors {
    var mark: Anchor<CGRect>?
    var avoiding: [Anchor<CGRect>] = []
}

struct MarkToolbarAnchorsKey: PreferenceKey {
    static var defaultValue: MarkToolbarAnchors { MarkToolbarAnchors() }
    static func reduce(value: inout MarkToolbarAnchors, nextValue: () -> MarkToolbarAnchors) {
        let next = nextValue()
        value.mark = value.mark ?? next.mark
        value.avoiding += next.avoiding
    }
}

/// Where the selected mark's toolbar sits on the stage. Nonisolated, as `Layout` calls it.
nonisolated enum AnnotationMarkToolbarPlacement {
    enum Side { case above, below, after, before, overlapping }

    static let gap: CGFloat = 6
    static let margin: CGFloat = 8

    /// The first side of `mark` with room, in the order above, below, after, before, slid
    /// along that side to stay inside `bounds` and off `avoiding`. With no room on any side
    /// it overlaps the top of the stage.
    static func place(
        _ size: CGSize, beside mark: CGRect, avoiding: [CGRect] = [], in bounds: CGRect
    ) -> (origin: CGPoint, side: Side) {
        let inner = bounds.insetBy(dx: margin, dy: margin)
        let x = max(min(mark.midX - size.width / 2, inner.maxX - size.width), inner.minX)
        let y = max(min(mark.midY - size.height / 2, inner.maxY - size.height), inner.minY)
        let candidates: [(CGPoint, Side)] = [
            (CGPoint(x: x, y: mark.minY - gap - size.height), .above),
            (CGPoint(x: x, y: mark.maxY + gap), .below),
            (CGPoint(x: mark.maxX + gap, y: y), .after),
            (CGPoint(x: mark.minX - gap - size.width, y: y), .before),
        ]
        for (origin, side) in candidates {
            let frame = CGRect(origin: origin, size: size)
            if inner.contains(frame), !avoiding.contains(where: frame.intersects) {
                return (origin, side)
            }
        }
        return (CGPoint(x: x, y: inner.minY), .overlapping)
    }
}

/// Fills the stage and places the toolbar at its natural size beside `mark`.
struct MarkToolbarLayout: Layout {
    let mark: CGRect
    let avoiding: [CGRect]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard let toolbar = subviews.first else { return }
        let size = toolbar.sizeThatFits(.unspecified)
        let origin = AnnotationMarkToolbarPlacement.place(
            size, beside: mark, avoiding: avoiding, in: CGRect(origin: .zero, size: bounds.size)
        ).origin
        toolbar.place(
            at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
            anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}

/// Places the toolbar beside the mark, opening its popover away from the mark, and holds
/// it in place while its size slider is dragged so the slider stays under the pointer.
struct MarkToolbarPlacer<Toolbar: View>: View {
    let mark: CGRect
    let avoiding: [CGRect]
    let stage: CGSize
    let toolbar: (_ popoverEdge: Edge, _ holdPlace: @escaping (Bool) -> Void) -> Toolbar

    @State private var held: CGRect?
    @State private var size = CGSize.zero

    var body: some View {
        let target = held ?? mark
        let side = AnnotationMarkToolbarPlacement.place(
            size, beside: target, avoiding: avoiding, in: CGRect(origin: .zero, size: stage)
        ).side
        MarkToolbarLayout(mark: target, avoiding: avoiding) {
            toolbar(side == .above ? .top : .bottom) { holding in
                held = holding ? (held ?? mark) : nil
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
        }
    }
}

/// Color, size and Duplicate beside the selected mark. It takes the title bar's bindings, so
/// both edit the same mark and close the edit as one undo step.
struct AnnotationMarkToolbar: View {
    @Binding var color: Color
    @Binding var thickness: Double
    let showsColor: Bool
    let showsThickness: Bool
    let popoverEdge: Edge
    let focus: FocusState<Bool>.Binding
    let onStyleEditEnded: () -> Void
    let onSizeDragging: (Bool) -> Void
    let onDuplicate: () -> Void
    /// Arrows and Delete still reach the mark while a toolbar button has the keyboard.
    let onMarkKey: (KeyPress) -> KeyPress.Result
    /// Escape hands the keyboard back to the mark.
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if showsColor {
                ColorSwatchButton(
                    color: $color, identifier: "annotation-mark-toolbar-color",
                    arrowEdge: popoverEdge, onEditEnded: onStyleEditEnded
                )
                .focused(focus)
            }
            if showsThickness {
                AnnotationSizeSlider(
                    thickness: $thickness, identifier: "annotation-mark-toolbar-size",
                    onEditEnded: onStyleEditEnded, onDragging: onSizeDragging)
            }
            duplicateButton
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            Capsule(style: .continuous)
                .fill(VitrineTokens.Surface.card)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
        )
        .onKeyPress(
            keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .delete, .deleteForward],
            action: onMarkKey
        )
        .onExitCommand(perform: onExit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected mark")
        .accessibilityIdentifier("annotation-mark-toolbar")
    }

    @ViewBuilder private var duplicateButton: some View {
        let button = Button(action: onDuplicate) {
            Image(systemName: "plus.square.on.square")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(VitrineTokens.Text.secondary)
                .frame(width: 26, height: 25)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Duplicate")
        .accessibilityLabel("Duplicate")
        .accessibilityIdentifier("annotation-mark-toolbar-duplicate")
        // One focus target: the swatch when the mark has a color, otherwise this.
        if showsColor { button } else { button.focused(focus) }
    }
}
