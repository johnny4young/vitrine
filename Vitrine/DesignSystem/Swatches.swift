import SwiftUI
import VitrineDomain
import VitrineRendering

// The shared chrome components of the current designed surfaces.
// Every visual value here resolves through `VitrineTokens`; the shapes and
// measurements mirror the design-system component classes one to one, so the
// Settings window, the editor inspector, and the menu-bar panel all read as the
// same design system.

// MARK: - Gradient swatches

/// One gradient swatch (`.swatch`): rounded, hover-scaled, with the selected
/// border + focus ring. 26 pt in Settings, 28 pt in the editor inspector.
struct GradientSwatch: View {
    let preset: GradientPreset
    let isSelected: Bool
    var size: CGFloat = 26
    let action: () -> Void

    var body: some View {
        FillSwatch(
            title: Text(verbatim: preset.rawValue), isSelected: isSelected, size: size,
            action: action
        ) {
            preset.gradient
        }
    }
}

/// The swatch chrome around any fill.
struct FillSwatch<Fill: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: Text
    let isSelected: Bool
    var size: CGFloat = 26
    let action: () -> Void
    @ViewBuilder var fill: Fill

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            fill
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                .modifier(
                    DecorativeScaleEffect(
                        isActive: isHovered, scale: 1.08, reduceMotion: reduceMotion))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The dashed "+" swatch that leads to the custom background kinds.
struct CustomBackgroundSwatch: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .modifier(
                    DecorativeScaleEffect(
                        isActive: isHovered, scale: 1.08, reduceMotion: reduceMotion)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Solid color, custom gradient, or image")
        .accessibilityLabel("Custom background")
    }
}
