import SwiftUI

// The shared chrome components of the redesigned surfaces (design/handoff).
// Every visual value here resolves through `VitrineTokens`; the shapes and
// measurements mirror the HTML UI kits' component classes one to one, so the
// Settings window, the editor inspector, and the menu-bar panel all read as the
// same design system.

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
                            isSelected ? VitrineTokens.Accent.system : VitrineTokens.Line.border,
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
    @Bindable var settings: AppSettings
    var fontSize: CGFloat = 11
    var verticalPadding: CGFloat = 5
    var horizontalPadding: CGFloat = 12
    var topPadding: CGFloat = 12
    var bottomPadding: CGFloat = 6
    /// Show a filter field above the strip (for the roomier Settings pane).
    var searchable: Bool = false

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if searchable {
                ChipFilterField(query: $query, prompt: "Filter fonts")
                    .accessibilityIdentifier("font-filter-field")
            }
            ChipScroll(topPadding: topPadding, bottomPadding: bottomPadding) {
                ForEach(filteredFonts, id: \.self) { family in
                    FontChip(
                        family: family, isSelected: settings.config.fontName == family,
                        fontSize: fontSize, verticalPadding: verticalPadding,
                        horizontalPadding: horizontalPadding
                    ) {
                        settings.config.fontName = family
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Font")
    }

    private var filteredFonts: [String] {
        guard !query.isEmpty else { return CodeFont.all }
        return CodeFont.all.filter { $0.localizedCaseInsensitiveContains(query) }
    }
}
