import AppKit
import SwiftUI

/// Style pane: theme, background, padding, font, chrome, shadow + live preview
/// (CS-006/010), in the redesign's sticky-header layout — the live preview and
/// the segmented sub-tabs (Appearance / Lines & header / Background) stay
/// pinned while the groups beneath scroll.
struct StyleSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var themes: CustomThemeStore

    /// The PRO brand kit + entitlement (CS-092): observed so the Brand Kit sub-tab's
    /// controls and the live preview track changes, and so the locked/unlocked split
    /// re-renders the instant PRO unlocks.
    @ObservedObject private var brandKit = BrandKitStore.shared
    @ObservedObject private var entitlements = Entitlements.shared

    /// The active sub-tab, remembered across openings (and seedable by the
    /// design-audit tooling) through the app's defaults store.
    @AppStorage("settings.styleSubTab", store: AppDefaults.current)
    private var subTab: StyleSubTab = .appearance

    /// The Style pane's segmented sub-tabs.
    private enum StyleSubTab: String, CaseIterable {
        case appearance, linesAndHeader, background, brandKit
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
                        case .brandKit:
                            BrandKitSettingsSection(brandKit: brandKit, entitlements: entitlements)
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
                    (.brandKit, Text("Brand Kit")),
                ],
                selection: $subTab,
                fillsWidth: true,
                optionIdentifiers: [
                    "style-subtab-appearance", "style-subtab-lines", "style-subtab-background",
                    "style-subtab-brandkit",
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
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 150)
                .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
                .help("Live preview of the current style")
                .accessibilityLabel("Live preview")
                .accessibilityIdentifier("settings-style-preview")
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

        TokenGroup(title: Text("Theme")) {
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
    /// so it reads as inert for a font that has none (CS-052).
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
        // Show the brand watermark live while configuring the kit (CS-092).
        config.watermark = brandKit.resolvedWatermark(isPro: entitlements.isPro)
        return config
    }

    private var previewImage: NSImage? {
        // Reflect a fixed-size preset's exact framing (e.g. Keynote 1920×1080) in the
        // live preview without rasterizing a full export canvas on every Settings change.
        // The renderer still lays out at the preset's logical size, but fixed-size
        // previews use a fractional thumbnail scale capped below; real Copy/Save/Share
        // paths keep `effectiveExportScale` and exact output dimensions (CS-020).
        return ExportManager.renderNSImage(
            previewConfig, scale: previewRenderScale, fixedSize: settings.effectiveFixedSize,
            profile: settings.colorProfile)
    }

    private var previewRenderScale: CGFloat {
        guard let fixedSize = settings.effectiveFixedSize else { return 2 }
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
