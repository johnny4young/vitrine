import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The editor window, redesigned around presets (CS-037): a preset-first command
/// strip on top, then code on the left, a hero preview on a neutral stage in the
/// center, and a focused inspector on the right (CS-005/006/007/008/037).
///
/// ## Why this layout
///
/// Beautiful output should come from picking a strong preset first, not from
/// tweaking many sliders before seeing value. So the very first controls are the
/// destination/style presets (``PresetStripView``) and the primary export actions
/// (the window toolbar); the live preview gets visual priority in the center; and
/// the advanced style controls live behind progressive disclosure in
/// ``EditorInspectorView`` rather than crowding the canvas.
struct EditorView: View {
    @EnvironmentObject private var settings: AppSettings

    /// This window's editor session (CS-053). Each editor window has its own session
    /// (and therefore its own `settings` above), so a window can promote *its* style to
    /// the app-wide default without affecting the others. Injected by
    /// `EditorWindowController` when the window is created.
    @EnvironmentObject private var session: EditorSession

    /// The saved-preset catalog and the custom-theme resolver, shared with the
    /// Settings panes so the editor and Preferences operate on the same data
    /// (CS-030/031). Held as observed singletons so the strip and inspector update
    /// live when presets or themes change anywhere in the app.
    @ObservedObject private var presets = PresetStore.shared
    @ObservedObject private var themes = CustomThemeStore.shared

    /// True while a drag is hovering the editor, used to draw the drop affordance
    /// (CS-028).
    @State private var isDropTargeted = false

    /// A binary/too-large/unreadable file the user tried to drop; presented as an
    /// alert so the rejection is clearly explained (CS-028).
    @State private var dropError: FileInputLoader.LoadError?

    /// A successful load that is waiting on the user to choose replace vs. append,
    /// because the editor already has code (CS-028). `nil` when no decision is
    /// pending.
    @State private var pendingDrop: PendingDrop?

    /// The natural (unscaled) size of the preview card, measured so the stage
    /// can scale it to always fit (design/handoff "scale-to-fit").
    @State private var cardSize: CGSize = .zero

    /// The currently selected annotation, shared between the preview's interactive
    /// overlay and the inspector's annotation controls (CS-083). `nil` when nothing
    /// is selected. Editor-only UI state, not persisted.
    @State private var selectedAnnotationID: UUID?

    /// The active annotation tool (CS-085). `.select` moves/resizes existing marks;
    /// any other tool puts the preview into draw mode. Editor-only UI state.
    @State private var activeTool: AnnotationTool = .select

    /// The color and size the next drawn mark inherits. When a mark is selected, the
    /// toolbar edits *its* color/size instead (see `annotationStyleColor`).
    @State private var newDrawColor: Color = Annotation.defaultColor.color
    @State private var newDrawThickness: Double = Annotation.defaultThickness

    /// Undo/redo history for annotation edits (CS-086): each entry is a full snapshot
    /// of `config.annotations` captured just before a draw/move/resize/delete. Bounded
    /// so a long session never grows without limit.
    @State private var annotationUndo: [[Annotation]] = []
    @State private var annotationRedo: [[Annotation]] = []

    /// True while the save-style-preset prompt is up (the toolbar star).
    @State private var showSavePresetPrompt = false
    @State private var savePresetName = ""

