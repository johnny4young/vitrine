import SwiftUI

/// The editor's right-hand inspector (CS-037).
///
/// Progressive disclosure is the whole point: the **primary** style controls a
/// user reaches for most — theme, font, padding, chrome, shadow — sit open at the
/// top, while the more specialized controls (lines, header metadata, background,
/// output resolution/format) live in collapsible sections that start closed. A
/// first-time user sees a short, legible set of choices and never a wall of
/// sliders; the advanced knobs are one disclosure away rather than gone.
///
/// The inspector reuses the exact components the Settings panes use —
/// ``CoreStyleControls``, ``HighlightedLinesField``, ``MetadataFields``, and
/// ``BackgroundEditor`` — so there is one labeled, accessible set of style
/// controls in the app rather than two that can drift. Each section is keyboard-
/// reachable, and the whole panel is a single accessibility container
/// ("Inspector") tagged for UI tests.
struct EditorInspectorView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var themes: CustomThemeStore

    /// Disclosure state for the advanced sections. All start collapsed so the
    /// inspector opens compact; the primary style cluster above them is always
    /// visible. State is per-window and intentionally not persisted — it is view
    /// chrome, not a user preference.
    @State private var showLines = false
    @State private var showHeader = false
    @State private var showBackground = false
    @State private var showOutput = false

    var body: some View {
        Form {
            // Primary cluster: always open, the first controls in the inspector.
            Section("Style") {
                CoreStyleControls(settings: settings, themes: themes)
            }

            // Advanced, progressively disclosed. Collapsible `Section`s give native
            // grouped-form chrome and a keyboard-focusable disclosure header.
            Section("Lines", isExpanded: $showLines) {
                Toggle("Line numbers", isOn: $settings.config.showLineNumbers)
                    .accessibilityIdentifier("line-numbers-toggle")
                HighlightedLinesField(settings: settings)
            }

            Section("Header", isExpanded: $showHeader) {
                MetadataFields(settings: settings)
            }

            Section("Background", isExpanded: $showBackground) {
                BackgroundEditor(background: $settings.config.background)
            }

            Section("Output", isExpanded: $showOutput) {
                Picker("Resolution", selection: $settings.exportScale) {
                    Text("1×").tag(1)
                    Text("2× (Retina)").tag(2)
                    Text("3×").tag(3)
                }
                .accessibilityIdentifier("inspector-resolution-picker")
                Picker("Format", selection: $settings.exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .accessibilityIdentifier("inspector-format-picker")
                // Name the vector option honestly: PDF is the supported scalable
                // format; PNG is raster (CS-023). The summary also appears as an
                // always-visible row below so the vector/raster guidance does not
                // depend on a hover tooltip, matching the Settings → Output pane.
                .help(settings.exportFormat.summary)

                Text(settings.exportFormat.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
        .accessibilityIdentifier("editor-inspector")
    }
}
