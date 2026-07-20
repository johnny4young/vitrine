import AppKit
import SwiftUI

private enum EditorToolbarDensity: Equatable {
    case full
    case condensed
    case compact

    var annotationDensity: AnnotationToolbarDensity {
        switch self {
        case .full: .full
        case .condensed: .condensed
        case .compact: .compact
        }
    }

    var usesCompactCopyButton: Bool { self != .full }
    var collapsesSecondaryActions: Bool { self == .compact }
    var spacing: CGFloat { self == .compact ? 10 : 14 }
}

/// The editor's glass toolbar and the export/copy actions behind it.
extension EditorView {
    // MARK: - Toolbar (design system: glass band merged into the title bar)

    /// The glass toolbar: brand mark + title, the language picker, then the
    /// secondary export actions as bordered icon buttons and the gradient
    /// "Copy image" CTA. Each action mirrors its File-menu command,
    /// sharing the command's VoiceOver label and keyboard shortcut.
    var editorToolbar: some View {
        // `settings` arrives via @Environment (an @Observable), which has no projected
        // value; this local @Bindable provides the `$settings.config.language` binding the
        // language picker needs.
        @Bindable var settings = settings
        @ViewBuilder func contents(_ density: EditorToolbarDensity) -> some View {
            HStack(spacing: density.spacing) {
                // Just the app mark — the "Vitrine Editor" wordmark was redundant next to
                // the window and only crowded the toolbar.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .accessibilityLabel("Vitrine Editor")

                Picker("Language", selection: $settings.config.language) {
                    ForEach(settings.orderedLanguages) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("The language used to syntax-highlight the code.")
                .accessibilityLabel("Language")
                .accessibilityIdentifier("language-picker")
                // Picking the Diff language is an unambiguous "I want diff rendering", so
                // turn the +/− bands (and the line gutter they read best with) on
                // automatically — the feature was previously undiscoverable behind an
                // inspector toggle. The toggle stays as a manual override.
                .onChange(of: settings.config.language) { _, newValue in
                    if newValue == .diff {
                        settings.config.diffDecorations = true
                        settings.config.showLineNumbers = true
                    }
                }

                Spacer(minLength: 8)

                // The annotation tool palette lives in the title bar, so marks
                // are drawn with the cursor like a dedicated screenshot tool. Picking a
                // draw tool deselects any mark so its options show the new-draw style.
                AnnotationToolbar(
                    activeTool: $activeTool,
                    color: annotationStyleColor,
                    thickness: annotationStyleThickness,
                    stickerGlyph: $newStickerGlyph,
                    showsColor: annotationStyleUsesColor,
                    showsThickness: annotationStyleUsesThickness,
                    canUndo: annotationHistory.canUndo,
                    canRedo: annotationHistory.canRedo,
                    shortcutsActive: annotationContextActive,
                    onUndo: undoAnnotations,
                    onRedo: redoAnnotations,
                    hasSelection: selectedAnnotationID != nil,
                    onDuplicate: duplicateSelection,
                    canBringToFront: canBringSelectionToFront,
                    canSendToBack: canSendSelectionToBack,
                    onBringToFront: bringSelectionToFront,
                    onSendToBack: sendSelectionToBack,
                    density: density.annotationDensity
                )
                .onChange(of: activeTool) { _, newTool in
                    if newTool != .select { selectedAnnotationID = nil }
                }

                Spacer(minLength: 8)

                if density.collapsesSecondaryActions {
                    copyOptionsMenu
                    savePresetButton
                    editorActionsMenu
                } else {
                    copyOptionsMenu
                    iconButton(
                        .saveImage, "save-button", help: "Render and save the image as a file",
                        systemImage: "square.and.arrow.down",
                        action: saveImage)
                    iconButton(
                        .shareImage, "share-button", help: "Share the rendered image",
                        systemImage: "square.and.arrow.up", action: share)
                    pinSnapshotButton
                    multiSizeExportButton
                    carouselExportButton
                    savePresetButton
                    makeDefaultButton
                }

                copyImageCTA(compact: density.usesCompactCopyButton)
            }
        }

        return ViewThatFits(in: .horizontal) {
            contents(.full)
            contents(.condensed)
            contents(.compact)
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
        .accessibilityContainerIdentifier("editor-toolbar")
        .accessibilityLabel("Toolbar")
    }

    /// The gradient "Copy image" capsule — the window's primary action. Bound
    /// to the Copy Image command's shortcut so the menu and CTA stay in lockstep.
    @ViewBuilder func copyImageCTA(compact: Bool) -> some View {
        let button = GradientCTAButton {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
            if !compact {
                Text("Copy image")
            }
        } action: {
            copyImage()
        }
        .help("Render and copy the image to the clipboard")
        .disabled(!settings.config.hasRenderableContent)
        .accessibilityLabel(VitrineCommand.copyImage.accessibilityLabel)
        .accessibilityIdentifier("copy-button")

        if let shortcut = VitrineCommand.copyImage.swiftUIShortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    /// Compact-window access to the secondary actions that do not need to remain
    /// individually visible. The primary copy action and the annotation controls stay
    /// directly reachable while this menu prevents title-bar clipping.
    var editorActionsMenu: some View {
        Menu {
            Button(action: saveImage) {
                Label(VitrineCommand.saveImage.title, systemImage: "square.and.arrow.down")
            }
            .disabled(!settings.config.hasRenderableContent)
            .accessibilityIdentifier("save-button")

            Button(action: share) {
                Label(VitrineCommand.shareImage.title, systemImage: "square.and.arrow.up")
            }
            .disabled(!settings.config.hasRenderableContent)
            .accessibilityIdentifier("share-button")

            Divider()

            Button(action: pinSnapshot) {
                Label("Pin snapshot", systemImage: "pin")
            }
            .disabled(!settings.config.hasRenderableContent)
            .accessibilityIdentifier("pin-snapshot-button")

            Button {
                multiSizeSheet = entitlements.isUnlocked(.multiSizeExport) ? .export : .paywall
            } label: {
                Label("Export sizes", systemImage: "square.grid.2x2")
            }
            .disabled(!settings.config.hasRenderableContent)
            .accessibilityIdentifier("export-sizes-button")

            Button {
                carouselSheet = entitlements.isUnlocked(.carouselExport) ? .export : .paywall
            } label: {
                Label("Export carousel", systemImage: "rectangle.stack")
            }
            .disabled(!settings.config.hasRenderableContent || settings.config.usesImageContent)
            .accessibilityIdentifier("export-carousel-button")

            Divider()

            Button(action: session.makeDefault) {
                Label(
                    VitrineCommand.makeDefault.title,
                    systemImage: VitrineCommand.makeDefault.systemImageName)
            }
            .accessibilityIdentifier("make-default-button")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VitrineTokens.Text.secondary)
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More editor actions")
        .accessibilityLabel("More editor actions")
        .accessibilityIdentifier("editor-actions-menu")
        .sheet(item: $multiSizeSheet) { sheet in
            switch sheet {
            case .export:
                MultiSizeExportView(
                    baseConfig: settings.exportConfig, format: settings.export.format,
                    profile: settings.export.colorProfile, textSidecar: settings.export.textSidecar)
            case .paywall:
                PaywallSheet(feature: .multiSizeExport)
            }
        }
        .sheet(item: $carouselSheet) { sheet in
            switch sheet {
            case .export:
                CarouselExportView(
                    baseConfig: settings.exportConfig,
                    profile: settings.export.colorProfile)
            case .paywall:
                PaywallSheet(feature: .carouselExport)
            }
        }
    }

    /// Renders and copies the image, then — by default — closes the editor window so
    /// it gets out of the way once its job is done. Users who copy more than
    /// once can keep it open from Settings.
    func copyImage() {
        // Surface the outcome so the toolbar's primary CTA isn't silent on success or a
        // render/encode failure — mirroring the menu command and the quick-capture HUD.
        // The HUD shows near the menu bar regardless of `closeAfterCopy`.
        let copied = ExportManager.copyToPasteboard(
            settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
            fixedSize: settings.effectiveFixedSize, profile: settings.export.colorProfile,
            richText: settings.export.richClipboard, plainText: settings.export.textSidecar)
        ExportFeedback.presentCopy(copied)
        // `closeAfterCopy` is an app-global behavior preference, so it is read from the
        // shared settings (what the Settings toggle edits) rather than this window's
        // per-session copy. Close *this* window — captured via `WindowAccessor`, so it
        // never depends on `keyWindow` being right — deferred past the button's action,
        // and `close()` (not `performClose`) so it is unconditional.
        guard AppSettings.shared.export.closeAfterCopy else { return }
        let target = editorWindow ?? NSApp.keyWindow
        DispatchQueue.main.async { target?.close() }
    }

    /// Renders and saves the image, confirming the outcome through the shared HUD so the
    /// toolbar Save button gives the same feedback as the File-menu command.
    /// A cancelled save panel is silent.
    func saveImage() {
        ExportFeedback.presentSave(
            ExportManager.saveToFile(
                settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
                format: settings.export.format, fixedSize: settings.effectiveFixedSize,
                profile: settings.export.colorProfile))
    }

    /// The explicit alternative copy targets behind the rich-text icon:
    /// "Copy Highlighted Code" (syntax colors and font as RTF/HTML),
    /// "Copy as Markdown" (self-contained image plus source), and "Copy as Data
    /// URI" (`data:image/png;base64,…`). A menu so the
    /// one-click CTA stays the primary action while the developer-grade
    /// formats stay clearly labeled, one click away.
    var copyOptionsMenu: some View {
        Menu {
            if !settings.config.usesImageContent {
                Button {
                    copyHighlightedCode()
                } label: {
                    Label(
                        VitrineCommand.copyHighlightedCode.title,
                        systemImage: VitrineCommand.copyHighlightedCode.systemImageName)
                }
                .accessibilityIdentifier("copy-highlighted-code-button")

                Button {
                    copyMarkdown()
                } label: {
                    Label(
                        VitrineCommand.copyMarkdown.title,
                        systemImage: VitrineCommand.copyMarkdown.systemImageName)
                }
                .accessibilityIdentifier("copy-markdown-button")

                // A reproducible link: the whole styled snapshot as a
                // `vitrine://open` URL a teammate can open to get your exact image.
                Button {
                    copyShareLink()
                } label: {
                    Label("Copy share link", systemImage: "link")
                }
                .accessibilityIdentifier("copy-share-link-button")
            }

            Button {
                copyDataURI()
            } label: {
                Label(
                    VitrineCommand.copyDataURI.title,
                    systemImage: VitrineCommand.copyDataURI.systemImageName)
            }
            .accessibilityIdentifier("copy-data-uri-button")
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VitrineTokens.Text.secondary)
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Copy the code or image in alternate formats")
        .accessibilityLabel("More copy options")
        .accessibilityIdentifier("copy-options-menu")
        .disabled(!settings.config.hasRenderableContent)
    }

    /// The PRO multi-size export entry: when unlocked it opens the size
    /// picker; when locked it shows a discreet "PRO" badge and opens the paywall
    /// instead. Both sheets are anchored here; disabled with the rest of the toolbar
    /// when there is no code to render.
    var multiSizeExportButton: some View {
        GlassIconButton(systemImage: "square.grid.2x2") {
            multiSizeSheet = entitlements.isUnlocked(.multiSizeExport) ? .export : .paywall
        }
        .overlay(alignment: .topTrailing) {
            if !entitlements.isUnlocked(.multiSizeExport) { ProBadge().accessibilityHidden(true) }
        }
        .help("Export this snapshot to several platform sizes at once")
        .disabled(!settings.config.hasRenderableContent)
        .accessibilityLabel(Text("Export sizes"))
        .accessibilityIdentifier("export-sizes-button")
        .sheet(item: $multiSizeSheet) { sheet in
            switch sheet {
            case .export:
                MultiSizeExportView(
                    baseConfig: settings.exportConfig, format: settings.export.format,
                    profile: settings.export.colorProfile, textSidecar: settings.export.textSidecar)
            case .paywall:
                PaywallSheet(feature: .multiSizeExport)
            }
        }
    }

    /// The carousel export entry: split a long snippet into numbered
    /// 4:5 slides for a LinkedIn/Instagram carousel. Same PRO gate as multi-size —
    /// it is the same batch-export family.
    var carouselExportButton: some View {
        GlassIconButton(systemImage: "rectangle.stack") {
            carouselSheet = entitlements.isUnlocked(.carouselExport) ? .export : .paywall
        }
        .overlay(alignment: .topTrailing) {
            if !entitlements.isUnlocked(.carouselExport) { ProBadge().accessibilityHidden(true) }
        }
        .help("Split the snippet into numbered carousel slides (4:5)")
        .disabled(
            !settings.config.hasRenderableContent || settings.config.usesImageContent
        )
        .accessibilityLabel(Text("Export carousel"))
        .accessibilityIdentifier("export-carousel-button")
        .sheet(item: $carouselSheet) { sheet in
            switch sheet {
            case .export:
                CarouselExportView(
                    baseConfig: settings.exportConfig,
                    profile: settings.export.colorProfile)
            case .paywall:
                PaywallSheet(feature: .carouselExport)
            }
        }
    }

    /// The star: applies a saved style preset or saves the current style as a
    /// new one. Carries the legacy picker identifier so the UI tests keep
    /// addressing one stable element for style presets in the editor.
    var savePresetButton: some View {
        Menu {
            Button {
                settings.applySurpriseStyle()
            } label: {
                Label("Surprise Me", systemImage: "dice")
            }
            .accessibilityHint("Apply the next curated style without changing your code")
            .accessibilityIdentifier("editor-surprise-style-button")
            Divider()
            Section("Built-in") {
                ForEach(StylePreset.builtIns) { preset in
                    Button(action: { settings.applyStylePreset(preset) }) {
                        Text(preset.name)
                    }
                }
            }
            if !presets.userPresets.isEmpty {
                Section("Saved") {
                    ForEach(presets.userPresets) { preset in
                        Button(action: { settings.applyStylePreset(preset) }) {
                            Text(preset.name)
                        }
                    }
                }
            }
            Divider()
            Button("Save Current Style…") {
                savePresetName = settings.config.theme.displayName
                showSavePresetPrompt = true
            }
            .accessibilityIdentifier("editor-save-style-preset-button")
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VitrineTokens.Text.secondary)
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Style presets — apply a saved or built-in look, or save the current style.")
        .accessibilityLabel("Style presets")
        .accessibilityIdentifier("editor-style-preset-picker")
    }

    /// Promotes this window's current style to the app-wide default. Distinct
    /// from the export buttons in that it is code-independent — adopting a look is
    /// meaningful even before any code is typed — so it does not disable on an empty
    /// editor. It mirrors the File-menu "Make This Window the Default" command.
    var makeDefaultButton: some View {
        GlassIconButton(systemImage: VitrineCommand.makeDefault.systemImageName) {
            session.makeDefault()
        }
        .help(
            "Make this window's style the default — theme, font, background, and output — for new windows and captures."
        )
        .accessibilityLabel(VitrineCommand.makeDefault.accessibilityLabel)
        .accessibilityIdentifier("make-default-button")
    }

    /// One bordered toolbar icon button mirroring a `VitrineCommand`: same
    /// VoiceOver label and keyboard shortcut as its File-menu counterpart.
    @ViewBuilder
    func iconButton(
        _ command: VitrineCommand, _ identifier: String, help: String, systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        let button = GlassIconButton(systemImage: systemImage, action: action)
            .help(help)
            .disabled(!settings.config.hasRenderableContent)
            .accessibilityLabel(command.accessibilityLabel)
            .accessibilityIdentifier(identifier)

        if let shortcut = command.swiftUIShortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    /// Pin the current render in a floating always-on-top reference window,
    /// so an error/design stays visible while you work against it.
    var pinSnapshotButton: some View {
        GlassIconButton(systemImage: "pin", action: pinSnapshot)
            .help("Pin the snapshot in a floating window that stays on top")
            .disabled(!settings.config.hasRenderableContent)
            .accessibilityLabel("Pin snapshot")
            .accessibilityIdentifier("pin-snapshot-button")
    }

    func pinSnapshot() {
        guard
            let image = ExportManager.renderNSImage(
                settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
                fixedSize: settings.effectiveFixedSize,
                profile: settings.export.colorProfile)
        else { return }
        PinnedSnapshotController.shared.pin(image)
    }

    // MARK: - Export/share actions

    func share() {
        guard
            let image = ExportManager.renderNSImage(
                settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
                fixedSize: settings.effectiveFixedSize, profile: settings.export.colorProfile),
            let view = NSApp.keyWindow?.contentView
        else { return }
        ShareManager.share(image, relativeTo: view)
    }

    /// Copies the rendered image to the clipboard as a `data:image/png;base64,…`
    /// URI string, honoring the active preset's framing.
    func copyDataURI() {
        RichPasteboard.copyDataURI(
            for: settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
            fixedSize: settings.effectiveFixedSize, profile: settings.export.colorProfile)
    }

    /// Copies a self-contained Markdown image embed followed by the visible,
    /// redaction-safe source in a language-tagged code fence.
    func copyMarkdown() {
        RichPasteboard.copyMarkdown(
            for: settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
            fixedSize: settings.effectiveFixedSize, profile: settings.export.colorProfile)
    }

    /// Copies the highlighted code as styled RTF/HTML, preserving the syntax colors
    /// and the selected font.
    func copyHighlightedCode() {
        RichPasteboard.copyHighlightedCode(for: settings.config)
    }

    /// Copies a self-contained `vitrine://open` link that reproduces this snapshot. The
    /// link carries redaction-safe text and no local file references; an image background
    /// degrades to the default gradient.
    func copyShareLink() {
        do {
            let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: settings.config))
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.absoluteString, forType: .string)
            CaptureHUDController.shared.present(
                Notifier.confirmation(String(localized: "Share link copied")))
        } catch SnapshotShareLink.ShareLinkError.tooLarge {
            CaptureHUDController.shared.present(
                Notifier.failure(
                    String(localized: "This snapshot is too large to share as a link")))
        } catch {
            CaptureHUDController.shared.present(
                Notifier.failure(String(localized: "Couldn't copy the share link")))
        }
    }
}
