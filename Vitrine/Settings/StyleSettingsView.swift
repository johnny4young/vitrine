import AppKit
import SwiftUI

/// Style pane: theme, background, padding, font, chrome, shadow + live preview,
/// in the current design's sticky-header layout — the live preview and
/// the segmented sub-tabs (Appearance / Lines & header / Background) stay
/// pinned while the groups beneath scroll.
struct StyleSettingsView: View {
    @Bindable var settings: AppSettings
    var themes: CustomThemeStore

    /// The PRO brand kit + entitlement: observed so the live preview tracks
    /// Brand Kit placement changes while the dedicated Brand Kit pane owns the controls.
    @Bindable private var brandKit = BrandKitStore.shared
    private let entitlements = Entitlements.shared

    /// The rendered preview thumbnail, recomputed debounced off the `body` pass :
    /// rasterizing a full `ImageRenderer` canvas inside `body` re-ran the slowest path
    /// in the app on every color-picker frame. Now a `.task(id:)` coalesces rapid edits
    /// into one render after a short quiet window and stores the result here.
    @State private var previewImage: NSImage?

    /// The active sub-tab, remembered across openings (and seedable by the
    /// visual-regression tooling) through the app's defaults store.
    @AppStorage("settings.styleSubTab", store: AppDefaults.current)
    private var subTab: StyleSubTab = .appearance

    /// The Style pane's segmented sub-tabs.
    private enum StyleSubTab: String, CaseIterable {
        case appearance, linesAndHeader, background
    }

    var body: some View {
        ScrollView {
            LazyVStack(
                alignment: .leading, spacing: VitrineTokens.Spacing.md,
                pinnedViews: [.sectionHeaders]
            ) {
                Section {
                    VStack(alignment: .leading, spacing: VitrineTokens.Spacing.md) {
                        switch subTab {
                        case .appearance: appearanceGroups
                        case .linesAndHeader: linesAndHeaderGroups
                        case .background: backgroundGroup
                        }
                    }
                    .padding(.horizontal, 26)
                } header: {
                    stickyHeader
                }
            }
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("settings-style-pane")
        // Debounced live preview: `.task(id:)` cancels the prior render when any
        // preview input changes, so a color-picker drag coalesces to one render after a
        // short quiet window instead of rasterizing the canvas on every frame. Runs once
        // on appear for the initial thumbnail.
        .task(id: previewInputs) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            previewImage = renderCurrentPreview()
        }
    }

    /// The pinned header: live preview + sub-tab segments over the window
    /// fill, with a soft drop so scrolled content reads as sliding beneath.
    private var stickyHeader: some View {
        VStack(spacing: VitrineTokens.Spacing.sm) {
            preview
            TokenSegmentedPicker(
                options: [
                    (StyleSubTab.appearance, Text("Appearance")),
                    (.linesAndHeader, Text("Lines & header")),
                    (.background, Text("Background")),
                ],
                selection: $subTab,
                fillsWidth: true,
                optionIdentifiers: [
                    "style-subtab-appearance", "style-subtab-lines", "style-subtab-background",
                ]
            )
        }
        .padding(.top, 18)
        .padding(.horizontal, 26)
        .padding(.bottom, VitrineTokens.Spacing.sm)
        .background(
            Rectangle()
                .fill(VitrineTokens.Surface.window)
                .brandShadow(VitrineTokens.Chrome.stickyHeaderShadow)
        )
    }

