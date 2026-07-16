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

    /// Whether the stage draws the safe-area guide (feature #20). Same key/store as
    /// `EditorView.showsSafeAreaGuides`, so the toggle here and the stage overlay stay
    /// in sync through the shared defaults without any plumbing.
    @AppStorage("editorShowsSafeAreaGuides", store: AppDefaults.current)
    private var showsSafeAreaGuides = false
    var themes: CustomThemeStore

    /// Disclosure state for the advanced sections. All start collapsed so the
    /// inspector opens compact; the primary style cluster above them is always
    /// visible. State is per-window and intentionally not persisted — it is view
    /// chrome, not a user preference.
    @State private var showLines = false
    @State private var showHeader = false
    @State private var showOutput = false

    /// Presents the PRO paywall when the user reaches for a gated image frame (browser).
    @State private var showingFramePaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xl - 12) {
                scopeNote
                backgroundSection
                // A beautified image swaps the code-only style controls (theme, fonts)
                // for the frame picker; everything else (background, canvas, header,
                // output) applies to both.
                if settings.config.usesImageContent {
                    frameSection
                } else {
                    themeSection
                    typographySection
                }
                canvasSection

                VStack(alignment: .leading, spacing: 0) {
                    // The line gutter / highlight / redact controls only make sense for
                    // code, so they're hidden when a beautified image is the content.
                    if !settings.config.usesImageContent {
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
                                    .help(
                                        "Soft-wrap past a column width instead of widening the card"
                                    )
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
                                    "Focus highlighted",
                                    isOn: $settings.config.focusHighlightedLines
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
                            InspectorRow(label: Text("Redact secrets")) {
                                if settings.config.redactedLineRanges.isEmpty {
                                    Button("Scan") {
                                        // Scan `sidecarText`, not `code`: for a terminal capture
                                        // the canvas renders the ANSI-resolved screen, so the raw
                                        // bytes' line numbers would map to the wrong rows (and
                                        // could leave a secret visible). For other languages
                                        // `sidecarText == code`.
                                        let lines = SecretScanner.secretLines(
                                            in: settings.config.sidecarText)
                                        settings.config.redactedLineRanges =
                                            LineHighlight.normalize(
                                                lines.map { $0...$0 })
                                    }
                                    .help(
                                        "Blur lines that look like API keys, tokens, or passwords."
                                    )
                                    .disabled(settings.config.code.isEmpty)
                                    .accessibilityIdentifier("redact-secrets-button")
                                } else {
                                    Button("Clear") { settings.config.redactedLineRanges = [] }
                                        .accessibilityIdentifier("clear-redactions-button")
                                }
                            }
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
        .sheet(isPresented: $showingFramePaywall) {
            PaywallSheet(feature: .advancedFrames)
        }
    }

    // MARK: - Sections

    /// Clarifies the scope the audit flagged as confusing. The editor binds a *per-window*
    /// `EditorSession.settings` (see `EditorWindowController.makeWindow`), so these controls
    /// style only the capture in this window. Settings ▸ Style edits `AppSettings.shared`,
    /// the global default that new captures start from (`QuickCapture` copies it into the
    /// primary window). Without this, an inspector tweak reads as "the default", or a
    /// Settings change reads as "should have changed my open image".
    private var scopeNote: some View {
        Text("These style this capture. New captures start from the default in Settings ▸ Style.")
            .font(.system(size: VitrineTokens.FontSize.caption))
            .foregroundStyle(VitrineTokens.Text.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("inspector-scope-note")
    }

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

    /// The frame for a beautified image — none, a macOS window, a browser window, or a
    /// device mockup (MacBook / iPhone). Shown only when the content is an image. Everything
    /// past the macOS window is PRO: selecting a locked frame opens the paywall instead of
    /// applying (the free frames stay one tap away). The window title doubles as the
    /// window/browser-address text.
    private var frameSection: some View {
        InspectorSection(title: Text("Frame")) {
            InspectorRow(label: Text("Style")) {
                TokenSegmentedPicker(
                    options: [
                        (ImageFrame.none, Text("None")),
                        (ImageFrame.macOSWindow, Text("Window")),
                        (ImageFrame.browser, Text("Browser")),
                        (ImageFrame.macBook, Text("MacBook")),
                        (ImageFrame.iPhone, Text("iPhone")),
                    ],
                    selection: Binding(
                        get: { settings.config.imageFrame },
                        set: { newFrame in
                            if newFrame.isPro, !Entitlements.shared.isUnlocked(.advancedFrames) {
                                showingFramePaywall = true
                            } else {
                                settings.config.imageFrame = newFrame
                            }
                        }
                    )
                )
                .accessibilityLabel("Frame style")
                .accessibilityIdentifier("image-frame-picker")
            }
            if settings.config.imageFrame != .none {
                InspectorRow(label: Text("Appearance")) {
                    TokenSegmentedPicker(
                        options: [
                            (FrameAppearance.auto, Text("Auto")),
                            (FrameAppearance.light, Text("Light")),
                            (FrameAppearance.dark, Text("Dark")),
                        ],
                        selection: $settings.config.imageFrameAppearance
                    )
                    .accessibilityLabel("Frame appearance")
                    .accessibilityIdentifier("image-frame-appearance-picker")
                }
            }
            // The title/address applies only to the window and browser chrome.
            if settings.config.imageFrame == .macOSWindow || settings.config.imageFrame == .browser
            {
                InspectorRow(label: Text("Title")) {
                    TokenTextField(
                        prompt: Text(verbatim: "vitrineframe.app"),
                        text: $settings.config.windowTitle
                    )
                    .accessibilityIdentifier("image-frame-title-field")
                }
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
                valueSlider(
                    "Font size", $settings.config.fontSize, in: 10...20, step: 1,
                    identifier: "font-size-slider")
            }
        }
    }

    /// A slider with a trailing numeric readout, so the user can see (and target) the
    /// current value instead of guessing from the knob position (audit UX). The value is
    /// hidden from VoiceOver because the slider already announces it.
    @ViewBuilder
    private func valueSlider(
        _ label: LocalizedStringKey, _ value: Binding<Double>, in range: ClosedRange<Double>,
        step: Double, identifier: String
    ) -> some View {
        HStack(spacing: 8) {
            Slider(value: value, in: range, step: step)
                .frame(width: 92)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
            Text(verbatim: "\(Int(value.wrappedValue.rounded()))")
                .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .frame(width: 22, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var canvasSection: some View {
        InspectorSection(title: Text("Canvas")) {
            InspectorRow(label: Text("Padding")) {
                valueSlider(
                    "Padding", $settings.config.padding, in: 16...64, step: 4,
                    identifier: "padding-slider")
            }
            InspectorRow(label: Text("Corner radius")) {
                valueSlider(
                    "Corner radius", $settings.config.cornerRadius, in: 0...32, step: 2,
                    identifier: "corner-radius-slider")
            }
            // The code card's macOS chrome. For a beautified image the Frame section
            // owns the window/browser chrome, so these rows are hidden there.
            if !settings.config.usesImageContent {
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
            }
            InspectorRow(label: Text("Drop shadow")) {
                Toggle("Drop shadow", isOn: $settings.config.showShadow)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("drop-shadow-toggle")
            }
            if settings.config.showShadow {
                InspectorRow(label: Text("Shadow depth")) {
                    valueSlider(
                        "Shadow depth", $settings.config.shadowRadius, in: 0...40, step: 2,
                        identifier: "shadow-radius-slider")
                }
            }
        }
    }

    /// The Output disclosure: destination segments (two rows, as in the kit),
    /// then resolution and format.
    @ViewBuilder private var outputControls: some View {
        VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xs) {
            InspectorRow(label: Text("Destination")) {
                // Row 1: Custom + the first three chips. Labels come from the shared
                // `DestinationChips` source so the editor and Settings never drift.
                TokenSegmentedPicker(
                    options: [(DestinationTag.custom.rawValue, Text("Custom"))]
                        + DestinationChips.all.prefix(3).map {
                            (DestinationTag.preset($0.id).rawValue, Text(verbatim: $0.label))
                        },
                    selection: destinationBinding
                )
            }
            HStack {
                Spacer(minLength: 0)
                // Row 2: the remaining chips, including Transparent Slide (the editor's
                // extra segment, absent from the six-wide Settings row by design).
                TokenSegmentedPicker(
                    options: DestinationChips.all.dropFirst(3).map {
                        (DestinationTag.preset($0.id).rawValue, Text(verbatim: $0.label))
                    },
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
                selection: $settings.export.scale
            )
            .accessibilityLabel("Resolution")
            .accessibilityIdentifier("inspector-resolution-picker")
        }
        InspectorRow(label: Text("Format")) {
            TokenSegmentedPicker(
                options: ExportFormat.allCases.map { ($0, Text(verbatim: $0.displayName)) },
                selection: $settings.export.format,
                optionIdentifiers: ExportFormat.allCases.map {
                    "inspector-format-\($0.rawValue)"
                }
            )
            .help(settings.export.format.summary)
            .accessibilityLabel("Format")
            .accessibilityIdentifier("inspector-format-picker")
        }
        InspectorRow(label: Text("Guides")) {
            Toggle("Safe-area guides", isOn: $showsSafeAreaGuides)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(
                    "Show the margin platforms may crop or cover, plus the live line and column count"
                )
                .accessibilityLabel("Safe-area guides")
                .accessibilityIdentifier("inspector-safe-area-toggle")
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
                        get: { color.color },
                        set: { settings.config.background = .solid(RGBAColor($0)) }),
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
