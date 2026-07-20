import SwiftUI

/// A branded empty-state placeholder built entirely from design tokens.
///
/// Used where a surface has no content yet (e.g. the editor before any code is
/// pasted). It pairs the Vitrine brand mark with a title, a short message, and an
/// optional primary action, and washes the background with the signature
/// gradient so empty states feel like part of the display case rather than a
/// blank rectangle.
struct EmptyStateView: View {
    // `LocalizedStringKey`-typed so callers pass plain string literals that flow
    // through the String Catalog automatically, and `Text`/`Button` below
    // render them localized.
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?
    /// The editor's narrow code column uses the compact metrics; full windows
    /// (the recents gallery) use the regular ones.
    var compact = false

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
                BrandMark(size: compact ? 44 : 56)
                Text(title)
                    .font(.system(size: compact ? 15 : 17, weight: .bold))
                    .foregroundStyle(Brand.Palette.textPrimary.color)
                Text(message)
                    .font(
                        .system(
                            size: compact
                                ? VitrineTokens.FontSize.subhead : VitrineTokens.FontSize.body)
                    )
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Brand.Palette.textSecondary.color)
                    .frame(maxWidth: 420)
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
