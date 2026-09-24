import SwiftUI
import VitrineDomain
import VitrineRendering

/// Canonical destination-chip ids and their short labels, single-sourced so the
/// Settings picker and the editor inspector's two-row variant never drift.
/// The labels are product/brand tokens shown verbatim in every locale.
enum DestinationChips {
    /// Every chip in display order. The editor inspector shows all of them.
    static let all: [(id: String, label: String)] = [
        ("twitter", "X"),
        ("linkedin", "LinkedIn"),
        ("opengraph", "OG"),
        ("keynote", "Keynote"),
        ("docs", "Docs"),
        ("transparent-slide", "Slide"),
    ]
}

/// The complete destination catalog in Settings. The shared segmented control wraps
/// naturally instead of omitting an option when the column is narrow.
struct DestinationSegmentedPicker: View {
    @Bindable var settings: AppSettings

    /// Sentinel tag for the "Custom" segment (no preset). Not a valid preset id.
    private static let customTag = ""

    var body: some View {
        TokenSegmentedPicker(
            options: options, selection: selectionBinding,
            optionIdentifiers: ["settings-destination-custom"]
                + DestinationChips.all.map { "settings-destination-\($0.id)" }
        )
        .help(presetHelp)
        .accessibilityLabel("Destination preset")
        .accessibilityIdentifier("destination-preset-picker")
    }

    private var options: [(String, Text)] {
        [(Self.customTag, Text("Custom"))]
            + DestinationChips.all.map { ($0.id, Text(verbatim: $0.label)) }
    }

    private var presetHelp: String {
        settings.selectedPreset?.summary
            ?? "Custom: your own size and style, with no destination preset applied."
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: { settings.selectedPresetID ?? Self.customTag },
            set: { id in
                if let preset = ExportPreset.preset(withID: id) {
                    settings.selectPreset(preset)
                } else {
                    settings.clearPreset()
                }
            }
        )
    }
}

/// An editor for the selected-line highlight spec.
///
/// The user types a compact spec like `3, 7-9, 12`; on every change it is parsed
/// into normalized 1-based inclusive ranges and pushed into `config`. The text the
/// user is typing is kept in local state (not re-derived from the parsed result on
/// each keystroke), so an in-progress entry such as `7-` is not rewritten out from
/// under the caret; the field is re-canonicalized from the config only when it
/// first appears or the config changes underneath it (e.g. a reset).
struct HighlightedLinesField: View {
    @Bindable var settings: AppSettings
    @State private var text: String = ""

    var body: some View {
        TokenTextField(prompt: Text("e.g. 3, 7-9, 12"), text: $text)
            .help("Lines or ranges to highlight, e.g. 3, 7-9, 12")
            // Match the visible row label so VoiceOver and the title agree.
            .accessibilityLabel("Highlight lines")
            .accessibilityIdentifier("highlight-lines-field")
            .onAppear { text = LineHighlight.describe(settings.style.highlightedLineRanges) }
            .onChange(of: text) { _, newValue in
                let parsed = LineHighlight.parse(newValue)
                if parsed != settings.style.highlightedLineRanges {
                    settings.style.highlightedLineRanges = parsed
                }
            }
            // Re-seed from the config when it changes elsewhere (e.g. Reset All
            // Settings) so the field never shows stale text.
            .onChange(of: settings.style.highlightedLineRanges) { _, newValue in
                let canonical = LineHighlight.describe(newValue)
                if LineHighlight.parse(text) != newValue { text = canonical }
            }
    }
}

/// Editors for the optional metadata header — filename, title, caption, and a
/// language-badge toggle.
///
/// Each text field maps to an optional `SnapshotMetadata` field through a binding
/// that normalizes on the way in (trim, empty → `nil`), so a blank entry never
/// reserves header space. The fields are reused by both the Style pane and the
/// editor's inline metadata bar so there is one labeled, accessible set of
/// controls. Every control carries an explicit accessibility label and identifier
/// .
struct MetadataFields: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Group {
            TokenRow(label: Text("Filename")) {
                TokenTextField(prompt: Text("e.g. ContentView.swift"), text: filenameBinding)
                    .help("Optional filename shown as a chip in the header")
                    .accessibilityLabel("Filename")
                    .accessibilityIdentifier("metadata-filename-field")
            }

            TokenRow(label: Text("Title")) {
                TokenTextField(prompt: Text("e.g. Aurora gradient"), text: titleBinding)
                    .help("Optional title shown above the code")
                    .accessibilityLabel("Title")
                    .accessibilityIdentifier("metadata-title-field")
            }

            TokenRow(label: Text("Caption")) {
                TokenTextField(prompt: Text("e.g. A SwiftUI gradient"), text: captionBinding)
                    .help("Optional one-line caption shown under the title")
                    .accessibilityLabel("Caption")
                    .accessibilityIdentifier("metadata-caption-field")
            }

            TokenRow(label: Text("Language badge")) {
                Toggle("Language badge", isOn: $settings.style.metadata.showLanguageBadge)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Show the current language as a badge in the header")
                    .accessibilityLabel("Language badge")
                    .accessibilityIdentifier("metadata-language-badge-toggle")
            }
        }
    }

    private var filenameBinding: Binding<String> {
        field(\.filename)
    }

    private var titleBinding: Binding<String> {
        field(\.title)
    }

    private var captionBinding: Binding<String> {
        field(\.caption)
    }

    /// A `String` binding over one optional metadata field: reads `nil` as the
    /// empty string and writes a normalized value back (empty/whitespace → `nil`),
    /// so the live config and the field stay in sync without ever storing a blank.
    private func field(_ keyPath: WritableKeyPath<SnapshotMetadata, String?>) -> Binding<String> {
        Binding(
            get: { settings.style.metadata[keyPath: keyPath] ?? "" },
            set: { settings.style.metadata[keyPath: keyPath] = SnapshotMetadata.normalized($0) }
        )
    }
}
