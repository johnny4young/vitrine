import SwiftUI

// MARK: - Inspector chrome (editor kit)
//
// Shared inspector building blocks used by the Editor, Web Snapshot, and Social
// Card inspectors so every inspector column reads the same. Promoted here from the
// Editor (where they were private) so sibling windows reuse one set of metrics
// instead of each rolling its own `section()` / `row()` helpers.

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

/// A collapsed-by-default disclosure (`.disc` in the kit): hairline on top, a
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
