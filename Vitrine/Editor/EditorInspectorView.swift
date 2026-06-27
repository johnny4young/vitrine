import SwiftUI

/// The editor's right-hand inspector (CS-037), restyled per design/handoff: a
/// 302 pt glass column of uppercase-labeled sections — Background swatches,
/// Theme chips, Typography pills, Canvas — with the specialized controls
/// (Lines, Header, Output) behind collapsed disclosures, so a first-time user
/// sees a short, legible set of choices and never a wall of sliders.
///
/// The chip pickers are the same components the Settings Style pane uses
/// (``ThemeChipPicker``, ``FontChipPicker``, ``GradientSwatch``), at the editor
/// kit's slightly larger metrics, so there is one accessible set of style
/// controls in the app rather than two that can drift.
struct EditorInspectorView: View {
    @Bindable var settings: AppSettings
    var themes: CustomThemeStore

    /// Disclosure state for the advanced sections. All start collapsed so the
    /// inspector opens compact; the primary style cluster above them is always
    /// visible. State is per-window and intentionally not persisted — it is view
    /// chrome, not a user preference.
    @State private var showLines = false
    @State private var showHeader = false
    @State private var showOutput = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xl - 12) {
                backgroundSection
                themeSection
                typographySection
                canvasSection

                VStack(alignment: .leading, spacing: 0) {
                    InspectorDisclosure(
                        label: Text("Lines"), identifier: "inspector-disclosure-lines",
                        isExpanded: $showLines
                    ) {
                        InspectorRow(label: Text("Line numbers")) {
                            Toggle("Line numbers", isOn: $settings.config.showLineNumbers)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .accessibilityIdentifier("line-numbers-toggle")
                        }
                        InspectorRow(label: Text("Wrap long lines")) {
                            Toggle("Wrap long lines", isOn: settings.wrapsLongLines)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .help("Soft-wrap past a column width instead of widening the card")
                                .accessibilityIdentifier("wrap-lines-toggle")
                        }
                        if settings.config.wrapsLongLines {
                            InspectorRow(label: Text("Wrap width")) {
                                HStack(spacing: 8) {
                                    Slider(
                                        value: settings.wrapColumnsValue,
                                        in: SettingsDefaults.wrapColumnsSliderRange, step: 4
                                    )
                                    .frame(width: 90)
                                    .accessibilityLabel("Wrap width")
                                    .accessibilityIdentifier("wrap-columns-slider")
                                    Text(
                                        verbatim:
                                            "\(settings.config.wrapColumns ?? SettingsDefaults.wrapColumns)"
                                    )
                                    .font(
                                        .system(
                                            size: VitrineTokens.FontSize.caption,
                                            design: .monospaced)
                                    )
                                    .foregroundStyle(VitrineTokens.Text.tertiary)
                                    .frame(width: 26, alignment: .trailing)
                                }
                            }
                        }
                        InspectorRow(label: Text("Highlight lines")) {
                            HighlightedLinesField(settings: settings)
                        }
                        InspectorRow(label: Text("Focus highlighted")) {
                            Toggle(
                                "Focus highlighted", isOn: $settings.config.focusHighlightedLines
                            )
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(settings.config.highlightedLineRanges.isEmpty)
                            .help("Dim the lines outside the highlight so it stands out.")
                            .accessibilityIdentifier("focus-lines-toggle")
                        }
                        InspectorRow(label: Text("Diff bands")) {
                            Toggle("Diff bands", isOn: $settings.config.diffDecorations)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .help(
                                    "Color lines that start with + green and − red, GitHub-style. Choosing the Diff language turns this on for you."
                                )
                                .accessibilityIdentifier("diff-decorations-toggle")
                        }
                    }

                    InspectorDisclosure(
                        label: Text("Header"), identifier: "inspector-disclosure-header",
                        isExpanded: $showHeader
                    ) {
                        MetadataFields(settings: settings)
                    }

                    InspectorDisclosure(
                        label: Text("Output"), identifier: "inspector-disclosure-output",
                        isExpanded: $showOutput
                    ) {
                        outputControls
                    }
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, VitrineTokens.Spacing.xl - 12)
            .padding(.bottom, VitrineTokens.Spacing.lg)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(VitrineTokens.Line.border)
                .frame(width: Brand.Stroke.hairline)
        }
        .tint(VitrineTokens.Accent.system)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
        .accessibilityIdentifier("editor-inspector")
    }

    // MARK: - Sections

    /// Background: the gradient preset swatches plus the dashed "+" leading to
    /// the custom kinds. The kind picker and per-kind controls appear only once
    /// the background is no longer a stock gradient, keeping the section as
    /// small as the design's by default.
    private var backgroundSection: some View {
        InspectorSection(title: Text("Background")) {
            ChipScroll(topPadding: 2, bottomPadding: 6) {
                ForEach(GradientPreset.allCases) { preset in
                    GradientSwatch(
                        preset: preset, isSelected: selectedGradientPreset == preset, size: 28
                    ) {
                        settings.config.background = .gradient(preset)
                    }
                }
                CustomBackgroundSwatch(size: 28) {
                    settings.config.background = BackgroundKind.solid.makeDefault(
                        from: settings.config.background, imageStore: .container)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Background")
            .accessibilityIdentifier("inspector-background-swatches")

            if selectedGradientPreset == nil {
                InspectorRow(label: Text("Kind")) {
                    TokenSegmentedPicker(
                        options: [
                            (BackgroundKind.gradient, Text("Gradient")),
                            (.customGradient, Text("Custom")),
                            (.solid, Text("Solid")),
                            (.image, Text("Image")),
                            (.transparent, Text("Transparent")),
                        ],
                        selection: backgroundKindBinding
                    )
                    .accessibilityLabel("Kind")
                    .accessibilityIdentifier("background-kind-picker")
                }
                backgroundDetail
            }
        }
    }

    private var themeSection: some View {
        InspectorSection(title: Text("Theme")) {
            ThemeChipPicker(
                settings: settings, themes: themes,
                chipSize: CGSize(width: 52, height: 34), dotSize: 6,
                topPadding: 2, bottomPadding: 6
            )
            .accessibilityIdentifier("style-theme-picker")
        }
    }

    private var typographySection: some View {
        InspectorSection(title: Text("Typography")) {
            FontChipPicker(
                settings: settings, fontSize: 11.5, verticalPadding: 6, horizontalPadding: 13,
                topPadding: 2, bottomPadding: 6
            )
            .accessibilityIdentifier("style-font-picker")
            InspectorRow(label: Text("Ligatures")) {
                Toggle("Ligatures", isOn: $settings.config.fontLigatures)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(ligatureHelp)
                    .disabled(!fontHasLigatures)
                    .accessibilityIdentifier("ligatures-toggle")
            }
            InspectorRow(label: Text("Font size")) {
                Slider(value: $settings.config.fontSize, in: 10...20, step: 1)
                    .frame(width: 120)
                    .accessibilityLabel("Font size")
                    .accessibilityIdentifier("font-size-slider")
            }
        }
    }

    private var canvasSection: some View {
        InspectorSection(title: Text("Canvas")) {
            InspectorRow(label: Text("Padding")) {
                Slider(value: $settings.config.padding, in: 16...64, step: 4)
                    .frame(width: 120)
                    .accessibilityLabel("Padding")
                    .accessibilityIdentifier("padding-slider")
            }
            InspectorRow(label: Text("Corner radius")) {
                Slider(value: $settings.config.cornerRadius, in: 0...32, step: 2)
                    .frame(width: 120)
                    .accessibilityLabel("Corner radius")
                    .accessibilityIdentifier("corner-radius-slider")
            }
            InspectorRow(label: Text("Window chrome")) {
                Toggle("Window chrome", isOn: $settings.config.showChrome)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("window-chrome-toggle")
            }
            if settings.config.showChrome {
                InspectorRow(label: Text("Title")) {
                    TokenTextField(
                        prompt: Text(verbatim: "ContentView.swift"),
                        text: $settings.config.windowTitle
                    )
                    .accessibilityIdentifier("window-title-field")
                }
            }
            InspectorRow(label: Text("Drop shadow")) {
                Toggle("Drop shadow", isOn: $settings.config.showShadow)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("drop-shadow-toggle")
            }
            if settings.config.showShadow {
                InspectorRow(label: Text("Shadow depth")) {
                    Slider(value: $settings.config.shadowRadius, in: 0...40, step: 2)
                        .frame(width: 120)
                        .accessibilityLabel("Shadow depth")
                        .accessibilityIdentifier("shadow-radius-slider")
                }
            }
        }
    }

    /// The Output disclosure: destination segments (two rows, as in the kit),
    /// then resolution and format.
    @ViewBuilder private var outputControls: some View {
        VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xs) {
            InspectorRow(label: Text("Destination")) {
                TokenSegmentedPicker(
                    options: [
                        (DestinationTag.custom.rawValue, Text("Custom")),
                        (DestinationTag.preset("twitter").rawValue, Text(verbatim: "X")),
                        (DestinationTag.preset("linkedin").rawValue, Text(verbatim: "LinkedIn")),
                        (DestinationTag.preset("opengraph").rawValue, Text(verbatim: "OG")),
                    ],
                    selection: destinationBinding
                )
            }
            HStack {
                Spacer(minLength: 0)
                TokenSegmentedPicker(
                    options: [
                        (DestinationTag.preset("keynote").rawValue, Text(verbatim: "Keynote")),
                        (DestinationTag.preset("docs").rawValue, Text(verbatim: "Docs")),
                        (
                            DestinationTag.preset("transparent-slide").rawValue,
                            Text(verbatim: "Slide")
                        ),
                    ],
                    selection: destinationBinding
                )
            }
        }
        .help(destinationHelp)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Destination preset")
        .accessibilityIdentifier("editor-destination-preset-picker")

        InspectorRow(label: Text("Resolution")) {
            TokenSegmentedPicker(
                options: [
                    (1, Text(verbatim: "1×")), (2, Text(verbatim: "2×")), (3, Text(verbatim: "3×")),
                ],
                selection: $settings.exportScale
            )
            .accessibilityLabel("Resolution")
            .accessibilityIdentifier("inspector-resolution-picker")
        }
        InspectorRow(label: Text("Format")) {
            TokenSegmentedPicker(
                options: ExportFormat.allCases.map { ($0, Text(verbatim: $0.displayName)) },
                selection: $settings.exportFormat
            )
            .help(settings.exportFormat.summary)
            .accessibilityLabel("Format")
            .accessibilityIdentifier("inspector-format-picker")
        }
    }

    // MARK: - Bindings & helpers

    /// A stable string tag for the destination segments: "custom" or a preset id.
    private enum DestinationTag: Equatable {
        case custom
        case preset(String)

        var rawValue: String {
            switch self {
            case .custom: ""
            case .preset(let id): id
            }
        }
    }

    private var destinationBinding: Binding<String> {
        Binding(
            get: { settings.selectedPresetID ?? "" },
            set: { id in
                if let preset = ExportPreset.preset(withID: id) {
                    settings.selectPreset(preset)
                } else {
                    settings.clearPreset()
                }
            }
        )
    }

    private var destinationHelp: String {
        settings.selectedPreset?.summary
            ?? "Custom: your own size and style, with no destination preset applied."
    }

    private var selectedGradientPreset: GradientPreset? {
        if case .gradient(let preset) = settings.config.background { return preset }
        return nil
    }

    /// The active background kind; switching seeds a sensible default from the
    /// current style, mirroring the Settings pane.
    private var backgroundKindBinding: Binding<BackgroundKind> {
        Binding(
            get: { BackgroundKind(settings.config.background) },
            set: {
                settings.config.background = $0.makeDefault(
                    from: settings.config.background, imageStore: .container)
            }
        )
    }

    /// The controls for the active non-preset background kind.
    @ViewBuilder private var backgroundDetail: some View {
        switch settings.config.background {
        case .gradient:
            EmptyView()
        case .customGradient(let gradient):
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xs) {
                CustomGradientEditor(
                    gradient: Binding(
                        get: { gradient },
                        set: { settings.config.background = .customGradient($0) }))
            }
        case .solid(let color):
            InspectorRow(label: Text("Color")) {
                ColorPicker(
                    "Color",
                    selection: Binding(
                        get: { color }, set: { settings.config.background = .solid($0) }),
                    supportsOpacity: true
                )
                .labelsHidden()
                .accessibilityIdentifier("background-solid-color")
            }
        case .image(let image):
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xs) {
                ImageBackgroundEditor(
                    image: Binding(
                        get: { image }, set: { settings.config.background = .image($0) }),
                    imageStore: .container)
            }
        case .transparent:
            Text("Exports with a real transparent (alpha) background.")
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.tertiary)
        }
    }

    /// Whether the selected font ships programming ligatures, gating the toggle
    /// so it reads as inert for a font that has none (CS-052).
    private var fontHasLigatures: Bool {
        CodeFont.hasLigatures(settings.config.fontName)
    }

    private var ligatureHelp: String {
        fontHasLigatures
            ? "Render programming ligatures (->, =>, !=) for this font."
            : "The selected font has no ligatures; choose Fira Code or JetBrains Mono."
    }
}
