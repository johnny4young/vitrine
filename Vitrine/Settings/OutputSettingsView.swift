import SwiftUI

/// Output pane: clipboard/save behavior, resolution, format (CS-010).
struct OutputSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPaneScroll {
            TokenGroup(title: Text("Export")) {
                TokenRow(
                    label: Text("Destination"),
                    caption: Text("Presets set the image size and resolution for a destination")
                ) {
                    DestinationSegmentedPicker(settings: settings)
                }
                TokenRow(label: Text("Copy to clipboard automatically")) {
                    Toggle("Copy to clipboard automatically", isOn: $settings.autoCopy)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                TokenRow(label: Text("Also save to a file")) {
                    Toggle("Also save to a file", isOn: $settings.alsoSaveToFile)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                TokenRow(label: Text("Close the editor after copying")) {
                    Toggle("Close the editor after copying", isOn: $settings.closeAfterCopy)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("close-after-copy-toggle")
                }
                TokenRow(label: Text("Resolution")) {
                    TokenSegmentedPicker(
                        options: [
                            (1, Text(verbatim: "1×")),
                            (2, Text(verbatim: "2×")),
                            (3, Text(verbatim: "3×")),
                        ],
                        selection: $settings.exportScale
                    )
                    .accessibilityLabel("Resolution")
                    .accessibilityIdentifier("output-resolution-picker")
                }
                // The caption states honestly which output is vector: PDF is the
                // supported scalable format; PNG is raster (CS-023).
                TokenRow(label: Text("Format"), caption: Text(settings.exportFormat.summary)) {
                    TokenSegmentedPicker(
                        options: ExportFormat.allCases.map {
                            ($0, Text(verbatim: $0.displayName))
                        },
                        selection: $settings.exportFormat
                    )
                    .accessibilityLabel("Format")
                    .accessibilityIdentifier("output-format-picker")
                }
            }

            // Rich clipboard is opt-in so the default copy stays a plain image; the
            // explicit "Copy as Data URI" and "Copy Highlighted Code" actions in the
            // editor remain available regardless of this toggle (CS-054).
            TokenGroup(title: Text("Clipboard")) {
                TokenRow(
                    label: Text("Rich-text code on copy"),
                    caption: Text(
                        "Keeps colors and font when pasting; the image is always included")
                ) {
                    Toggle("Rich-text code on copy", isOn: $settings.richClipboard)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("rich-clipboard-toggle")
                }
            }

            // Color management lives in its own "Advanced" group so the default
            // (sRGB) stays the obvious choice and Display P3 reads as a deliberate
            // opt-in (CS-024).
            TokenGroup(title: Text("Advanced")) {
                TokenRow(
                    label: Text("Color profile"),
                    caption: Text(settings.colorProfile.summary)
                ) {
                    TokenSegmentedPicker(
                        options: [
                            (ColorProfile.sRGB, Text(verbatim: "sRGB")),
                            (.displayP3, Text(verbatim: "P3")),
                        ],
                        selection: $settings.colorProfile
                    )
                    .accessibilityLabel("Color profile")
                    .accessibilityIdentifier("color-profile-picker")
                }
            }
        }
        .accessibilityIdentifier("settings-output-pane")
    }
}
