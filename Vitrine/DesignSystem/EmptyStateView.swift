import SwiftUI

/// A branded empty-state placeholder built entirely from design tokens (CS-036).
///
/// Used where a surface has no content yet (e.g. the editor before any code is
/// pasted). It pairs the Vitrine brand mark with a title, a short message, and an
/// optional primary action, and washes the background with the signature
/// gradient so empty states feel like part of the display case rather than a
/// blank rectangle.
struct EmptyStateView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Brand.Spacing.md) {
            // The non-interactive identity + copy collapse into a single
            // VoiceOver element (mark is decorative), so the user hears the
            // title and message as one announcement. Hit testing is disabled so
            // that when this view is used as an overlay over an editable surface
            // (e.g. the empty code editor), a click falls through to the surface
            // and the caret can land — the copy invites typing as well as
            // pasting.
            Group {
                BrandMark(size: 44)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Brand.Palette.textPrimary.color)
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Brand.Palette.textSecondary.color)
            }
            .accessibilityElement(children: .combine)
            .allowsHitTesting(false)

            // The action stays a discrete, focusable button with its
            // `.isButton` trait intact — never folded into the text blob. It
            // keeps hit testing so the primary action remains clickable even
            // though the surrounding wash lets clicks through.
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, Brand.Spacing.xxs)
            }
        }
        .padding(Brand.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Gradient.signatureWash().allowsHitTesting(false))
        .accessibilityIdentifier("empty-state")
    }
}
