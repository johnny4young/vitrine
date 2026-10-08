import SwiftUI

/// A slider with a trailing numeric readout, so the current value can be read and
/// targeted. The readout is hidden from VoiceOver because the slider announces it.
struct ValueSlider: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let identifier: String
    var width: CGFloat = 110

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: $value, in: range, step: step)
                .frame(width: width)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
            Text(verbatim: "\(Int(value.rounded()))")
                .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .frame(width: 26, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}
