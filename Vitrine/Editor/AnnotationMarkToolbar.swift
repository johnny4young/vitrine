import SwiftUI
import VitrineRendering

/// The selected mark's outline, handles and delete badge, reported from inside the scaled
/// preview so the stage can place the mark's toolbar at its natural size.
struct SelectedMarkChromeKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Where the selected mark's toolbar sits on the stage. Nonisolated, as `Layout` calls it.
nonisolated enum AnnotationMarkToolbarPlacement {
    static let gap: CGFloat = 6
    static let margin: CGFloat = 8

    /// The first side of `mark` with room, in the order above, below, after, before, slid
    /// along that side to stay inside `bounds`. With no room on any side it goes to the top.
    static func origin(for size: CGSize, beside mark: CGRect, in bounds: CGRect) -> CGPoint {
        let inner = bounds.insetBy(dx: margin, dy: margin)
        let x = max(min(mark.midX - size.width / 2, inner.maxX - size.width), inner.minX)
        let y = max(min(mark.midY - size.height / 2, inner.maxY - size.height), inner.minY)
        if mark.minY - gap - size.height >= inner.minY {
            return CGPoint(x: x, y: mark.minY - gap - size.height)
        }
        if mark.maxY + gap + size.height <= inner.maxY {
            return CGPoint(x: x, y: mark.maxY + gap)
        }
        if mark.maxX + gap + size.width <= inner.maxX {
            return CGPoint(x: mark.maxX + gap, y: y)
        }
        if mark.minX - gap - size.width >= inner.minX {
            return CGPoint(x: mark.minX - gap - size.width, y: y)
        }
        return CGPoint(x: x, y: inner.minY)
    }
}

/// Fills the stage and places the toolbar at its natural size beside `mark`.
struct MarkToolbarLayout: Layout {
    let mark: CGRect

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard let toolbar = subviews.first else { return }
        let size = toolbar.sizeThatFits(.unspecified)
        let origin = AnnotationMarkToolbarPlacement.origin(
            for: size, beside: mark, in: CGRect(origin: .zero, size: bounds.size))
        toolbar.place(
            at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
            anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}

/// Color, size and Duplicate beside the selected mark. It takes the title bar's bindings, so
/// both edit the same mark and close the edit as one undo step.
struct AnnotationMarkToolbar: View {
    @Binding var color: Color
    @Binding var thickness: Double
    let showsColor: Bool
    let showsThickness: Bool
    let focus: FocusState<Bool>.Binding
    let onStyleEditEnded: () -> Void
    let onDuplicate: () -> Void
    /// Delete still removes the mark while a toolbar control has the keyboard.
    let onDelete: () -> Bool
    /// Escape hands the keyboard back to the mark.
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if showsColor {
                ColorSwatchButton(
                    color: $color, identifier: "annotation-mark-toolbar-color",
                    onEditEnded: onStyleEditEnded
                )
                .focused(focus)
            }
            if showsThickness {
                AnnotationSizeSlider(
                    thickness: $thickness, identifier: "annotation-mark-toolbar-size",
                    onEditEnded: onStyleEditEnded)
            }
            duplicateButton
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Capsule(style: .continuous).fill(VitrineTokens.Surface.card))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
        )
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in onDelete() ? .handled : .ignored }
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