    /// This editor's own `NSWindow`, captured via `WindowAccessor`, so actions like
    /// close-after-copy target it directly instead of guessing at `keyWindow`.
    @State private var editorWindow: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            HStack(spacing: 0) {
                codeColumn
                    .frame(width: 280)
                previewStage
                inspectorColumn
                    .frame(width: 302)
            }
        }
        // Merge the toolbar into the title bar: the window is `fullSizeContentView`
        // with a hidden, transparent title bar, but SwiftUI still insets its content
        // below the title bar by default, leaving an empty strip above the toolbar.
        // Extending into the top safe area pulls the glass toolbar up to the window
        // edge, with the traffic lights floating over its leading 86 pt (CS-037).
        .ignoresSafeArea(.container, edges: .top)
        // A comfortable minimum that still fits the three columns on the smallest
        // supported window; the stage column absorbs all extra width.
        .frame(minWidth: 940, minHeight: 520)
        .background(WindowAccessor { editorWindow = $0 })
        // The redesign's controls tint with the brand accent regardless of the
        // user's system accent (`--control-on: var(--accent)`).
        .tint(VitrineTokens.Accent.base)
        .alert("Save Preset", isPresented: $showSavePresetPrompt) {
            TextField("Name", text: $savePresetName)
                .accessibilityIdentifier("editor-save-preset-name-field")
            Button("Save") {
                _ = presets.savePreset(named: savePresetName, from: settings.config)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Save the current style — theme, font, background, and the rest of your current layout — as a named preset."
            )
        }
        // No identifier on this root: the VStack is not an accessibility element,
        // so an identifier here would propagate down and *override* the nearest
        // descendant elements' identifiers (the preset strip would report the
        // root's name instead of `editor-preset-strip`), breaking the CS-037 and
        // CS-047 UI tests. The window itself is tagged `editor-window`.
        // A rejected file (binary, too large, unreadable) explains why in plain
        // language rather than failing silently (CS-028).
        .alert(
            "Can't Load That File",
            isPresented: Binding(
                get: { dropError != nil },
                set: { if !$0 { dropError = nil } })
        ) {
            Button("OK", role: .cancel) { dropError = nil }
        } message: {
            Text(dropError?.message ?? "")
        }
        // When the editor already has code, a drop asks before clobbering it:
        // replace everything, or append to the end (CS-028 "clear prompt").
        .confirmationDialog(
            pendingDrop?.promptTitle ?? "",
            isPresented: Binding(
                get: { pendingDrop != nil },
                set: { if !$0 { pendingDrop = nil } }),
            titleVisibility: .visible
        ) {
            // Replacing discards the entire current document, so it is marked
            // destructive (red) to distinguish it from the safe Append — matching
            // every other irreversible action in the app (CS-028).
            Button("Replace", role: .destructive) { applyDrop(replacing: true) }
            Button("Append") { applyDrop(replacing: false) }
            Button("Cancel", role: .cancel) { pendingDrop = nil }
        } message: {
            Text(
                "This editor already has code. Replace it with the dropped content, or append to the end?"
            )
        }
    }

    // MARK: - Toolbar (design/handoff: glass band merged into the title bar)

    /// The glass toolbar: brand mark + title, the language picker, then the
    /// secondary export actions as bordered icon buttons and the gradient
    /// "Copy image" CTA. Each action mirrors its File-menu command (CS-032),
    /// sharing the command's VoiceOver label and keyboard shortcut.
    private var editorToolbar: some View {
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
                        settings.config, scale: CGFloat(settings.effectiveExportScale),
                        format: settings.exportFormat, fixedSize: settings.effectiveFixedSize,
                        profile: settings.colorProfile)
                })
            iconButton(
                .shareImage, "share-button", help: "Share the rendered image",
                systemImage: "square.and.arrow.up", action: share)
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
    @ViewBuilder private var copyImageCTA: some View {
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
    private func copyImage() {
        ExportManager.copyToPasteboard(
            settings.config, scale: CGFloat(settings.effectiveExportScale),
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
    private var copyOptionsMenu: some View {
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

    /// The star: applies a saved style preset or saves the current style as a
    /// new one. Carries the legacy picker identifier so the UI tests keep
    /// addressing one stable element for style presets in the editor.
    private var savePresetButton: some View {
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

    /// One bordered toolbar icon button mirroring a `VitrineCommand`: same
    /// VoiceOver label and keyboard shortcut as its File-menu counterpart.
    @ViewBuilder
    private func iconButton(
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

    // MARK: - Columns

    /// The code-input column on glass: a "CODE" header with the line count and
    /// the format action, then the live-highlighted editor. Carries the
    /// empty-state affordance and the drop target.
    private var codeColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TokenGroupLabel(title: Text("Code"))
                Spacer(minLength: 0)
                Text(lineCountLabel)
                    .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                formatButton
            }
            .padding(.top, VitrineTokens.Spacing.sm)
            .padding(.horizontal, 18)

            CodeEditorView(
                text: $settings.config.code,
                language: settings.config.language,
                theme: settings.config.theme,
                fontName: settings.config.fontName,
                fontSize: settings.config.fontSize,
                fontLigatures: settings.config.fontLigatures
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
                            "Paste code, or drop a source file, to turn it into a beautiful image.",
                        actionTitle: "Paste Code",
                        action: pasteFromClipboard,
                        compact: true
                    )
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
        .onDrop(of: [.fileURL, .text], isTargeted: $isDropTargeted) { providers in
            Task { await handleDrop(providers) }
            return true
        }
        .overlay { dropAffordance }
        .accessibilityContainerIdentifier("editor-drop-target")
    }

    /// The line count shown beside the CODE label, or an em dash when empty.
    /// One interpolated key whose plural variant the catalog chooses (CS-047).
    private var lineCountLabel: String {
        let code = settings.config.code
        guard !code.isEmpty else { return "—" }
        let count = code.split(separator: "\n", omittingEmptySubsequences: false).count
        return String(localized: "\(count) lines")
    }

    /// The 26 pt format action in the code header — the mouse route to the
    /// shared, undo-aware ⌥⌘F command (CS-032/CS-049).
    private var formatButton: some View {
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

    /// The stage: the preview card floating in ambient light "cast" by the
    /// selected background, always scaled to fit (design/handoff). Two radial
    /// glows tint the neutral stage from the background's stop colors, the
    /// card throws a matching tinted shadow, and a status capsule reports the
    /// destination, output size, format, and zoom.
    private var previewStage: some View {
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
                    canvasSize: cardSize, activeTool: activeTool,
                    drawColor: newDrawColor, drawThickness: newDrawThickness,
                    onBeginEdit: recordAnnotationUndo)
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
    private func fitScale(in stage: CGSize) -> CGFloat {
        guard cardSize.width > 0, cardSize.height > 0 else { return 1 }
        return min(
            1,
            (stage.width - 72) / cardSize.width,
            (stage.height - 72) / cardSize.height)
    }

    // MARK: - Annotation toolbar style (CS-085)

    /// The annotation currently selected in Select mode, if any.
    private var selectedAnnotation: Annotation? {
        guard let id = selectedAnnotationID else { return nil }
        return settings.config.annotations.first { $0.id == id }
    }

    /// The toolbar color: the selected mark's color when one is selected, otherwise
    /// the new-draw default. Writing it updates whichever target is active.
    private var annotationStyleColor: Binding<Color> {
        Binding(
            get: { selectedAnnotation?.color.color ?? newDrawColor },
            set: { newValue in
                newDrawColor = newValue
                if let id = selectedAnnotationID,
                    let index = settings.config.annotations.firstIndex(where: { $0.id == id })
                {
                    settings.config.annotations[index].color = RGBAColor(newValue)
                }
            })
    }

    /// The toolbar size slider, mirroring `annotationStyleColor`'s selected-vs-default
    /// targeting.
    private var annotationStyleThickness: Binding<Double> {
        Binding(
            get: { selectedAnnotation?.thickness ?? newDrawThickness },
            set: { newValue in
                newDrawThickness = newValue
                if let id = selectedAnnotationID,
                    let index = settings.config.annotations.firstIndex(where: { $0.id == id })
                {
                    settings.config.annotations[index].thickness = newValue
                }
            })
    }

    /// Whether the color swatch applies to the current context (the selected mark, or
    /// the active draw tool). Blur has no color.
    private var annotationStyleUsesColor: Bool {
        if let selected = selectedAnnotation { return selected.kind != .blur }
        return activeTool.usesColor
    }

    /// Whether the size slider applies (the highlighter fill and blur have no stroke).
    private var annotationStyleUsesThickness: Bool {
        if let selected = selectedAnnotation {
            return selected.kind != .blur && selected.kind != .highlighter
        }
        return activeTool.usesThickness
    }

    // MARK: - Annotation undo/redo (CS-086)

    /// Whether the user is in an annotation context (a draw tool is active or a mark
    /// is selected). The undo/redo keyboard shortcut is gated on this so it never
    /// hijacks the code editor's own Cmd-Z while you are typing code.
    private var annotationContextActive: Bool {
        activeTool != .select || selectedAnnotationID != nil
    }

    /// Snapshots the current marks just before a discrete edit, so it can be undone.
    private func recordAnnotationUndo() {
        annotationRedo.removeAll()
        annotationUndo.append(settings.config.annotations)
        if annotationUndo.count > 60 { annotationUndo.removeFirst() }
    }

    private func undoAnnotations() {
        guard !annotationUndo.isEmpty else { return }
        annotationRedo.append(settings.config.annotations)
        settings.config.annotations = annotationUndo.removeLast()
        selectedAnnotationID = nil
    }

    private func redoAnnotations() {
        guard !annotationRedo.isEmpty else { return }
        annotationUndo.append(settings.config.annotations)
        settings.config.annotations = annotationRedo.removeLast()
        selectedAnnotationID = nil
    }

    /// The neutral stage washed by two radial glows in the background's stop
    /// colors, cross-fading over 0.6 s when the background changes.
    private var stageBackground: some View {
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
    private var glowColors: (Color, Color)? {
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
    private var ambientShadowColor: Color {
        (glowColors?.0 ?? .black).opacity(0.28)
    }

    /// The floating status capsule: destination · output size · format and
    /// resolution · zoom (only when scaled down). Locale-neutral data line.
    private var statusCapsule: some View {
        Text(verbatim: statusLine)
            .font(.system(size: VitrineTokens.FontSize.caption))
            .foregroundStyle(VitrineTokens.Text.tertiary)
            .padding(.vertical, 4)
            .padding(.horizontal, VitrineTokens.Spacing.sm)
            .background(Capsule(style: .continuous).fill(VitrineTokens.Chrome.statusCapsule))
            .padding(.bottom, 14)
            .accessibilityIdentifier("editor-status-capsule")
    }

    /// The stage's current size, recorded so the capsule can report the live
    /// zoom percentage.
    @State private var stageSize: CGSize = .zero

    private var statusLine: String {
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
    private var inspectorColumn: some View {
        EditorInspectorView(settings: settings, themes: themes)
    }

    /// The config the center stage renders. When the editor is empty it shows a
    /// representative sample so the preview is never a blank card — the empty state
    /// over the code column still invites pasting, but the user immediately sees
    /// what a finished image looks like with the current presets (CS-037 "empty
    /// editor state shows a sample"). The substitution is preview-only and never
    /// mutates the live document (see ``EditorPreview``).
    private var previewConfig: SnapshotConfig {
        EditorPreview.configForPreview(settings.config)
    }

    /// A subtle border + label shown while a drag hovers the editor, so the editor
    /// reads as a drop target (CS-028). Non-interactive so it never intercepts the
    /// drop itself.
    @ViewBuilder
    private var dropAffordance: some View {
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

    /// Promotes this window's current style to the app-wide default (CS-053). Distinct
    /// from the export buttons in that it is code-independent — adopting a look is
    /// meaningful even before any code is typed — so it does not disable on an empty
    /// editor. It mirrors the File-menu "Make This Window the Default" command.
    private var makeDefaultButton: some View {
        GlassIconButton(systemImage: VitrineCommand.makeDefault.systemImageName) {
            session.makeDefault()
        }
        .help(
            "Make this window's style the default — theme, font, background, and output — for new windows and captures."
        )
        .accessibilityLabel(VitrineCommand.makeDefault.accessibilityLabel)
        .accessibilityIdentifier("make-default-button")
    }

    /// Fills the editor from the clipboard, detecting the language so the empty
    /// state's "Paste Code" action produces an immediately useful preview.
    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return
        }
        let language = LanguageDetector.detect(text)
        settings.config.language = language
        // Tidy the indentation on paste when the user opts in (CS-049); the global
        // preference (not the per-window session) owns this behavior.
        settings.config.code =
            AppSettings.shared.reindentOnPaste ? CodeFormatter.tidy(text, language: language) : text
    }

    // MARK: - Drag-and-drop input (CS-028)

    /// A loaded drop awaiting the user's replace-vs-append choice, kept so the
    /// confirmation dialog can apply exactly what was dropped.
    private struct PendingDrop {
        var loaded: FileInputLoader.LoadedFile

        /// The dialog title names the source so the choice has context — the
        /// filename for a dropped file, or a generic label for dropped text.
        /// Localized through the String Catalog (CS-047); the filename is inserted
        /// into the localized template.
        var promptTitle: String {
            loaded.filename.isEmpty
                ? String(localized: "Add Dropped Text")
                : String(localized: "Load “\(loaded.filename)”")
        }
    }

    /// Handles a drop onto the editor: reads a source file (preferred) or selected
    /// text from the providers, then either loads it straight away (empty editor)
    /// or asks whether to replace or append (non-empty editor). A binary, oversized,
    /// or unreadable file is rejected with a clear alert (CS-028).
    private func handleDrop(_ providers: [NSItemProvider]) async {
        // A dragged file is the richer source, so try file URLs before text — a
        // Finder drag often advertises both.
        for provider in providers {
            if let url = await readFileURL(from: provider) {
                do {
                    offerLoaded(try FileInputLoader.load(from: url))
                } catch let error as FileInputLoader.LoadError {
                    dropError = error
                } catch {
                    dropError = .unreadable
                }
                return
            }
        }

        // No file: fall back to dropped text, inferring the language from content.
        for provider in providers {
            if let text = await readText(from: provider),
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                let interpreted = LanguageDetector.interpret(text)
                offerLoaded(
                    FileInputLoader.LoadedFile(
                        text: interpreted.code, language: interpreted.language, filename: ""))
                return
            }
        }
    }

    /// Loads immediately into an empty editor, or defers to the replace/append
    /// prompt when the editor already holds code (CS-028 "clear prompt").
    private func offerLoaded(_ loaded: FileInputLoader.LoadedFile) {
        if settings.config.code.isEmpty {
            apply(loaded, replacing: true)
        } else {
            pendingDrop = PendingDrop(loaded: loaded)
        }
    }

    /// Resolves a pending replace/append choice from the confirmation dialog.
    private func applyDrop(replacing: Bool) {
        guard let pending = pendingDrop else { return }
        apply(pending.loaded, replacing: replacing)
        pendingDrop = nil
    }

    /// Writes a loaded drop into the live config. Replacing swaps the whole
    /// document and adopts the inferred language and filename; appending keeps the
    /// current language (the existing code defines it) and only grows the text.
    ///
    /// Either way this just fills the editor — it never records a Recent. The
    /// filename rides along in `metadata.filename` (CS-022) so a *later*
    /// capture/export reflects the source, honoring "Recents record loaded file
    /// metadata only when the user captures/exports" (CS-028).
    private func apply(_ loaded: FileInputLoader.LoadedFile, replacing: Bool) {
        loaded.apply(to: &settings.config, replacing: replacing)
        settings.noteLanguageUsed(settings.config.language)
        Log.capture.info(
            "Editor drop loaded (\(loaded.text.count, privacy: .public) chars, \(loaded.language.rawValue, privacy: .public))"
        )
    }

    /// Reads a dropped file's URL from a provider, or `nil` when it carries none.
    /// The coerced item is a `URL` (or URL bytes), which `FileInputLoader` then
    /// reads under a security-scoped access — no broad file entitlement is
    /// involved (CS-028).
    private func readFileURL(from provider: NSItemProvider) async -> URL? {
        let type = UTType.fileURL.identifier
        guard provider.hasItemConformingToTypeIdentifier(type) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Reads dropped plain text from a provider, or `nil` when it carries none.
    private func readText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { string, _ in
                continuation.resume(returning: string)
            }
        }
    }

    private func share() {
        guard
            let image = ExportManager.renderNSImage(
                settings.config, scale: CGFloat(settings.effectiveExportScale),
                fixedSize: settings.effectiveFixedSize, profile: settings.colorProfile),
            let view = NSApp.keyWindow?.contentView
        else { return }
        ShareManager.share(image, relativeTo: view)
    }

    /// Copies the rendered image to the clipboard as a `data:image/png;base64,…`
    /// URI string (CS-054), honoring the active preset's framing.
    private func copyDataURI() {
        RichPasteboard.copyDataURI(
            for: settings.config, scale: CGFloat(settings.effectiveExportScale),
            fixedSize: settings.effectiveFixedSize, profile: settings.colorProfile)
    }

    /// Copies the highlighted code as styled RTF/HTML, preserving the syntax colors
    /// and the selected font (CS-054).
    private func copyHighlightedCode() {
        RichPasteboard.copyHighlightedCode(for: settings.config)
    }
}

extension VitrineCommand {
    /// This command's AppKit `modifiers` translated into SwiftUI `EventModifiers`,
    /// so a toolbar/menu-bar button carries the exact modifier set its File-menu
    /// counterpart uses (CS-032). Kept separate from `swiftUIShortcut` because it
    /// is the drift-prone part — a dropped flag here is what would make ⇧⌘C decay
    /// to ⌘C in the toolbar — and, being a pure value mapping, it is unit-testable
    /// without constructing a `KeyboardShortcut` (whose initializer reaches the
    /// system Shortcuts daemon and hangs in a headless test host).
    var swiftUIEventModifiers: EventModifiers {
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        return eventModifiers
    }

    /// The SwiftUI `KeyboardShortcut` equivalent of this command's AppKit key and
    /// modifiers, so a toolbar button can bind the exact shortcut its File-menu
    /// counterpart uses (CS-032). `nil` when the command has no shortcut. Defined
    /// here, in a SwiftUI-importing file, to keep `VitrineCommands.swift` itself
    /// AppKit-only (it builds an `NSMenu`).
    var swiftUIShortcut: KeyboardShortcut? {
        guard let key = keyEquivalent, let character = key.first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: swiftUIEventModifiers)
    }
}

/// Captures the hosting `NSWindow` of a SwiftUI view, so AppKit-level actions (e.g.
/// close-after-copy, CS-084) can target *this* window rather than guessing at
/// `NSApp.keyWindow`. Resolves once the view joins the window, and again if it moves.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Poll the next few run loops until the view has joined its window, then stop.
        // (A one-shot resolve can miss it if the view isn't in the window yet; a
        // per-`updateNSView` resolve churns on every editor re-render and can slow
        // launch enough to flake the multi-window UI test — this captures once,
        // reliably, without the churn.)
        capture(from: view, attempt: 0)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func capture(from view: NSView, attempt: Int) {
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            if let window = view.window {
                onResolve(window)
            } else if attempt < 30 {
                capture(from: view, attempt: attempt + 1)
            }
        }
    }
}
