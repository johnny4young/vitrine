import SwiftUI

// MARK: - Inspector chrome
//
// Shared inspector building blocks used by the Editor, Web Snapshot, and Social
// Card inspectors so every inspector column reads the same. Promoted here from the
// Editor (where they were private) so sibling windows reuse one set of metrics
// instead of each rolling its own `section()` / `row()` helpers.

/// A wrapping row: lays subviews left-to-right and wraps to the next line when the
/// current one runs out of width. Used for chip rows that must show **every** option
/// (e.g. the multi-select viewport chips) in a narrow inspector without clipping or
/// horizontal scrolling.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// An uppercase-labeled inspector section: 11 pt gaps, no tile (the glass
/// column itself is the surface).
struct InspectorSection<Content: View>: View {
    let title: Text
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            TokenGroupLabel(title: title)
            content
        }
    }
}

/// A labeled inspector row (label on the left, control on the right). Shared so
/// sibling inspector panels use one row metric.
struct InspectorRow<Content: View>: View {
    let label: Text
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            label
                .font(.system(size: VitrineTokens.FontSize.body))
                .foregroundStyle(VitrineTokens.Text.primary)
            Spacer(minLength: 0)
            content
        }
    }
}

/// A collapsed-by-default disclosure: hairline on top, a
/// rotating chevron, and a semibold body label.
struct InspectorDisclosure<Content: View>: View {
    let label: Text
    let identifier: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .overlay(VitrineTokens.Line.separator)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(VitrineTokens.Text.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    label
                        .font(.system(size: VitrineTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(VitrineTokens.Text.primary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, VitrineTokens.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)

            if isExpanded {
                VStack(alignment: .leading, spacing: 11) {
                    content
                }
                .padding(.bottom, VitrineTokens.Spacing.sm)
            }
        }
    }
}
