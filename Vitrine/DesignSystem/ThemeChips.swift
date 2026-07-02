import SwiftUI

// The shared chrome components of the redesigned surfaces (design/handoff).
// Every visual value here resolves through `VitrineTokens`; the shapes and
// measurements mirror the HTML UI kits' component classes one to one, so the
// Settings window, the editor inspector, and the menu-bar panel all read as the
// same design system.

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
                                isSelected
                                    ? VitrineTokens.Accent.system : VitrineTokens.Line.border,
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

/// A compact filter field shown above a chip strip when searchable, so a long
/// theme/font catalog is filterable instead of scroll-only.
struct ChipFilterField: View {
    @Binding var query: String
    let prompt: LocalizedStringKey

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(VitrineTokens.Text.tertiary)
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: VitrineTokens.FontSize.subhead))
                .foregroundStyle(VitrineTokens.Text.primary)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(VitrineTokens.Chrome.fieldFill))
    }
}

/// The horizontally scrolling theme-chip picker shared by the Style settings
/// pane and the editor inspector. Built-ins lead; custom themes follow.
struct ThemeChipPicker: View {
    @Bindable var settings: AppSettings
    var themes: CustomThemeStore
    var chipSize: CGSize = CGSize(width: 50, height: 32)
    var dotSize: CGFloat = 5.5
    var topPadding: CGFloat = 12
    var bottomPadding: CGFloat = 12
    /// Show a filter field above the strip (for the roomier Settings pane).
    var searchable: Bool = false

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if searchable {
                ChipFilterField(query: $query, prompt: "Filter themes")
                    .accessibilityIdentifier("theme-filter-field")
            }
            ChipScroll(topPadding: topPadding, bottomPadding: bottomPadding) {
                ForEach(filteredThemes) { theme in
                    chip(for: theme)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme")
    }

    private var filteredThemes: [Theme] {
        let all = ThemeChipColors.orderedBuiltIns + themes.customThemes
        guard !query.isEmpty else { return all }
        return all.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
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
