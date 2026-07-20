import SwiftUI

// The shared chrome components of the current designed surfaces.
// Every visual value here resolves through `VitrineTokens`; the shapes and
// measurements mirror the design-system component classes one to one, so the
// Settings window, the editor inspector, and the menu-bar panel all read as the
// same design system.

// MARK: - Buttons

/// The signature gradient call-to-action capsule (`.cta`): white semibold
/// label on the brand gradient, accent halo, +10 % brightness on hover and a
/// 0.98 press scale. Shared by the editor toolbar, the menu-bar panel, and the
/// Welcome window.
struct GradientCTAButton<Label: View>: View {
    @ViewBuilder var label: Label
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

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
            // Keyboard focus ring (Full Keyboard Access): an accent halo shown only
            // while focused, so the unfocused CTA is unchanged.
            .overlay(
                Capsule(style: .continuous)
                    .inset(by: -2.5)
                    .stroke(isFocused ? VitrineTokens.Line.focusGlow : .clear, lineWidth: 3)
            )
            // No accent shadow when disabled — a glowing, full-color capsule must not
            // read as the active primary action when it does nothing.
            .brandShadow(isEnabled ? VitrineTokens.Chrome.ctaShadow : Brand.ShadowStyle.none)
            .brightness(isHovered ? 0.06 : 0)
            .contentShape(Capsule(style: .continuous))
            // Dim + desaturate the gradient when disabled so the state is visible
            // (a custom-painted background does not honor `.disabled()` on its own).
            .saturation(isEnabled ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressScaleButtonStyle())
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

/// Scales the pressed control to 0.98 — the universal press affordance.
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

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

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
                            isFocused
                                ? VitrineTokens.Line.focusRing
                                : (isHovered
                                    ? VitrineTokens.Text.tertiary : VitrineTokens.Line.border),
                            lineWidth: isFocused ? Brand.Stroke.focus : Brand.Stroke.hairline
                        )
                )
                // The keyboard focus ring (Full Keyboard Access): a soft accent glow,
                // shown only while focused so the unfocused look is unchanged.
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .inset(by: -1.5)
                        .stroke(isFocused ? VitrineTokens.Line.focusGlow : .clear, lineWidth: 3)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                // A `.plain` button over a hand-drawn border does not dim on its own;
                // fade it so a disabled icon button reads as inert.
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
