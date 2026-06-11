import SwiftUI

// The shared chrome components of the redesigned surfaces (design/handoff).
// Every visual value here resolves through `VitrineTokens`; the shapes and
// measurements mirror the HTML UI kits' component classes one to one, so the
// Settings window, the editor inspector, and the menu-bar panel all read as the
// same design system.

/// The uppercase, letter-spaced group label above a tile (`.lbl` in the kits).
struct TokenGroupLabel: View {
    let title: Text

    var body: some View {
        title
            .font(.system(size: VitrineTokens.FontSize.caption, weight: .semibold))
            .foregroundStyle(VitrineTokens.Text.tertiary)
            .textCase(.uppercase)
            .tracking(VitrineTokens.FontSize.caption * 0.07)
    }
}

/// A grouped-form section: optional uppercase label + a rounded tile of rows
/// (`Group` in the settings kit: tile fill, hairline border, radius 14).
struct TokenGroup<Content: View>: View {
    var title: Text? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                TokenGroupLabel(title: title)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, VitrineTokens.Spacing.md)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VitrineTokens.Radius.lg, style: .continuous)
                    .fill(VitrineTokens.Chrome.tile)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VitrineTokens.Radius.lg, style: .continuous)
                    .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
            )
        }
    }
}

/// One label + optional caption + trailing control row inside a `TokenGroup`
/// (`Row` in the settings kit: 9 pt vertical padding, 12 pt gap).
struct TokenRow<Content: View>: View {
    var label: Text? = nil
    var caption: Text? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: VitrineTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                if let label {
                    label
                        .font(.system(size: VitrineTokens.FontSize.body))
                        .foregroundStyle(VitrineTokens.Text.primary)
                }
                if let caption {
                    caption
                        .font(.system(size: VitrineTokens.FontSize.caption))
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            content
        }
        .padding(.vertical, 9)
    }
}

/// The pill segmented control (`.seg` in the kits): a capsule track of small
/// capsule buttons; the selected one lifts onto a card-colored pill.
struct TokenSegmentedPicker<Value: Hashable>: View {
    /// The selectable values, in display order, each with its visible label.
    let options: [(value: Value, label: Text)]
    @Binding var selection: Value
    /// When `true`, segments stretch to share the available width equally
    /// (the sticky style sub-tabs); otherwise the control hugs its content.
    var fillsWidth: Bool = false
    /// Optional stable identifiers, one per option in order, so UI tests can
    /// address individual segments independently of their localized titles.
    var optionIdentifiers: [String]? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                segment(option.value, label: option.label)
                    .accessibilityIdentifier(identifier(at: index))
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(VitrineTokens.Chrome.segmentTrack))
        .accessibilityElement(children: .contain)
    }

    private func identifier(at index: Int) -> String {
        guard let optionIdentifiers, index < optionIdentifiers.count else { return "" }
        return optionIdentifiers[index]
    }

    private func segment(_ value: Value, label: Text) -> some View {
        let isSelected = value == selection
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selection = value }
        } label: {
            label
                .font(.system(size: VitrineTokens.FontSize.caption, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(
                    isSelected ? VitrineTokens.Text.primary : VitrineTokens.Text.secondary
                )
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(VitrineTokens.Surface.card)
                            .brandShadow(VitrineTokens.Chrome.segmentShadow)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The bordered inline text field of the redesigned forms (`.dfield`): fixed
/// 160 pt, right-aligned, hairline border that turns into the accent focus
/// ring while editing.
struct TokenTextField: View {
    let prompt: Text
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text, prompt: prompt.foregroundStyle(VitrineTokens.Text.tertiary))
            .textFieldStyle(.plain)
            .focused($isFocused)
            .multilineTextAlignment(.trailing)
            .font(.system(size: VitrineTokens.FontSize.subhead))
            .foregroundStyle(VitrineTokens.Text.primary)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .frame(width: 160)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VitrineTokens.Chrome.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isFocused ? VitrineTokens.Line.focusRing : VitrineTokens.Line.border,
                        lineWidth: isFocused ? Brand.Stroke.focus : Brand.Stroke.hairline
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .inset(by: -1.5)
                    .stroke(
                        isFocused ? VitrineTokens.Line.focusGlow : .clear,
                        lineWidth: 3
                    )
            )
    }
}

