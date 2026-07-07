import SwiftUI

/// The SwiftUI view that becomes an exported social card (CS-041). WYSIWYG: what
/// renders here is exactly what `ImageRenderer` exports — no WebKit, no network.
///
/// The card fills a fixed 1200×630 frame (the default OpenGraph size) with the
/// configured background, then composes the model's copy — title, subtitle, a
/// syntax-highlighted code excerpt, an author/project footer, and the optional
/// Vitrine logo — according to the chosen `SocialCardTemplate`. The code excerpt
/// is highlighted synchronously through `HighlightManager` (not via `.task`)
/// because `ImageRenderer` does not run async view lifecycle, so the exported
/// image is fully highlighted at render time, exactly like `SnapshotCanvas`.
///
/// ## Color strategy
///
/// Two surfaces, two color sources. The **headline copy** sits over the canvas
/// background, so its color is chosen for legibility *over that background* — light
/// over a gradient/image/transparent canvas (with a soft shadow), and luminance
/// matched over a solid color. The **code panel** is the theme's own opaque card,
/// so the excerpt and its gutter take their colors from the theme via
/// `HighlightManager`, identical to a normal snapshot. This keeps a card readable
/// on any background/theme pairing while staying fully deterministic.
struct SocialCardCanvas: View {
    let model: SocialCardModel

    /// The exact logical size to render at. Defaults to the 1200×630 OpenGraph
    /// card; a caller can override it for a different fixed destination.
    var size: CGSize = SocialCardModel.defaultSize

    var body: some View {
        content
            .padding(Self.framePadding)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(BackgroundView(style: model.background))
            .clipped()
    }

    /// Frame inset around the whole card composition, in points.
    private static let framePadding: CGFloat = 72

    // MARK: - Template composition

    @ViewBuilder
    private var content: some View {
        switch model.template {
        case .standard:
            standardLayout
        case .codeFocus:
            codeFocusLayout
        case .headline:
            headlineLayout
        }
    }

    /// Headline block at the top, code panel filling the middle, footer pinned to
    /// the bottom. The signature card composition.
    private var standardLayout: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
            headlineBlock(alignment: .leading)
            if model.template.showsCode, !model.codeExcerpt.isEmpty {
                codePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Spacer(minLength: 0)
            }
            footerRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The excerpt takes center stage, with the headline above it and the footer
    /// below; the copy frames the snippet rather than dominating it.
    private var codeFocusLayout: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            headlineBlock(alignment: .leading, compact: true)
            if model.template.showsCode, !model.codeExcerpt.isEmpty {
                codePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Spacer(minLength: 0)
            }
            footerRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Headline and subtitle only, centered, with the footer beneath. No code
    /// panel — for announcements and quotes.
    private var headlineLayout: some View {
        VStack(alignment: .center, spacing: Brand.Spacing.lg) {
            Spacer(minLength: 0)
            headlineBlock(alignment: .center)
            Spacer(minLength: 0)
            footerRow
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }

    // MARK: - Building blocks

    /// The title + subtitle block, optionally prefixed by the brand logo. `compact`
    /// shrinks the type a step so a code-forward layout keeps the snippet dominant.
    @ViewBuilder
    private func headlineBlock(alignment: HorizontalAlignment, compact: Bool = false) -> some View {
        VStack(alignment: alignment, spacing: Brand.Spacing.sm) {
            if model.showLogo {
                BrandMark(size: compact ? 40 : 52)
                    .brandShadow(Brand.Shadow.card)
            }
            if let title = model.title {
                Text(title)
                    .font(.system(size: compact ? 52 : 68, weight: .bold, design: .rounded))
                    .foregroundStyle(onBackgroundPrimary)
                    .brandShadow(headlineShadow)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let subtitle = model.subtitle {
                Text(subtitle)
                    .font(.system(size: compact ? 26 : 32, weight: .medium))
                    .foregroundStyle(onBackgroundSecondary)
                    .brandShadow(headlineShadow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    /// The syntax-highlighted code excerpt on the theme's own card surface, with a
    /// hairline border and an elevated shadow — the same vocabulary as a snapshot.
    private var codePanel: some View {
        Text(highlightedExcerpt)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(alignment: .topLeading)
            .background(HighlightManager.shared.backgroundColor(for: model.theme))
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous)
                    .strokeBorder(
                        Brand.Palette.exportedCardBorder, lineWidth: Brand.Stroke.hairline)
            )
            .brandShadow(Brand.Shadow.elevated)
    }

    /// The footer: an author/handle and/or a project name, shown only when at least
    /// one is present (CS-041 "author/project").
    @ViewBuilder
    private var footerRow: some View {
        if model.hasFooter {
            HStack(spacing: Brand.Spacing.sm) {
                if let author = model.author {
                    Text(author)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(onBackgroundPrimary)
                }
                if model.author != nil, model.project != nil {
                    // A non-localizable middle-dot separator: shown verbatim so it
                    // never enters the String Catalog (CS-047).
                    Text(verbatim: "·")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(onBackgroundSecondary)
                }
                if let project = model.project {
                    Text(project)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(onBackgroundSecondary)
                }
            }
            .brandShadow(headlineShadow)
        }
    }

    // MARK: - Color resolution

    /// The primary color for copy drawn over the canvas background, chosen for
    /// legibility: near-white over a colored/gradient/image/transparent canvas, or
    /// luminance-matched over a solid color.
    private var onBackgroundPrimary: Color {
        backgroundIsLight ? Color.black.opacity(0.88) : Color.white
    }

    /// The secondary (dimmer) color for subtitles and the project line, derived
    /// from the same legibility choice.
    private var onBackgroundSecondary: Color {
        backgroundIsLight ? Color.black.opacity(0.62) : Color.white.opacity(0.78)
    }

    /// A soft shadow under copy drawn over the background, so light text stays
    /// legible over a bright gradient stop without a heavy outline. Omitted (clear)
    /// over a light solid background where dark text needs no lift.
    private var headlineShadow: Brand.ShadowStyle {
        backgroundIsLight
            ? Brand.ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
            : Brand.ShadowStyle(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
    }

    /// Whether the canvas background reads as light, so dark copy is more legible
    /// over it. Only a solid color can be confidently classified by luminance;
    /// gradients, images, and transparency default to "dark" so the safe, high
    /// contrast light copy is used (a transparent card is composited over an unknown
    /// surface, where light text with a shadow is the safer default).
    private var backgroundIsLight: Bool {
        if case .solid(let color) = model.background {
            return Brand.Contrast.relativeLuminance(color.color) > 0.55
        }
        return false
    }

    /// The resolved code font for the excerpt (the named family or a monospaced
    /// system fallback), with the card's documented font size.
    private var excerptFont: NSFont {
        CodeFont.resolved(family: model.fontName, size: model.fontSize, ligatures: false)
    }

    /// The excerpt, syntax-highlighted with the model's theme and language through
    /// the same engine a snapshot uses, as a SwiftUI `AttributedString`.
    private var highlightedExcerpt: AttributedString {
        HighlightManager.shared.swiftUIAttributedString(
            for: model.codeExcerpt,
            language: model.language,
            theme: model.theme,
            font: excerptFont
        )
    }
}
