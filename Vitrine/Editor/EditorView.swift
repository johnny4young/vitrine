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

    var body: some View {
        VStack(spacing: 0) {
            // Preset-first: the destination/style pickers are the first controls,
            // above code and preview (CS-037).
            PresetStripView(settings: settings, presets: presets)
            Divider()

            HSplitView {
                codeColumn
                previewStage
                inspectorColumn
            }
        }
        // A comfortable minimum that still fits the three columns on the smallest
        // supported window, plus headroom so large displays never leave the
        // preview stranded (the stage column expands to absorb extra width).
        .frame(minWidth: 940, minHeight: 520)
        .toolbar { toolbar }
        .accessibilityIdentifier("editor-root")
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

    // MARK: - Columns

    /// The code-input column. Carries the empty-state affordance and the drop
    /// target; it has a real minimum width but yields layout priority to the
    /// preview stage so the canvas, not the code, dominates on a wide window.
    private var codeColumn: some View {
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
                    action: pasteFromClipboard
                )
            }
        }
        .frame(minWidth: 280, idealWidth: 340)
        .layoutPriority(1)
        // Accept a dropped source file or selected text. `.onDrop` with UTType
        // payloads is the current API; the read happens off the closure via a
        // main-actor Task so the handler stays synchronous (CS-028).
        .onDrop(of: [.fileURL, .text], isTargeted: $isDropTargeted) { providers in
            Task { await handleDrop(providers) }
            return true
        }
        .overlay { dropAffordance }
        .accessibilityIdentifier("editor-drop-target")
    }

    /// The hero preview, centered on the neutral "display case" stage so it reads
    /// as the focus of the window rather than a cramped settings thumbnail (CS-037).
    /// It absorbs spare width (highest layout priority) and stays centered so a
    /// large display never leaves an awkward gutter; on the minimum window it still
    /// scrolls rather than clipping.
    private var previewStage: some View {
        ScrollView([.horizontal, .vertical]) {
            // The preview mirrors the active preset's framing, so selecting a
            // fixed-size preset (e.g. OpenGraph 1200×630) updates the canvas
            // immediately (CS-020).
            SnapshotCanvas(config: previewConfig, fixedSize: settings.effectiveFixedSize)
                .padding(Brand.Spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 360, idealWidth: 560)
        .layoutPriority(2)
        .background(Brand.Palette.stage.color)
        .accessibilityIdentifier("editor-preview-stage")
    }

    /// The focused inspector column with progressive disclosure for advanced
    /// controls (CS-037). Kept narrow and fixed-feeling so the preview keeps the
    /// width it gains.
    private var inspectorColumn: some View {
        EditorInspectorView(settings: settings, themes: themes)
            .frame(minWidth: 280, idealWidth: 300, maxWidth: 360)
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

    /// The export toolbar. Each item is the equivalent of a File-menu command
    /// (CS-032): it shares the command's SF Symbol and VoiceOver label, and binds
    /// the same keyboard shortcut, so the toolbar button and the menu command stay
    /// in lockstep and either route reaches the same exporter. The language picker
    /// lives here too, so the per-capture choice (language) sits with the export
    /// actions while the reusable look (presets) leads the canvas (CS-037).
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Language", selection: $settings.config.language) {
                ForEach(settings.orderedLanguages) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .frame(minWidth: 140)
            .help("The language used to syntax-highlight the code.")
            .accessibilityLabel("Language")
            .accessibilityIdentifier("language-picker")
        }

        ToolbarItemGroup {
            toolbarButton(
                .copyImage, "copy-button", help: "Render and copy the image to the clipboard"
            ) {
                ExportManager.copyToPasteboard(
                    settings.config, scale: CGFloat(settings.effectiveExportScale),
                    fixedSize: settings.effectiveFixedSize, profile: settings.colorProfile,
                    richText: settings.richClipboard)
            }

            copyOptionsMenu

            toolbarButton(.saveImage, "save-button", help: "Render and save the image as a file") {
                ExportManager.saveToFile(
                    settings.config, scale: CGFloat(settings.effectiveExportScale),
                    format: settings.exportFormat, fixedSize: settings.effectiveFixedSize,
                    profile: settings.colorProfile)
            }

            toolbarButton(
                .shareImage, "share-button", help: "Share the rendered image", action: share)
        }
    }

    /// A small overflow menu beside the primary Copy button holding the explicit
    /// alternative copy targets (CS-054): "Copy as Data URI" (a
    /// `data:image/png;base64,…` string) and "Copy Highlighted Code" (the syntax
    /// colors and selected font as RTF/HTML). These sit behind a menu so the
    /// one-click Copy stays the primary, unchanged action while the developer-grade
    /// formats are clearly labeled and one click away.
    @ViewBuilder
    private var copyOptionsMenu: some View {
        Menu {
            Button {
                copyDataURI()
            } label: {
                Label(
                    VitrineCommand.copyDataURI.title,
                    systemImage: VitrineCommand.copyDataURI.systemImageName)
            }
            .accessibilityIdentifier("copy-data-uri-button")

            Button {
                copyHighlightedCode()
            } label: {
                Label(
                    VitrineCommand.copyHighlightedCode.title,
                    systemImage: VitrineCommand.copyHighlightedCode.systemImageName)
            }
            .accessibilityIdentifier("copy-highlighted-code-button")
        } label: {
            Label("More copy options", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
        .help("Copy as a data URI, or copy the highlighted code as rich text")
        .accessibilityLabel("More copy options")
        .accessibilityIdentifier("copy-options-menu")
        .disabled(settings.config.code.isEmpty)
    }

    /// Builds one export toolbar button from a `VitrineCommand`, applying its
    /// symbol, VoiceOver label, accessibility identifier, and keyboard shortcut.
    /// The shortcut matches the File-menu command so pressing it works whether the
    /// editor toolbar or the menu has focus.
    @ViewBuilder
    private func toolbarButton(
        _ command: VitrineCommand, _ identifier: String, help: String, action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Label(command.title, systemImage: command.systemImageName)
        }
        .help(help)
        .accessibilityLabel(command.accessibilityLabel)
        .accessibilityIdentifier(identifier)
        .disabled(settings.config.code.isEmpty)

        if let shortcut = command.swiftUIShortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    /// Fills the editor from the clipboard, detecting the language so the empty
    /// state's "Paste Code" action produces an immediately useful preview.
    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return
        }
        settings.config.code = text
        settings.config.language = LanguageDetector.detect(text)
    }

    // MARK: - Drag-and-drop input (CS-028)

    /// A loaded drop awaiting the user's replace-vs-append choice, kept so the
    /// confirmation dialog can apply exactly what was dropped.
    private struct PendingDrop {
        var loaded: FileInputLoader.LoadedFile

        /// The dialog title names the source so the choice has context — the
        /// filename for a dropped file, or a generic label for dropped text.
        var promptTitle: String {
            loaded.filename.isEmpty ? "Add Dropped Text" : "Load “\(loaded.filename)”"
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