/// A keyboard-glyph chip (`.kbd-chip`): the hotkey shown as typed glyphs in a
/// small bordered capsule-cornered tag.
struct KeyChip: View {
    /// The literal glyph string (e.g. `"⇧⌘S"`); locale-neutral, shown verbatim.
    let glyphs: String

    var body: some View {
        Text(verbatim: glyphs)
            .font(.system(size: VitrineTokens.FontSize.subhead, design: .monospaced))
            .foregroundStyle(VitrineTokens.Text.primary)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(VitrineTokens.Chrome.keyChip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
            )
    }
}

/// A horizontally scrolling chip strip (`.hscroll`): 7 pt gaps, hidden
/// scroller, and a 26 pt fade-out mask on the trailing edge hinting at more.
struct ChipScroll<Content: View>: View {
    var topPadding: CGFloat = 12
    var bottomPadding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                content
            }
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .padding(.horizontal, 2)
        }
        .mask(
            GeometryReader { proxy in
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(
                            color: .black,
                            location: max(0, (proxy.size.width - 26) / max(proxy.size.width, 1))),
                        .init(color: .black.opacity(0), location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
        )
    }
}

// MARK: - Buttons

/// The signature gradient call-to-action capsule (`.cta`): white semibold
/// label on the brand gradient, accent halo, +10 % brightness on hover and a
/// 0.98 press scale. Shared by the editor toolbar, the menu-bar panel, and the
/// Welcome window.
struct GradientCTAButton<Label: View>: View {
    @ViewBuilder var label: Label
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                label
            }
            .font(.system(size: VitrineTokens.FontSize.body, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, VitrineTokens.Spacing.xs)
            .padding(.horizontal, 18)
            .background(Capsule(style: .continuous).fill(VitrineTokens.Gradients.signature))
            .brandShadow(VitrineTokens.Chrome.ctaShadow)
            .brightness(isHovered ? 0.06 : 0)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

/// Scales the pressed control to 0.98 — the kits' universal press affordance.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The quiet pill button (`.ghost`): hairline border, secondary label that
/// lifts to primary on hover. The understated counterpart to the gradient CTA.
struct GhostPillButton: View {
    let title: Text
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            title
                .font(.system(size: VitrineTokens.FontSize.body, weight: .medium))
                .foregroundStyle(
                    isHovered ? VitrineTokens.Text.primary : VitrineTokens.Text.secondary
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, VitrineTokens.Spacing.xs)
                .padding(.horizontal, 18)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isHovered ? VitrineTokens.Text.tertiary : VitrineTokens.Line.border,
                            lineWidth: Brand.Stroke.hairline
                        )
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

/// A bordered 30×30 icon button on a glass panel (`.ibtn`): hairline border,
/// secondary glyph that lifts to primary on hover.
struct GlassIconButton: View {
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    isHovered ? VitrineTokens.Text.primary : VitrineTokens.Text.secondary
                )
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            isHovered ? VitrineTokens.Text.tertiary : VitrineTokens.Line.border,
                            lineWidth: Brand.Stroke.hairline
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Theme chips

/// The representative chip colors for the built-in themes — the card
/// background plus three signature palette dots (keyword / string / function),
/// exactly as specified in the handoff kits. Custom themes derive the same
/// quartet from their user palette.
enum ThemeChipColors {
    /// `id → (background, dot1, dot2, dot3)` for the built-in catalog.
    private static let builtIns: [String: (bg: String, a: String, b: String, c: String)] = [
        "one-dark": ("#282C34", "#C678DD", "#98C379", "#61AFEF"),
        "one-light": ("#FAFAFA", "#A626A4", "#50A14F", "#4078F2"),
        "dracula": ("#282A36", "#FF79C6", "#F1FA8C", "#50FA7B"),
        "github": ("#FFFFFF", "#D73A49", "#005CC5", "#6F42C1"),
        "github-dark": ("#0D1117", "#FF7B72", "#79C0FF", "#D2A8FF"),
        "gruvbox": ("#282828", "#FB4934", "#B8BB26", "#FABD2F"),
        "monokai": ("#272822", "#F92672", "#E6DB74", "#A6E22E"),
        "night-owl": ("#011627", "#C792EA", "#ECC48D", "#82AAFF"),
        "nord": ("#2E3440", "#81A1C1", "#A3BE8C", "#88C0D0"),
        "solarized": ("#002B36", "#859900", "#2AA198", "#268BD2"),
        "solarized-light": ("#FDF6E3", "#859900", "#2AA198", "#268BD2"),
        "tokyo-night": ("#1A1B26", "#BB9AF7", "#9ECE6A", "#7AA2F7"),
        "xcode-dark": ("#1F1F24", "#FC5FA3", "#FC6A5D", "#5DD8FF"),
    ]

    /// The kits' chip display order: the signature One Dark / One Light pair
    /// leads (they are the default and its light twin), then the rest of the
    /// catalog. Pickers elsewhere stay alphabetical; the chip strips follow
    /// the handoff exactly.
    private static let displayOrder: [String] = [
        "one-dark", "one-light", "dracula", "github", "github-dark", "gruvbox",
        "monokai", "night-owl", "nord", "solarized", "solarized-light",
        "tokyo-night", "xcode-dark",
    ]

    /// The built-in catalog in the kits' chip order. Any built-in missing from
    /// the order list (a future addition) is appended rather than dropped.
    static var orderedBuiltIns: [Theme] {
        let byID = Dictionary(uniqueKeysWithValues: Theme.builtIns.map { ($0.id, $0) })
        var ordered = displayOrder.compactMap { byID[$0] }
        let listed = Set(displayOrder)
        ordered.append(contentsOf: Theme.builtIns.filter { !listed.contains($0.id) })
        return ordered
    }

    /// The chip quartet for a theme: the kit-specified colors for a built-in,
    /// or the palette-derived ones for a custom theme. A theme with neither
    /// (not expected) falls back to the One Dark chip so the strip never gaps.
    static func colors(for theme: Theme) -> (bg: Color, dots: [Color]) {
        if let entry = builtIns[theme.id] {
            return (
                Color(hex: entry.bg),
                [Color(hex: entry.a), Color(hex: entry.b), Color(hex: entry.c)]
            )
        }
        if let palette = theme.palette {
            return (
                palette.background.color,
                [palette.keyword.color, palette.string.color, palette.function.color]
            )
        }
        let fallback = builtIns["one-dark"]!
        return (
            Color(hex: fallback.bg),
            [Color(hex: fallback.a), Color(hex: fallback.b), Color(hex: fallback.c)]
        )
    }
}

/// One selectable theme chip: a small card in the theme's background with
/// three palette dots, the name underneath, and the accent ring when selected.
/// Sized 50×32 in the Settings kit and 52×34 in the editor inspector.
struct ThemeChip: View {
    let theme: Theme
    let isSelected: Bool
    var chipSize: CGSize = CGSize(width: 50, height: 32)
    var dotSize: CGFloat = 5.5
    let action: () -> Void

    var body: some View {
        let colors = ThemeChipColors.colors(for: theme)
        Button(action: action) {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors.bg)
                    .frame(width: chipSize.width, height: chipSize.height)
                    .overlay(
                        HStack(spacing: 4) {
                            ForEach(Array(colors.dots.enumerated()), id: \.offset) { _, dot in
                                Circle().fill(dot).frame(width: dotSize, height: dotSize)
                            }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? VitrineTokens.Accent.base : VitrineTokens.Line.border,
                                lineWidth: isSelected ? 2 : Brand.Stroke.hairline
                            )
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .inset(by: -1.5)
                            .stroke(
                                isSelected ? VitrineTokens.Line.focusGlow : .clear, lineWidth: 3)
                    )
                Text(verbatim: theme.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(
                        isSelected ? VitrineTokens.Text.primary : VitrineTokens.Text.tertiary
                    )
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: theme.displayName))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The horizontally scrolling theme-chip picker shared by the Style settings
/// pane and the editor inspector. Built-ins lead; custom themes follow.
struct ThemeChipPicker: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var themes: CustomThemeStore
    var chipSize: CGSize = CGSize(width: 50, height: 32)
    var dotSize: CGFloat = 5.5
    var topPadding: CGFloat = 12
    var bottomPadding: CGFloat = 12

    var body: some View {
        ChipScroll(topPadding: topPadding, bottomPadding: bottomPadding) {
            ForEach(ThemeChipColors.orderedBuiltIns) { theme in
                chip(for: theme)
            }
            ForEach(themes.customThemes) { theme in
                chip(for: theme)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme")
    }

    private func chip(for theme: Theme) -> some View {
        ThemeChip(
            theme: theme, isSelected: settings.config.theme.id == theme.id,
            chipSize: chipSize, dotSize: dotSize
        ) {
            settings.config.theme = themes.theme(withID: theme.id)
        }
    }
}

// MARK: - Font chips

/// One selectable font pill, rendered in its own face (`.pill` in the kits).
/// 11 pt / 5×12 padding in Settings; 11.5 pt / 6×13 in the editor inspector.
struct FontChip: View {
    let family: String
    let isSelected: Bool
    var fontSize: CGFloat = 11
    var verticalPadding: CGFloat = 5
    var horizontalPadding: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: family)
                .font(.custom(family, size: fontSize))
                .foregroundStyle(VitrineTokens.Text.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.vertical, verticalPadding)
                .padding(.horizontal, horizontalPadding)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? VitrineTokens.Chrome.pillSelectedFill : .clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? VitrineTokens.Accent.base : VitrineTokens.Line.border,
                            lineWidth: Brand.Stroke.hairline
                        )
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: family))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The horizontally scrolling font-pill picker, one pill per bundled or
/// system monospace family, each shown in its own face.
struct FontChipPicker: View {
    @ObservedObject var settings: AppSettings
    var fontSize: CGFloat = 11
    var verticalPadding: CGFloat = 5
    var horizontalPadding: CGFloat = 12
    var topPadding: CGFloat = 12
    var bottomPadding: CGFloat = 6

