import SwiftUI
import VitrineDomain
import VitrineRendering

/// The inspector rows that shape a diff: its layout, stats header and how much context it
/// keeps. Shown only for content that reads as a diff.
struct DiffViewInspectorRows: View {
    @Bindable var settings: AppSettings

    var body: some View {
        if settings.style.diffOptionsApply {
            InspectorRow(label: Text("Layout")) {
                TokenSegmentedPicker(
                    options: [
                        (DiffViewMode.unified, Text("Unified")),
                        (DiffViewMode.split, Text("Split")),
                    ],
                    selection: settings.diffViewSelection,
                    optionIdentifiers: ["diff-view-unified", "diff-view-split"]
                )
                .disabled(settings.style.diffLayoutIsLocked)
                .opacity(settings.style.diffLayoutIsLocked ? 0.5 : 1)
                .accessibilityLabel("Layout")
                .accessibilityIdentifier("diff-view-picker")
            }
            InspectorRow(label: Text("Stats header")) {
                Toggle("Stats header", isOn: settings.diffStatsEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(settings.style.diffLayoutIsLocked)
                    .accessibilityIdentifier("diff-stats-toggle")
            }
            InspectorRow(label: Text("Context lines")) {
                HStack(spacing: 8) {
                    Slider(
                        value: settings.diffContextSliderValue,
                        in: AppSettings.diffContextSliderRange, step: 1
                    )
                    .frame(width: 90)
                    .disabled(settings.style.diffLayoutIsLocked)
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
            if settings.style.diffLayoutIsLocked {
                Text("Locked while a blur box is on the canvas.")
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .accessibilityIdentifier("diff-view-locked-note")
            }
        }
    }

    private var contextValue: Text {
        guard let lines = settings.style.diffContextLines else { return Text("All") }
        return Text(verbatim: "\(lines)")
    }
}
