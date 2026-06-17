import AppKit
import SwiftUI

/// The editor's glass toolbar and the export/copy actions behind it (CS-032/037).
extension EditorView {
    // MARK: - Toolbar (design/handoff: glass band merged into the title bar)

    /// The glass toolbar: brand mark + title, the language picker, then the
    /// secondary export actions as bordered icon buttons and the gradient
    /// "Copy image" CTA. Each action mirrors its File-menu command (CS-032),
    /// sharing the command's VoiceOver label and keyboard shortcut.
    var editorToolbar: some View {
        HStack(spacing: 14) {
            // Just the app mark — the "Vitrine Editor" wordmark was redundant next to
            // the window and only crowded the toolbar (CS-087).
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
            // inspector toggle (CS-084). The toggle stays as a manual override.
            .onChange(of: settings.config.language) { _, newValue in
                if newValue == .diff {
                    settings.config.diffDecorations = true
                    settings.config.showLineNumbers = true
                }
            }

            Spacer(minLength: 8)

            // The annotation tool palette lives in the title bar (CS-085), so marks
            // are drawn with the cursor like a dedicated screenshot tool. Picking a
            // draw tool deselects any mark so its options show the new-draw style.
            AnnotationToolbar(
                activeTool: $activeTool,
                color: annotationStyleColor,
                thickness: annotationStyleThickness,
                showsColor: annotationStyleUsesColor,
                showsThickness: annotationStyleUsesThickness,
                canUndo: !annotationUndo.isEmpty,
                canRedo: !annotationRedo.isEmpty,
                shortcutsActive: annotationContextActive,
                onUndo: undoAnnotations,
                onRedo: redoAnnotations
            )
            .onChange(of: activeTool) { _, newTool in
                if newTool != .select { selectedAnnotationID = nil }
            }

            Spacer(minLength: 8)

            copyOptionsMenu
            iconButton(
                .saveImage, "save-button", help: "Render and save the image as a file",
                systemImage: "square.and.arrow.down",
                action: {
                    ExportManager.saveToFile(
                        settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
                        format: settings.exportFormat, fixedSize: settings.effectiveFixedSize,
                        profile: settings.colorProfile)
                })
            iconButton(
                .shareImage, "share-button", help: "Share the rendered image",
                systemImage: "square.and.arrow.up", action: share)
            multiSizeExportButton
            savePresetButton
            makeDefaultButton

            copyImageCTA
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
    @ViewBuilder var copyImageCTA: some View {
        let button = GradientCTAButton {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
            Text("Copy image")
        } action: {
            copyImage()
        }
        .help("Render and copy the image to the clipboard")
        .disabled(settings.config.code.isEmpty)
        .accessibilityLabel(VitrineCommand.copyImage.accessibilityLabel)
        .accessibilityIdentifier("copy-button")

        if let shortcut = VitrineCommand.copyImage.swiftUIShortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    /// Renders and copies the image, then — by default — closes the editor window so
    /// it gets out of the way once its job is done (CS-084). Users who copy more than
    /// once can keep it open from Settings.
    func copyImage() {
        ExportManager.copyToPasteboard(
            settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
            fixedSize: settings.effectiveFixedSize, profile: settings.colorProfile,
            richText: settings.richClipboard)
        // `closeAfterCopy` is an app-global behavior preference, so it is read from the
        // shared settings (what the Settings toggle edits) rather than this window's
        // per-session copy. Close *this* window — captured via `WindowAccessor`, so it
        // never depends on `keyWindow` being right — deferred past the button's action,
        // and `close()` (not `performClose`) so it is unconditional.
        guard AppSettings.shared.closeAfterCopy else { return }
        let target = editorWindow ?? NSApp.keyWindow
        DispatchQueue.main.async { target?.close() }
    }

    /// The explicit alternative copy targets behind the rich-text icon
    /// (CS-054): "Copy Highlighted Code" (syntax colors and font as RTF/HTML)
    /// and "Copy as Data URI" (`data:image/png;base64,…`). A menu so the
    /// one-click CTA stays the primary action while the developer-grade
    /// formats stay clearly labeled, one click away.
    var copyOptionsMenu: some View {
        Menu {
            Button {
                copyHighlightedCode()
            } label: {
                Label(
                    VitrineCommand.copyHighlightedCode.title,
                    systemImage: VitrineCommand.copyHighlightedCode.systemImageName)
            }
            .accessibilityIdentifier("copy-highlighted-code-button")

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
        .help("Copy the highlighted code as rich text, or the image as a data URI")
        .accessibilityLabel("More copy options")
        .accessibilityIdentifier("copy-options-menu")
        .disabled(settings.config.code.isEmpty)
    }

    /// The PRO multi-size export entry (CS-093): when unlocked it opens the size
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
        .disabled(settings.config.code.isEmpty)
        .accessibilityLabel(Text("Export sizes"))
        .accessibilityIdentifier("export-sizes-button")
        .sheet(item: $multiSizeSheet) { sheet in
            switch sheet {
            case .export:
                MultiSizeExportView(
                    baseConfig: settings.exportConfig, format: settings.exportFormat,
                    profile: settings.colorProfile)
            case .paywall:
                PaywallSheet(feature: .multiSizeExport)
            }
        }
    }

    /// The star: applies a saved style preset or saves the current style as a
    /// new one. Carries the legacy picker identifier so the UI tests keep
    /// addressing one stable element for style presets in the editor.
    var savePresetButton: some View {
        Menu {
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

    /// Promotes this window's current style to the app-wide default (CS-053). Distinct
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
            .disabled(settings.config.code.isEmpty)
            .accessibilityLabel(command.accessibilityLabel)
            .accessibilityIdentifier(identifier)

        if let shortcut = command.swiftUIShortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    // MARK: - Export/share actions

    func share() {
        guard
            let image = ExportManager.renderNSImage(
                settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
                fixedSize: settings.effectiveFixedSize, profile: settings.colorProfile),
            let view = NSApp.keyWindow?.contentView
        else { return }
        ShareManager.share(image, relativeTo: view)
    }

    /// Copies the rendered image to the clipboard as a `data:image/png;base64,…`
    /// URI string (CS-054), honoring the active preset's framing.
    func copyDataURI() {
        RichPasteboard.copyDataURI(
            for: settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
            fixedSize: settings.effectiveFixedSize, profile: settings.colorProfile)
    }

    /// Copies the highlighted code as styled RTF/HTML, preserving the syntax colors
    /// and the selected font (CS-054).
    func copyHighlightedCode() {
        RichPasteboard.copyHighlightedCode(for: settings.config)
    }
}