    var body: some View {
        ChipScroll(topPadding: topPadding, bottomPadding: bottomPadding) {
            ForEach(CodeFont.all, id: \.self) { family in
                FontChip(
                    family: family, isSelected: settings.config.fontName == family,
                    fontSize: fontSize, verticalPadding: verticalPadding,
                    horizontalPadding: horizontalPadding
                ) {
                    settings.config.fontName = family
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Font")
    }
}

// MARK: - Gradient swatches

/// One gradient swatch (`.swatch`): rounded, hover-scaled, with the selected
/// border + focus ring. 26 pt in Settings, 28 pt in the editor inspector.
struct GradientSwatch: View {
    let preset: GradientPreset
    let isSelected: Bool
    var size: CGFloat = 26
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(preset.gradient)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            isSelected ? VitrineTokens.Chrome.swatchSelectedBorder : .clear,
                            lineWidth: 2
                        )
                )
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .inset(by: -1.5)
                        .stroke(isSelected ? VitrineTokens.Line.focusGlow : .clear, lineWidth: 3)
                )
                .scaleEffect(isHovered ? 1.08 : 1)
                .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text(verbatim: preset.rawValue))
        .accessibilityLabel(Text(verbatim: preset.rawValue))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The dashed "+" swatch that leads to the custom background kinds.
struct CustomBackgroundSwatch: View {
    var size: CGFloat = 26
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    VitrineTokens.Line.border,
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])
                )
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                )
                .scaleEffect(isHovered ? 1.08 : 1)
                .animation(.easeInOut(duration: 0.12), value: isHovered)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Custom — solid color or image")
        .accessibilityLabel("Custom background")
    }
}
