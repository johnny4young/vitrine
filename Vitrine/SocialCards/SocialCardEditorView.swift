import AppKit
import SwiftUI

/// The social-card composer (CS-041): a live 1200×630 preview beside an inspector
/// that edits the working ``SocialCardModel``, with copy / save / share export in a
/// glass toolbar. Everything is local and deterministic — the preview *is* the
/// exported image (`ImageRenderer` over ``SocialCardCanvas``), with no WebKit and no
/// network — so the card round-trips the same pixels on any Mac.
///
/// The card is the app-global working document (`AppSettings.socialCard`), so unlike
/// the multi-window code editor this surface edits the shared settings directly; its
/// changes persist immediately through the settings' own observer.
struct SocialCardEditorView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                previewStage
                SocialCardInspector(settings: settings)
                    .frame(width: 320)
            }
        }
        // Merge the toolbar into the title bar so the title sits in the traffic-light row
        // (the editor pattern, CS-037): extending into the top safe area pulls the glass
        // toolbar to the window edge, with the traffic lights floating over its leading 86 pt.
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 860, minHeight: 560)
        .background(VitrineTokens.Surface.window)
        .tint(VitrineTokens.Accent.system)
    }

    private var card: SocialCardModel { settings.socialCard }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: VitrineTokens.Spacing.xs) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(verbatim: "Social Card")
                    .font(.system(size: VitrineTokens.FontSize.headline, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.primary)
            }

            Spacer(minLength: 0)

            iconButton(
                "social-card-save-button", label: VitrineCommand.saveImage.accessibilityLabel,
                help: "Render and save the card as a file", systemImage: "square.and.arrow.down",
                shortcut: KeyboardShortcut("s", modifiers: .command), action: saveCard)
            iconButton(
                "social-card-share-button", label: VitrineCommand.shareImage.accessibilityLabel,
                help: "Share the rendered card", systemImage: "square.and.arrow.up",
                action: shareCard)

            copyCardCTA
        }
        .padding(.vertical, 10)
        .padding(.trailing, VitrineTokens.Spacing.md)
        // Clears the traffic lights, which overlay the leading edge of the band.
        .padding(.leading, 86)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VitrineTokens.Line.border)
                .frame(height: Brand.Stroke.hairline)
        }
        .accessibilityContainerIdentifier("social-card-toolbar")
        .accessibilityLabel("Toolbar")
    }

    /// The gradient "Copy card" capsule — the window's primary action. Disabled until
    /// the card has something to draw (a title or a non-empty excerpt), so it never
    /// copies a blank image (CS-041 `isRenderable`).
    private var copyCardCTA: some View {
        GradientCTAButton {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
            Text("Copy card")
        } action: {
            copyCard()
        }
        .help("Render and copy the card to the clipboard")
        .disabled(!card.isRenderable)
        // ⇧⌘C, matching the editor's image-copy command (plain ⌘C stays text copy).
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .accessibilityLabel(VitrineCommand.copyImage.accessibilityLabel)
        .accessibilityIdentifier("social-card-copy-button")
    }

    /// One bordered toolbar icon button, disabled until the card is renderable, with an
    /// optional local keyboard shortcut (the menu's image commands are gated to editor
    /// windows, so this window provides its own).
    @ViewBuilder
    private func iconButton(
        _ identifier: String, label: String, help: String, systemImage: String,
        shortcut: KeyboardShortcut? = nil, action: @escaping () -> Void
    ) -> some View {
        let button = GlassIconButton(systemImage: systemImage, action: action)
            .help(help)
            .disabled(!card.isRenderable)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
        if let shortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    // MARK: - Export

    private func copyCard() {
        ExportFeedback.presentCopy(
            SocialCardRenderer.copyToPasteboard(
                card, scale: exportScale, profile: settings.export.colorProfile))
    }

    private func saveCard() {
        ExportFeedback.presentSave(
            SocialCardRenderer.saveToFile(
                card, scale: exportScale, format: settings.export.format,
                profile: settings.export.colorProfile))
    }

    private func shareCard() {
        guard let view = NSApp.keyWindow?.contentView else { return }
        if !SocialCardRenderer.share(
            card, relativeTo: view, scale: exportScale, profile: settings.export.colorProfile)
        {
            ExportFeedback.presentShareFailure()
        }
    }

    /// The export scale: the user's chosen resolution multiplier, applied to the
    /// fixed 1200×630 card (so 2× yields a crisp 2400×1260).
    private var exportScale: CGFloat { CGFloat(settings.export.scale) }

    // MARK: - Preview

    /// The stage: the 1200×630 card floating in the neutral preview area, always
    /// scaled to fit with a soft shadow. An empty card shows a quiet prompt over the
    /// background rather than a blank rectangle.
    private var previewStage: some View {
        GeometryReader { proxy in
            let scale = fitScale(in: proxy.size)
            ZStack {
                SocialCardCanvas(model: card)
                    .fixedSize()
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 18)
                    .overlay {
                        if !card.isRenderable { emptyPrompt }
                    }
                    .scaleEffect(scale)
                    // `scaleEffect` does not shrink the layout footprint, so pin it to the
                    // scaled size — otherwise the full-size 1200×630 card stays full-width
                    // in layout and its centered overflow is clipped to one side, leaving
                    // the card off-center in the stage (the editor's fix). Kept on the card
                    // (with its empty-state overlay) so the overlay scales and stays put.
                    .frame(
                        width: SocialCardModel.defaultSize.width * scale,
                        height: SocialCardModel.defaultSize.height * scale
                    )
                    .animation(.easeInOut(duration: 0.2), value: scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .background(VitrineTokens.Surface.stage)
        .layoutPriority(2)
        .accessibilityIdentifier("social-card-preview-stage")
    }

    /// The scale that keeps the 1200×630 card fully visible with a 72 pt margin,
    /// never upscaling past its natural size.
    private func fitScale(in stage: CGSize) -> CGFloat {
        let size = SocialCardModel.defaultSize
        return min(1, (stage.width - 72) / size.width, (stage.height - 72) / size.height)
    }

    private var emptyPrompt: some View {
        // Sits over the card's own background gradient (not the neutral stage), so the
        // copy stays white for legibility on any preset; the rest is tokenized.
        Text("Add a title or a code excerpt to compose your card.")
            .font(.system(size: VitrineTokens.FontSize.largeTitle, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            .padding(VitrineTokens.Spacing.xxl)
    }
}

// MARK: - Inspector

/// The social-card inspector: a glass column of uppercase-labeled sections — Template,
/// Content, Code, Footer, Theme, Typography, Background — bound to the working card.
private struct SocialCardInspector: View {
    @Bindable var settings: AppSettings
    private let themes = CustomThemeStore.shared
    @State private var showTypography = false
    @State private var showBackground = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xl - 12) {
                templateSection
                contentSection
                if card.template.showsCode { codeSection }
                footerSection
                themeSection
                typographySection
                backgroundSection
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
        .accessibilityIdentifier("social-card-inspector")
    }

    private var card: SocialCardModel { settings.socialCard }

    // MARK: Sections

    private var templateSection: some View {
        section("Template") {
            TokenSegmentedPicker(
                options: SocialCardTemplate.allCases.map { ($0, Text(verbatim: $0.displayName)) },
                selection: $settings.socialCard.template,
                fillsWidth: true,
                optionIdentifiers: SocialCardTemplate.allCases.map {
                    "social-card-template-\($0.rawValue)"
                }
            )
            .accessibilityLabel("Template")
            .accessibilityIdentifier("social-card-template-picker")
            Text(verbatim: card.template.summary)
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.tertiary)
        }
    }

    private var contentSection: some View {
        section("Content") {
            cardField("Title", \.title, identifier: "social-card-title-field")
            cardField("Subtitle", \.subtitle, identifier: "social-card-subtitle-field")
        }
    }

    private var codeSection: some View {
        section("Code") {
            InspectorCodeField(
                text: $settings.socialCard.codeExcerpt, placeholder: "let value = 42", height: 96
            )
            .accessibilityIdentifier("social-card-excerpt-editor")
            row("Language") {
                Picker("Language", selection: $settings.socialCard.language) {
                    ForEach(Language.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Language")
                .accessibilityIdentifier("social-card-language-picker")
            }
        }
    }

    private var footerSection: some View {
        section("Footer") {
            cardField("Author", \.author, identifier: "social-card-author-field")
            cardField("Project", \.project, identifier: "social-card-project-field")
            row("Show logo") {
                Toggle("Show logo", isOn: $settings.socialCard.showLogo)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("social-card-logo-toggle")
            }
            brandKitRow
        }
    }

    /// A PRO affordance that fills the footer from the app-global Brand Kit (CS-092):
    /// the handle and project become the author/project lines and the logo is enabled.
    /// Gated through the shared `proGated` modifier, so it runs when PRO is unlocked
    /// and opens the paywall (with a "PRO" badge) when it is not.
    private var brandKitRow: some View {
        // A tinted accent pill so the affordance clearly reads as a tappable action
        // (not a static label). `proGated` runs it when PRO is unlocked and opens the
        // paywall — with its "PRO" badge — when it is not.
        HStack(spacing: VitrineTokens.Spacing.xs) {
            Image(systemName: "wand.and.stars")
            Text("Use Brand Kit")
            Spacer(minLength: 0)
        }
        .font(.system(size: VitrineTokens.FontSize.subhead, weight: .medium))
        .foregroundStyle(VitrineTokens.Accent.system)
        .padding(.horizontal, VitrineTokens.Spacing.sm)
        .padding(.vertical, VitrineTokens.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.md, style: .continuous)
                .fill(VitrineTokens.Accent.system.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.md, style: .continuous)
                .strokeBorder(
                    VitrineTokens.Accent.system.opacity(0.30), lineWidth: Brand.Stroke.hairline)
        )
        .contentShape(RoundedRectangle(cornerRadius: VitrineTokens.Radius.md, style: .continuous))
        .proGated(.brandKit) { applyBrandKit() }
        .help("Fill the footer from your Brand Kit")
        .accessibilityIdentifier("social-card-use-brand-kit")
    }

    /// Copies the brand kit's handle/project into the footer and turns the logo on.
    /// Empty kit fields are left untouched, so a partial kit never blanks the footer.
    private func applyBrandKit() {
        let kit = BrandKitStore.shared.brandKit
        if !kit.handle.isEmpty { settings.socialCard.author = kit.handle }
        if !kit.project.isEmpty { settings.socialCard.project = kit.project }
        settings.socialCard.showLogo = true
    }

    private var themeSection: some View {
        section("Theme") {
            SocialCardThemePicker(theme: $settings.socialCard.theme, themes: themes)
        }
    }

    private var typographySection: some View {
        InspectorDisclosure(
            label: Text("Typography"), identifier: "social-card-typography-disclosure",
            isExpanded: $showTypography
        ) {
            SocialCardFontPicker(fontName: $settings.socialCard.fontName)
            row("Font size") {
                Slider(
                    value: $settings.socialCard.fontSize,
                    in: SocialCardModel.fontSizeRange, step: 1
                )
                .frame(width: 120)
                .accessibilityLabel("Font size")
                .accessibilityIdentifier("social-card-font-size-slider")
            }
        }
    }

    private var backgroundSection: some View {
        InspectorDisclosure(
            label: Text("Background"), identifier: "social-card-background-disclosure",
            isExpanded: $showBackground
        ) {
            ChipScroll(topPadding: 2, bottomPadding: 6) {
                ForEach(GradientPreset.allCases) { preset in
                    GradientSwatch(preset: preset, isSelected: selectedGradient == preset, size: 28)
                    {
                        settings.socialCard.background = .gradient(preset)
                    }
                }
                CustomBackgroundSwatch(size: 28) {
                    settings.socialCard.background = BackgroundKind.solid.makeDefault(
                        from: card.background, imageStore: .container)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Background")
            .accessibilityIdentifier("social-card-background-swatches")

            // Once the background is no longer a stock gradient preset, expose the full
            // kind picker (custom gradient, solid, image, transparent) and its controls.
            if selectedGradient == nil {
                row("Kind") {
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
                    .accessibilityIdentifier("social-card-background-kind-picker")
                }
                backgroundDetail
            }
        }
    }

    /// The control for the active non-gradient-preset background, mirroring the editor
    /// inspector: a custom gradient editor, a color well, an image picker, or the
    /// transparent note.
    @ViewBuilder private var backgroundDetail: some View {
        switch card.background {
        case .gradient:
            EmptyView()
        case .customGradient(let gradient):
            CustomGradientEditor(
                gradient: Binding(
                    get: { gradient },
                    set: { settings.socialCard.background = .customGradient($0) }))
        case .solid(let color):
            row("Color") {
                ColorPicker(
                    "Color",
                    selection: Binding(
                        get: { color }, set: { settings.socialCard.background = .solid($0) }),
                    supportsOpacity: true
                )
                .labelsHidden()
                .accessibilityIdentifier("social-card-background-color")
            }
        case .image(let image):
            ImageBackgroundEditor(
                image: Binding(
                    get: { image }, set: { settings.socialCard.background = .image($0) }),
                imageStore: .container)
        case .transparent:
            Text("Exports with a real transparent (alpha) background.")
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.tertiary)
        }
    }

    /// The active background kind; switching seeds a sensible default from the current
    /// style, mirroring the editor inspector.
    private var backgroundKindBinding: Binding<BackgroundKind> {
        Binding(
            get: { BackgroundKind(card.background) },
            set: {
                settings.socialCard.background = $0.makeDefault(
                    from: card.background, imageStore: .container)
            })
    }

    private var selectedGradient: GradientPreset? {
        if case .gradient(let preset) = card.background { return preset }
        return nil
    }

    // MARK: Chrome helpers

    /// Local sugar over the shared `InspectorSection` so call sites keep passing a
    /// `LocalizedStringKey`; the chrome is the shared editor-kit component, so every
    /// inspector reads with one section metric.
    private func section<Content: View>(
        _ title: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        InspectorSection(title: Text(title), content: content)
    }

    /// Local sugar over the shared `InspectorRow`.
    private func row<Content: View>(
        _ label: LocalizedStringKey, @ViewBuilder control: () -> Content
    ) -> some View {
        InspectorRow(label: Text(label), content: control)
    }

    /// A binding from an optional text field of the card to a non-optional `String`,
    /// mapping an empty entry back to `nil` so a blank field never reserves layout
    /// space (matching the model's normalization).
    private func optional(_ keyPath: WritableKeyPath<SocialCardModel, String?>) -> Binding<String> {
        Binding(
            get: { settings.socialCard[keyPath: keyPath] ?? "" },
            set: { settings.socialCard[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    /// One optional-text inspector field, wired to its `keyPath` and given a stable
    /// accessibility id — the shared ``InspectorTextField`` with the card's binding.
    private func cardField(
        _ prompt: LocalizedStringKey, _ keyPath: WritableKeyPath<SocialCardModel, String?>,
        identifier: String
    ) -> some View {
        InspectorTextField(prompt: Text(prompt), text: optional(keyPath))
            .accessibilityIdentifier(identifier)
    }
}

// MARK: - Card inspector controls

/// The card's theme chip strip — the same chips the editor uses, bound to the card's
/// own theme rather than `settings.config` (which `ThemeChipPicker` is wired to).
private struct SocialCardThemePicker: View {
    @Binding var theme: Theme
    var themes: CustomThemeStore

    var body: some View {
        ChipScroll(topPadding: 2, bottomPadding: 6) {
            ForEach(ThemeChipColors.orderedBuiltIns) { chip(for: $0) }
            ForEach(themes.customThemes) { chip(for: $0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme")
        .accessibilityIdentifier("social-card-theme-picker")
    }

    private func chip(for candidate: Theme) -> some View {
        ThemeChip(
            theme: candidate, isSelected: theme.id == candidate.id,
            chipSize: CGSize(width: 52, height: 34), dotSize: 6
        ) {
            theme = themes.theme(withID: candidate.id)
        }
    }
}

/// The card's font pill strip, bound to the card's own font.
private struct SocialCardFontPicker: View {
    @Binding var fontName: String

    var body: some View {
        ChipScroll(topPadding: 2, bottomPadding: 6) {
            ForEach(CodeFont.all, id: \.self) { family in
                FontChip(
                    family: family, isSelected: fontName == family,
                    fontSize: 11.5, verticalPadding: 6, horizontalPadding: 13
                ) {
                    fontName = family
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Font")
        .accessibilityIdentifier("social-card-font-picker")
    }
}
