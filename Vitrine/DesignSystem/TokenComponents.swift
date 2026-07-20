import SwiftUI

// The shared chrome components of the current designed surfaces.
// Every visual value here resolves through `VitrineTokens`; the shapes and
// measurements mirror the design-system component classes one to one, so the
// Settings window, the editor inspector, and the menu-bar panel all read as the
// same design system.

/// The uppercase, letter-spaced group label above a tile.
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
/// Uses the shared tile fill, hairline border, and 14-point radius.
struct TokenGroup<Content: View>: View {
    var title: Text? = nil
    /// Optional explanatory line under the section label — for clarifying a
    /// section's scope (e.g. what "Theme" affects versus the rest of "Style").
    var caption: Text? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || caption != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        TokenGroupLabel(title: title)
                    }
                    if let caption {
                        caption
                            .font(.system(size: VitrineTokens.FontSize.caption))
                            .foregroundStyle(VitrineTokens.Text.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
/// Uses 9-point vertical padding and a 12-point gap.
struct TokenRow<Content: View>: View {
    var label: Text? = nil
    var caption: Text? = nil
    @ViewBuilder var content: Content

    var body: some View {
        // Center the trailing control against the *label line* (always one line,
        // stable) and let the caption flow full-width beneath it — the macOS
        // System Settings layout. This keeps the control's vertical position
        // fixed when the caption reflows (e.g. toggling a segmented option whose
        // description grows or shrinks), instead of re-centering the control
        // against a label+caption block whose height changes.
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: VitrineTokens.Spacing.sm) {
                if let label {
                    label
                        .font(.system(size: VitrineTokens.FontSize.body))
                        .foregroundStyle(VitrineTokens.Text.primary)
                }
                Spacer(minLength: VitrineTokens.Spacing.sm)
                // When a caption exists, attach it to the control as its VoiceOver hint
                // so the explanation is announced together with the control;
                // no caption means no hint, rather than an empty one. The visible caption
                // stays accessible below — for a single control that is a harmless second
                // read, but for a composite control (several buttons in an HStack) the
                // hint may not reach the focused child, so keeping the caption as its own
                // element is what stops the explanation from being lost.
                if let caption {
                    content.accessibilityHint(caption)
                } else {
                    content
                }
            }
            if let caption {
                caption
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 9)
    }
}

/// The pill segmented control: a capsule track of small
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
        .accessibilityValue(selectedLabel)
    }

    /// The selected option's label, surfaced as the control's accessibility value so
    /// VoiceOver announces "<label>: <selection>" like a native segmented control.
    private var selectedLabel: Text {
        options.first { $0.value == selection }?.label ?? Text(verbatim: "")
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
                    isSelected ? VitrineTokens.Accent.systemContrast : VitrineTokens.Text.secondary
                )
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .background {
                    if isSelected {
                        // The selected segment lifts onto a system-accent pill so the
                        // control follows the user's macOS accent like the rest of the
                        // chrome (selection/links/chips), instead of a neutral white card.
                        Capsule(style: .continuous)
                            .fill(VitrineTokens.Accent.system)
                            .brandShadow(VitrineTokens.Chrome.segmentShadow)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The bordered inline text field of the current designed forms (`.dfield`): fixed
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
