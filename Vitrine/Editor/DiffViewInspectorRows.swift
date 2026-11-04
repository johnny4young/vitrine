import SwiftUI
import VitrineDomain
import VitrineRendering

/// The inspector rows that shape a diff: its stats header and how much context it keeps.
/// Shown only for content that reads as a diff.
struct DiffViewInspectorRows: View {
    @Bindable var settings: AppSettings

    var body: some View {
        if settings.style.diffOptionsApply {
            InspectorRow(label: Text("Stats header")) {
                Toggle("Stats header", isOn: $settings.style.showDiffStats)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("diff-stats-toggle")
            }
            InspectorRow(label: Text("Context lines")) {
                HStack(spacing: 8) {
                    Slider(
                        value: settings.diffContextSliderValue,
                        in: AppSettings.diffContextSliderRange, step: 1
                    )
                    .frame(width: 90)
                    .accessibilityLabel("Context lines")
                    .accessibilityValue(contextValue)
                    .accessibilityIdentifier("diff-context-slider")
                    contextValue
                        .font(
                            .system(size: VitrineTokens.FontSize.caption, design: .monospaced)
                        )
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    private var contextValue: Text {
        guard let lines = settings.style.diffContextLines else { return Text("All") }
        return Text(verbatim: "\(lines)")
    }
}