    @ViewBuilder private var preview: some View {
        if let image = previewImage {
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Live preview")
                    .accessibilityIdentifier("settings-style-preview")
                // Free-placement: drag the brand mark over the preview. The handle maps
                // the drag to the image's letterboxed content rect, not the frame.
                if previewConfig.watermark?.placement == .free {
                    GeometryReader { geo in
                        FreeWatermarkDragHandle(
                            position: $brandKit.brandKit.freePosition,
                            contentRect: FreeWatermarkDragHandle.aspectFitRect(
                                imageSize: image.size, in: geo.size))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 150)
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
            .help("Live preview of the current style")
            .accessibilityElement(children: .contain)
        } else {
            previewPlaceholder
        }
    }

    // MARK: Appearance

    @ViewBuilder private var appearanceGroups: some View {
        TokenGroup(title: Text("Destination")) {
            TokenRow(
                label: Text("Destination"),
                caption: Text("Sizes and styles the image for a place to post it")
            ) {
                DestinationSegmentedPicker(settings: settings)
            }
        }

        TokenGroup(
            title: Text("Theme"),
            caption: Text(
                "The theme recolors the code's syntax. The other Style tabs shape the image around it — font, background, header, and brand."
            )
        ) {
            ThemeChipPicker(settings: settings, themes: themes, searchable: true)
                .accessibilityIdentifier("style-theme-picker")
        }

        TokenGroup(title: Text("Typography")) {
            FontChipPicker(settings: settings, searchable: true)
                .accessibilityIdentifier("style-font-picker")
            TokenRow(label: Text("Ligatures")) {
                Toggle("Ligatures", isOn: $settings.config.fontLigatures)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(ligatureHelp)
                    .disabled(!fontHasLigatures)
                    .accessibilityIdentifier("ligatures-toggle")
            }
            TokenRow(label: Text("Font size")) {
                Slider(value: $settings.config.fontSize, in: 10...20, step: 1)
                    .frame(width: 130)
                    .accessibilityLabel("Font size")
                    .accessibilityIdentifier("font-size-slider")
            }
        }

        TokenGroup(title: Text("Canvas")) {
            TokenRow(label: Text("Padding")) {
                Slider(value: $settings.config.padding, in: 16...64, step: 4)
                    .frame(width: 130)
                    .accessibilityLabel("Padding")
                    .accessibilityIdentifier("padding-slider")
            }
            TokenRow(label: Text("Window chrome")) {
                Toggle("Window chrome", isOn: $settings.config.showChrome)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("window-chrome-toggle")
            }
            TokenRow(label: Text("Drop shadow")) {
                Toggle("Drop shadow", isOn: $settings.config.showShadow)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("drop-shadow-toggle")
            }
        }
    }

    /// Whether the selected font ships programming ligatures, gating the toggle
    /// so it reads as inert for a font that has none.
    private var fontHasLigatures: Bool {
        CodeFont.hasLigatures(settings.config.fontName)
    }

    private var ligatureHelp: String {
        fontHasLigatures
            ? "Render programming ligatures (->, =>, !=) for this font."
            : "The selected font has no ligatures; choose Fira Code or JetBrains Mono."
    }

    // MARK: Lines & header

    @ViewBuilder private var linesAndHeaderGroups: some View {
        TokenGroup(title: Text("Lines")) {
            TokenRow(label: Text("Line numbers")) {
                Toggle("Line numbers", isOn: $settings.config.showLineNumbers)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("line-numbers-toggle")
            }
            TokenRow(
                label: Text("Wrap long lines"),
                caption: Text("Soft-wrap past a column width instead of widening the card")
            ) {
                Toggle("Wrap long lines", isOn: settings.wrapsLongLines)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("wrap-lines-toggle")
            }
            if settings.config.wrapsLongLines {
                TokenRow(label: Text("Wrap width")) {
                    HStack(spacing: 8) {
                        Slider(
                            value: settings.wrapColumnsValue,
                            in: SettingsDefaults.wrapColumnsSliderRange, step: 4
                        )
                        .frame(width: 110)
                        .accessibilityLabel("Wrap width")
                        .accessibilityIdentifier("wrap-columns-slider")
                        Text(
                            verbatim:
                                "\(settings.config.wrapColumns ?? SettingsDefaults.wrapColumns)"
                        )
                        .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                        .frame(width: 26, alignment: .trailing)
                    }
                }
            }
            TokenRow(
                label: Text("Highlight lines"),
                caption: Text("Highlight specific lines or ranges")
            ) {
                HighlightedLinesField(settings: settings)
            }
        }

        TokenGroup(title: Text("Header")) {
            MetadataFields(settings: settings)
        }
    }

    // MARK: Background

    @ViewBuilder private var backgroundGroup: some View {
        TokenGroup(title: Text("Gradient preset")) {
            HStack(spacing: VitrineTokens.Spacing.xs) {
                ForEach(GradientPreset.allCases) { preset in
                    GradientSwatch(
                        preset: preset, isSelected: selectedGradientPreset == preset
                    ) {
                        settings.config.background = .gradient(preset)
                    }
                }
                CustomBackgroundSwatch {
                    settings.config.background = BackgroundKind.solid.makeDefault(
                        from: settings.config.background, imageStore: .container)
                }
            }
            .padding(.vertical, VitrineTokens.Spacing.sm)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Gradient preset")
            .accessibilityIdentifier("background-gradient-preset")

            TokenRow(
                label: Text("Kind"),
                caption: Text("Gradient preset, solid color, or image")
            ) {
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

    /// The controls for the active background kind, hosted as tile rows.
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
            .padding(.vertical, 9)
        case .solid(let color):
            TokenRow(label: Text("Color")) {
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
            .padding(.vertical, 9)
        case .transparent:
            TokenRow(caption: Text("Exports with a real transparent (alpha) background.")) {
                EmptyView()
            }
        }
    }

    /// The active background kind; switching seeds a sensible default from the
    /// current style, mirroring `BackgroundEditor`'s behavior.
    private var backgroundKindBinding: Binding<BackgroundKind> {
        Binding(
            get: { BackgroundKind(settings.config.background) },
            set: {
                settings.config.background = $0.makeDefault(
                    from: settings.config.background, imageStore: .container)
            }
        )
    }

    private var selectedGradientPreset: GradientPreset? {
        if case .gradient(let preset) = settings.config.background { return preset }
        return nil
    }

    /// Config used for the preview — falls back to a sample snippet when the editor
    /// has no code yet, so the preview is always meaningful.
    private var previewConfig: SnapshotConfig {
        var config = settings.config
        if config.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.code = "func greet(_ name: String) {\n    print(\"Hello, \\(name)!\")\n}"
        }
        // The Style preview is a *style* thumbnail, so drop the editor's free-form
        // annotations (arrows / text callouts / blur). They are content drawn on a
        // specific capture in the editor — not a Style-pane control — and a leftover
        // blur or "Note" callout only muddies the preview of the theme/background/font.
        // Header text, highlighted lines, and line numbers stay: those *are* set in
        // this pane, so the preview should reflect them.
        config.annotations = []
        // Show the brand watermark live while configuring the kit.
        config.watermark = brandKit.resolvedWatermark(isPro: entitlements.isPro)
        return config
    }

    /// Renders the preview thumbnail. Called only from the debounced `.task(id:)`, never
    /// inside `body`. Reflects a fixed-size preset's exact framing (e.g. Keynote
    /// 1920×1080) — the renderer lays out at the preset's logical size, but previews use
    /// a fractional thumbnail scale capped below; real Copy/Save/Share paths keep
    /// `effectiveExportScale` and exact output dimensions.
    private func renderCurrentPreview() -> NSImage? {
        ExportManager.renderNSImage(
            previewConfig, scale: previewRenderScale, fixedSize: settings.effectiveFixedSize,
            profile: settings.export.colorProfile)
    }

    /// The inputs the preview render depends on, so `.task(id:)` re-renders exactly when
    /// one changes (and coalesces a rapid drag into a single trailing render).
    private var previewInputs: PreviewInputs {
        PreviewInputs(
            config: previewConfig, fixedSize: settings.effectiveFixedSize,
            profile: settings.export.colorProfile)
    }

    private struct PreviewInputs: Equatable {
        var config: SnapshotConfig
        var fixedSize: CGSize?
        var profile: ColorProfile
    }

    private var previewRenderScale: CGFloat {
        // The on-screen preview is a small thumbnail (≤150 pt), so scale 1 is ample and
        // halves the per-render pixel work versus the old 2× path. Fixed-size presets
        // still cap the scale below 1 so a 1920×1080 preset doesn't rasterize full size.
        guard let fixedSize = settings.effectiveFixedSize else { return 1 }
        let longestSide = max(fixedSize.width, fixedSize.height)
        guard longestSide > 0 else { return 1 }
        return max(0.1, min(1, Self.maximumPreviewPixels / longestSide))
    }

    /// Largest raster side for the Settings thumbnail. The on-screen preview is capped
    /// at 300 pt tall, so rendering more pixels only burns main-thread time.
    private static let maximumPreviewPixels: CGFloat = 600

    /// Shown when a render is not available yet (e.g. a font is still loading or
    /// the renderer returns nil) so the Preview section degrades to a labeled
    /// placeholder instead of an empty group.
    private var previewPlaceholder: some View {
        VStack(spacing: Brand.Spacing.xs) {
            BrandMark(size: 28)
            Text("Preview unavailable")
                .font(.subheadline)
                .foregroundStyle(Brand.Palette.textSecondary.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Brand.Spacing.lg)
        .accessibilityElement(children: .combine)
        // A distinct identifier and explicit label so tests and VoiceOver can
        // tell this degraded fallback apart from the real rendered preview
        // (which keeps "settings-style-preview").
        .accessibilityLabel("Preview unavailable")
        .accessibilityIdentifier("settings-style-preview-placeholder")
    }
}
