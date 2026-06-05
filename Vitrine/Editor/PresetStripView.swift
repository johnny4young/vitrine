import SwiftUI

/// The editor's preset-first command strip (CS-037).
///
/// This is deliberately the **first** band of controls in the editor, above the
/// code and preview: the product promise is that beautiful output comes from
/// choosing a strong preset, not from tweaking many sliders before seeing value.
/// The strip pairs the two preset axes that frame an image —
///
/// - **Destination** (`ExportPreset`): sizes and styles the canvas for a place to
///   post it (X, LinkedIn, OpenGraph, …), reusing the same picker the Settings
///   panes use so the two stay in lockstep (CS-020).
/// - **Style** (`StylePreset`): a named brand look (theme + background + layout)
///   the user applies in one click, drawn from the built-in catalog plus anything
///   they have saved (CS-030).
///
/// Selecting a style preset applies it immediately — the strip's job is to make a
/// great look one choice away — while the destination picker keeps its existing
/// apply-on-select behavior. Both controls carry stable accessibility identifiers
/// so the strip is reachable by keyboard and assertable in UI tests; the strip
/// itself is a single labeled accessibility container ("Presets").
struct PresetStripView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var presets: PresetStore

    /// Sentinel tag for the "no style preset chosen" row. A style preset never
    /// reports as active here (the live style can diverge field-by-field), so the
    /// picker is an *apply* affordance, not an applied-state mirror — mirroring how
    /// the Settings pane treats style presets.
    private static let noStyleTag = "__none__"

    var body: some View {
        HStack(spacing: Brand.Spacing.md) {
            Label("Presets", systemImage: "rectangle.3.group")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.Palette.textSecondary.color)
                .labelStyle(.titleAndIcon)
                .accessibilityHidden(true)

            DestinationPresetPicker(
                settings: settings, identifier: "editor-destination-preset-picker"
            )
            .frame(maxWidth: Brand.Layout.headerControlMaxWidth)

            stylePresetPicker
                .frame(maxWidth: Brand.Layout.headerControlMaxWidth)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Brand.Spacing.md)
        .padding(.vertical, Brand.Spacing.sm)
        .background(Brand.Surface.glass)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Presets")
        .accessibilityIdentifier("editor-preset-strip")
    }

    /// The style-preset picker: a "Style…" prompt, the built-in catalog, and any
    /// saved presets. Choosing a row applies that preset's look to the live config
    /// at once, then resets the selection back to the prompt so the control reads
    /// as a one-shot action rather than claiming an active value the live style may
    /// already have drifted from.
    private var stylePresetPicker: some View {
        Picker("Style", selection: styleBinding) {
            Text("Style…").tag(Self.noStyleTag)
            Section("Built-in") {
                ForEach(StylePreset.builtIns) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            if !presets.userPresets.isEmpty {
                Section("Saved") {
                    ForEach(presets.userPresets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
            }
        }
        .help("Apply a saved or built-in style — theme, background, and layout — in one step.")
        .accessibilityLabel("Style preset")
        .accessibilityIdentifier("editor-style-preset-picker")
    }

    private var styleBinding: Binding<String> {
        Binding(
            get: { Self.noStyleTag },
            set: { id in
                guard id != Self.noStyleTag, let preset = presets.preset(withID: id) else { return }
                settings.applyStylePreset(preset)
            }
        )
    }
}
