import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The editor's three columns: the code input, the ambient preview stage, and the
/// inspector (CS-037).
extension EditorView {
    // MARK: - Columns

    /// The code-input column on glass: a "CODE" header with the line count and
    /// the format action, then the live-highlighted editor. Carries the
    /// empty-state affordance and the drop target.
    var codeColumn: some View {
        // `settings` arrives via @Environment (an @Observable), which has no projected
        // value; this local @Bindable provides the `$settings.config.code` write-binding
        // the code editor needs.
        @Bindable var settings = settings
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                TokenGroupLabel(
                    title: settings.config.usesImageContent ? Text("Image") : Text("Code"))
                Spacer(minLength: 0)
                // The line count + format action are code-only; a beautified image hides them.
                if !settings.config.usesImageContent {
                    Text(lineCountLabel)
                        .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                    formatButton
                }
            }
            .padding(.top, VitrineTokens.Spacing.sm)
            .padding(.horizontal, 18)

            if settings.config.usesImageContent {
                imagePanel
            } else {
                CodeEditorView(
                    text: $settings.config.code,
                    language: settings.config.language,
                    theme: settings.config.theme,
                    fontName: settings.config.fontName,
                    fontSize: settings.config.fontSize,
                    fontLigatures: settings.config.fontLigatures,
                    onReplaceAllPaste: { settings.config.clearContentMarks() }
                )
                .overlay {
                    if settings.config.code.isEmpty {
                        // The overlay is non-interactive except for its "Paste Code" button
                        // (see EmptyStateView): a click anywhere else falls through to the
                        // text view so the caret can land and the user can start typing —
                        // matching the "paste or type" affordance the copy promises.
                        EmptyStateView(
                            title: "Nothing to show yet",
                            message:
                                "Paste code or terminal output, or drop a file, to turn it into a beautiful image.",
                            actionTitle: "Paste Code",
                            action: pasteFromClipboard,
                            compact: true
                        )
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(VitrineTokens.Line.border)
                .frame(width: Brand.Stroke.hairline)
        }
        // Accept a dropped source file or selected text. `.onDrop` with UTType
        // payloads is the current API; the read happens off the closure via a
        // main-actor Task so the handler stays synchronous (CS-028).
        .onDrop(of: [.image, .fileURL, .text], isTargeted: $isDropTargeted) { providers in
            Task { await handleDrop(providers) }
            return true
        }
        .overlay { dropAffordance }
        .accessibilityContainerIdentifier("editor-drop-target")
    }

    /// Replaces the code editor when a beautified image is the content: a thumbnail of the
    /// loaded image, a hint that dropping replaces it, and a button to remove it (which
    /// returns the column to the code editor). The whole column is still a drop target.
    var imagePanel: some View {
        VStack(spacing: 14) {
            if let reference = settings.config.foregroundImage,
                let image = foregroundImageStore.image(for: reference)
            {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(VitrineTokens.Line.border))
            }
            Text("Drop a new image here to replace it.")
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .multilineTextAlignment(.center)
            Button(role: .destructive) {
                settings.config.foregroundImage = nil
            } label: {
                Text("Remove image")
            }
            .accessibilityIdentifier("remove-image-button")
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The line count shown beside the CODE label, or an em dash when empty.
    /// One interpolated key whose plural variant the catalog chooses (CS-047).
    var lineCountLabel: String {
        let code = settings.config.code
        guard !code.isEmpty else { return "—" }
        let count = code.split(separator: "\n", omittingEmptySubsequences: false).count
        return String(localized: "\(count) lines")
    }

    /// The 26 pt format action in the code header — the mouse route to the
    /// shared, undo-aware ⌥⌘F command (CS-032/CS-049).
    var formatButton: some View {
        Button {
            EditorCommandResponder.shared.formatCode(nil)
        } label: {
            Image(systemName: VitrineCommand.formatCode.systemImageName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VitrineTokens.Text.secondary)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Tidy the code: re-indent JSON, or strip the indentation shared by every line.")
        .accessibilityLabel(VitrineCommand.formatCode.accessibilityLabel)
        .accessibilityIdentifier("format-button")
        .disabled(settings.config.code.isEmpty)
    }

    // MARK: - Stage

    /// The stage: the preview card floating in ambient light "cast" by the
    /// selected background, always scaled to fit (design/handoff). Two radial
    /// glows tint the neutral stage from the background's stop colors, the
    /// card throws a matching tinted shadow, and a status capsule reports the
    /// destination, output size, format, and zoom.
    var previewStage: some View {
        GeometryReader { proxy in
            let scale = fitScale(in: proxy.size)
            // The preview mirrors the active preset's framing, so selecting a
            // fixed-size preset (e.g. OpenGraph 1200×630) updates the canvas
            // immediately (CS-020). The interactive annotation overlay is a sibling at
            // the canvas's natural size, so it shares the canvas coordinate space and
            // scales with it (CS-083) — a pointer drag maps straight to normalized
            // annotation coordinates.
            ZStack {
                SnapshotCanvas(config: previewConfig, fixedSize: settings.effectiveFixedSize)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self, of: \.size) { cardSize = $0 }
                    .compositingGroup()
                    .shadow(color: ambientShadowColor, radius: 24, x: 0, y: 24)
                AnnotationEditingOverlay(
                    settings: settings, selection: $selectedAnnotationID,
                    editingAnnotationID: $editingAnnotationID,
                    canvasSize: cardSize, activeTool: activeTool,
                    drawColor: newDrawColor, drawThickness: newDrawThickness,
                    onBeginEdit: recordAnnotationUndo)
                // Free-placement: drag the brand mark anywhere on the canvas. The
                // handle shares the canvas coordinate space (a sibling at cardSize),
                // so a drag maps straight to the normalized brand-kit position.
                if previewConfig.watermark?.placement == .free {
                    FreeWatermarkDragHandle(
                        position: $brandKit.brandKit.freePosition,
                        contentRect: CGRect(origin: .zero, size: cardSize))
                }
            }
            .scaleEffect(scale)
            // `scaleEffect` does not shrink the layout footprint, so without this the
            // unscaled (often very wide) card stays full-width in layout and its
            // centered overflow is clipped on the right. Pinning the footprint to the
            // *scaled* size centers the card on its visible bounds and keeps it fully
            // inside the stage at every window size (usability fix).
            .frame(width: cardSize.width * scale, height: cardSize.height * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: scale)
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { stageSize = $0 }
        .clipped()
        .background(stageBackground)
        .overlay(alignment: .bottom) { statusCapsule }
        .layoutPriority(2)
        .accessibilityIdentifier("editor-preview-stage")
    }

    /// The scale that keeps the card fully visible with a 72 pt margin, never
    /// upscaling past its natural size.
    func fitScale(in stage: CGSize) -> CGFloat {
        guard cardSize.width > 0, cardSize.height > 0 else { return 1 }
        return min(
            1,
            (stage.width - 72) / cardSize.width,
            (stage.height - 72) / cardSize.height)
    }

    /// The neutral stage washed by two radial glows in the background's stop
    /// colors, cross-fading over 0.6 s when the background changes.
    var stageBackground: some View {
        GeometryReader { proxy in
            ZStack {
                VitrineTokens.Surface.stage
                if let glow = glowColors {
                    RadialGradient(
                        colors: [glow.0.opacity(0.22), .clear],
                        center: UnitPoint(x: 0.38, y: 0.38),
                        startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.62)
                    RadialGradient(
                        colors: [glow.1.opacity(0.16), .clear],
                        center: UnitPoint(x: 0.68, y: 0.62),
                        startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.55)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: settings.config.background)
        }
        .accessibilityHidden(true)
    }

    /// The two ambient colors the stage catches from the current background:
    /// the gradient's stop colors, a solid's own color twice, or none for an
    /// image/transparent background (the stage stays neutral).
    var glowColors: (Color, Color)? {
        switch settings.config.background {
        case .gradient(let preset):
            let colors = preset.colors
            guard let first = colors.first, let last = colors.last else { return nil }
            return (first, last)
        case .customGradient(let gradient):
            let stops = gradient.stops.sorted { $0.location < $1.location }
            guard let first = stops.first?.color, let last = stops.last?.color else { return nil }
            return (first, last)
        case .solid(let color):
            return (color, color)
        case .image, .transparent:
            return nil
        }
    }

    /// The card's ambient drop shadow, tinted from the background's leading
    /// stop (`drop-shadow(0 24px 48px rgba(g1, 0.28))`).
    var ambientShadowColor: Color {
        (glowColors?.0 ?? .black).opacity(0.28)
    }

    /// The floating status capsule: destination · output size · format and
    /// resolution · zoom (only when scaled down). Locale-neutral data line.
    var statusCapsule: some View {
        Text(verbatim: statusLine)
            .font(.system(size: VitrineTokens.FontSize.caption))
            .foregroundStyle(VitrineTokens.Text.tertiary)
            .padding(.vertical, 4)
            .padding(.horizontal, VitrineTokens.Spacing.sm)
            .background(Capsule(style: .continuous).fill(VitrineTokens.Chrome.statusCapsule))
            .padding(.bottom, 14)
            .accessibilityIdentifier("editor-status-capsule")
    }

    var statusLine: String {
        let destination = settings.selectedPreset?.displayName ?? String(localized: "Custom")
        let size = settings.effectiveFixedSize ?? cardSize
        let dimensions = "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
        let output = "\(settings.exportFormat.displayName) \(settings.effectiveExportScale)×"
        var line = "\(destination) · \(dimensions) · \(output)"
        if stageSize.width > 0 {
            let zoom = Int((fitScale(in: stageSize) * 100).rounded())
            if zoom < 100 { line += " · \(zoom)%" }
        }
        return line
    }

    /// The focused inspector column with progressive disclosure for advanced
    /// controls (CS-037), on glass per the redesign.
    var inspectorColumn: some View {
        EditorInspectorView(settings: settings, themes: themes)
    }

    /// The config the center stage renders. When the editor is empty it shows a
    /// representative sample so the preview is never a blank card — the empty state
    /// over the code column still invites pasting, but the user immediately sees
    /// what a finished image looks like with the current presets (CS-037 "empty
    /// editor state shows a sample"). The substitution is preview-only and never
    /// mutates the live document (see ``EditorPreview``).
    var previewConfig: SnapshotConfig {
        var config = EditorPreview.configForPreview(settings.config)
        // WYSIWYG: the preview shows the same brand watermark the export will apply
        // (CS-092), resolved from the observed brand kit + entitlement so it tracks
        // changes live. Off unless the user enabled it and PRO is unlocked.
        config.watermark = brandKit.resolvedWatermark(isPro: entitlements.isPro)
        // While a text callout is being edited, blank its canvas copy so the inline
        // field (in the overlay) is the only text drawn — no doubled pill. Preview-only:
        // export surfaces render `settings.exportConfig`, so this never mutates the
        // rendered/exported image configuration.
        if let editing = editingAnnotationID,
            let index = config.annotations.firstIndex(where: { $0.id == editing }),
            config.annotations[index].kind == .text
        {
            config.annotations[index].text = ""
        }
        return config
    }

    /// A subtle border + label shown while a drag hovers the editor, so the editor
    /// reads as a drop target (CS-028). Non-interactive so it never intercepts the
    /// drop itself.
    @ViewBuilder
    var dropAffordance: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: Brand.Radius.card)
                .strokeBorder(
                    Brand.Palette.accent.color, style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .background(Brand.Palette.accent.color.opacity(0.08))
                .overlay {
                    Label("Drop to load", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .padding(Brand.Spacing.sm)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding(Brand.Spacing.xs)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Fills the editor from the clipboard, detecting the language so the empty
    /// state's "Paste Code" action produces an immediately useful preview.
    func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return
        }
        let language = LanguageDetector.detect(text)
        settings.config.language = language
        // Pasting fresh code is a new capture, so drop content-bound marks (annotations,
        // highlighted lines) that were positioned over whatever was here before.
        settings.config.clearContentMarks()
        // Tidy the indentation on paste when the user opts in (CS-049); the global
        // preference (not the per-window session) owns this behavior.
        settings.config.code =
            AppSettings.shared.reindentOnPaste ? CodeFormatter.tidy(text, language: language) : text
    }
}
