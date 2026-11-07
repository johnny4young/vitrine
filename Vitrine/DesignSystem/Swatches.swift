import SwiftUI
import VitrineDomain
import VitrineRendering

// The shared chrome components of the current designed surfaces.
// Every visual value here resolves through `VitrineTokens`; the shapes and
// measurements mirror the design-system component classes one to one, so the
// Settings window, the editor inspector, and the menu-bar panel all read as the
// same design system.

// MARK: - Gradient swatches

/// One gradient swatch (`.swatch`): rounded, hover-scaled, with a hairline, or a
/// ring when selected. 26 pt in Settings, 28 pt in the editor inspector.
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
                .clipShape(
                    RoundedRectangle(cornerRadius: isSelected ? 6 : 9, style: .continuous)
                )
                // The gap keeps the ring readable on a fill of its own color, such as Aurora.
                .padding(isSelected ? 3.5 : 0)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? VitrineTokens.Chrome.swatchSelectedBorder
                                : VitrineTokens.Line.border,
                            lineWidth: isSelected ? Brand.Stroke.focus : Brand.Stroke.hairline
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .modifier(
                    DecorativeScaleEffect(
                        isActive: isHovered, scale: DecorativeScaleEffect.hoverScale,
                        reduceMotion: reduceMotion))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The cells an image viewer shows behind transparency.
struct TransparencyGrid: View {
    var cell: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(VitrineTokens.Chrome.checkerBase))
            let squares = Path { path in
                for row in 0...Int(size.height / cell) {
                    for column in 0...Int(size.width / cell) where (row + column).isMultiple(of: 2)
                    {
                        path.addRect(
                            CGRect(
                                x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                                width: cell, height: cell))
                    }
                }
            }
            context.fill(squares, with: .color(VitrineTokens.Chrome.checkerSquare))
        }
    }
}

/// The swatch that derives a background from the capture.
struct MagicBackgroundSwatch: View {
    let isSelected: Bool
    var size: CGFloat = 26
    let action: () -> Void

    var body: some View {
        FillSwatch(title: Text("Magic"), isSelected: isSelected, size: size, action: action) {
            AngularGradient(
                colors: GradientPreset.allCases.flatMap { $0.stopColors.map(\.color) },
                center: .center
            )
            .overlay(
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
            )
        }
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
                        isActive: isHovered, scale: DecorativeScaleEffect.hoverScale,
                        reduceMotion: reduceMotion)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Solid color, custom gradient, or image")
        .accessibilityLabel("Custom background")
    }
}
