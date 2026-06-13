import SwiftUI

// Shared inspector input chrome for the editor-style composer windows (the social-card
// and web-snapshot inspectors). Both surfaces need the same full-width bordered text
// field and the same monospaced placeholder editor, so they live here once rather than
// being copy-pasted per window — the same reason the chip pickers and buttons live in
// `TokenComponents`.

/// A full-width inline text field for an inspector form field (`.dfield`,
/// leading-aligned), with the accent focus ring while editing.
struct InspectorTextField: View {
    /// The placeholder, as a `Text` so a caller can pass a localized key or a verbatim
    /// value (e.g. a URL example) without the field hard-coding either.
    let prompt: Text
    @Binding var text: String
    /// Called when the user presses Return; `nil` for fields with no submit action.
    var onSubmit: (() -> Void)?
    /// Disables autocorrection/auto-capitalization, for inputs that are not prose
    /// (a URL).
    var disablesAutocorrection = false

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            "", text: $text, prompt: prompt.foregroundStyle(VitrineTokens.Text.tertiary)
        )
        .textFieldStyle(.plain)
        .focused($isFocused)
        .font(.system(size: VitrineTokens.FontSize.subhead))
        .foregroundStyle(VitrineTokens.Text.primary)
        .autocorrectionDisabled(disablesAutocorrection)
        .onSubmit { onSubmit?() }
        .padding(.vertical, 6)
        .padding(.horizontal, 11)
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
    }
}

/// A monospaced multi-line editor for short code/markup input in an inspector, with a
/// faded placeholder shown over an empty field.
struct InspectorCodeField: View {
    @Binding var text: String
    /// The faded placeholder, shown verbatim (it is example code, never localized).
    var placeholder: String
    var height: CGFloat = 120

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(VitrineTokens.Text.primary)
            .scrollContentBackground(.hidden)
            .frame(height: height)
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VitrineTokens.Chrome.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
            )
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(verbatim: placeholder)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 14)
                        .allowsHitTesting(false)
                }
            }
    }
}
