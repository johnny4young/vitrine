import AppKit
import KeyboardShortcuts
import SwiftUI

/// A reusable picker for destination presets, shared by the editor and the
/// Style/Output settings panes (CS-020). The selection reflects the active
/// preset and offers an explicit "Custom" row for the user's own settings.
///
/// Selecting a preset applies its presentation/output guidance and persists the
/// choice; selecting "Custom" clears the selection without altering the style.
///
/// The accessibility identifier is a parameter because more than one instance can
/// be on screen at once (the editor header plus a settings pane). The default keeps
/// the settings panes' stable identifier; the editor passes its own so each live
/// instance resolves to a unique element (CS-032).
struct DestinationPresetPicker: View {
    @ObservedObject var settings: AppSettings

    /// The accessibility identifier for this instance. Defaults to the settings
    /// panes' value; callers that show a second instance pass a distinct one.
    var identifier: String = "destination-preset-picker"

    /// Sentinel tag for the "Custom" row (no preset). Not a valid preset id.
    private static let customTag = ""

    var body: some View {
        Picker("Destination", selection: selectionBinding) {
            Text("Custom").tag(Self.customTag)
            ForEach(ExportPreset.all) { preset in
                Text(preset.displayName).tag(preset.id)
            }
        }
        .help(presetHelp)
        .accessibilityLabel("Destination preset")
        .accessibilityIdentifier(identifier)
    }

    private var presetHelp: String {
        settings.selectedPreset?.summary
            ?? "Custom: your own size and style, with no destination preset applied."
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: { settings.selectedPresetID ?? Self.customTag },
            set: { id in
                if let preset = ExportPreset.preset(withID: id) {
                    settings.selectPreset(preset)
                } else {
                    settings.clearPreset()
                }
            }
        )
    }
}

/// General pane: hotkey, what it triggers, launch at login (CS-002/010/014),
/// plus a "Reset all settings" action that restores defaults (CS-050).
struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var presets: PresetStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Global hotkey:", name: .quickCapture)

            Picker("Hotkey runs", selection: $settings.hotkeyAction) {
                ForEach(HotkeyAction.allCases) { action in
                    Text(action.displayName).tag(action)
                }
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .accessibilityIdentifier("launch-at-login-toggle")
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLogin.setEnabled(newValue)
                }

            Section {
                Picker("App language", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .accessibilityIdentifier("app-language-picker")

                // Shown only once the choice differs from the language the app is
                // running in, so the user can apply it now instead of quitting and
                // reopening a Dock-less menu-bar agent by hand (CS-047).
                if settings.languageChangePendingRelaunch {
                    Button("Relaunch to Apply") { AppRelauncher.relaunch() }
                        .accessibilityIdentifier("relaunch-to-apply-button")
                }
            } footer: {
                Text("Vitrine reopens in the selected language the next time you launch it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All Settings…", role: .destructive) {
                    showResetConfirmation = true
                }
                .accessibilityIdentifier("reset-all-settings-button")
            } footer: {
                Text("Restores every preference to its default, including your recent languages.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .accessibilityIdentifier("settings-general-pane")
        .confirmationDialog(
            "Reset all settings to their defaults?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
                // `resetToDefaults()` clears the persisted preset blob too (its key
                // is in `SettingsCodec.Keys.all`); reload so this store's in-memory
                // copy reflects the cleared state.
                presets.reload()
                launchAtLogin = LaunchAtLogin.isEnabled
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Your recent languages and saved presets are also cleared.")
        }
    }
}

/// An editor for the selected-line highlight spec (CS-021).
///
/// The user types a compact spec like `3, 7-9, 12`; on every change it is parsed
/// into normalized 1-based inclusive ranges and pushed into `config`. The text the
/// user is typing is kept in local state (not re-derived from the parsed result on
/// each keystroke), so an in-progress entry such as `7-` is not rewritten out from
/// under the caret; the field is re-canonicalized from the config only when it
/// first appears or the config changes underneath it (e.g. a reset).
struct HighlightedLinesField: View {
    @ObservedObject var settings: AppSettings
    @State private var text: String = ""

    var body: some View {
        // No explicit textFieldStyle: inside a grouped Form the row supplies its
        // own inset chrome, so the field matches the sibling Toggle/Picker/Slider
        // rows. Forcing `.roundedBorder` here would double-bezel it (HIG).
        TextField("Highlight lines", text: $text, prompt: Text("e.g. 3, 7-9, 12"))
            .help("Lines or ranges to highlight, e.g. 3, 7-9, 12")
            // Match the visible row label so VoiceOver and the title agree.
            .accessibilityLabel("Highlight lines")
            .accessibilityIdentifier("highlight-lines-field")
            .onAppear { text = LineHighlight.describe(settings.config.highlightedLineRanges) }
            .onChange(of: text) { _, newValue in
                let parsed = LineHighlight.parse(newValue)
                if parsed != settings.config.highlightedLineRanges {
                    settings.config.highlightedLineRanges = parsed
                }
            }
            // Re-seed from the config when it changes elsewhere (e.g. Reset All
            // Settings) so the field never shows stale text.
            .onChange(of: settings.config.highlightedLineRanges) { _, newValue in
                let canonical = LineHighlight.describe(newValue)
                if LineHighlight.parse(text) != newValue { text = canonical }
            }
    }
}

/// Editors for the optional metadata header — filename, title, caption, and a
/// language-badge toggle (CS-022).
///
/// Each text field maps to an optional `SnapshotMetadata` field through a binding
/// that normalizes on the way in (trim, empty → `nil`), so a blank entry never
/// reserves header space. The fields are reused by both the Style pane and the
/// editor's inline metadata bar so there is one labeled, accessible set of
/// controls. Every control carries an explicit accessibility label and identifier
/// (CS-022 acceptance).
struct MetadataFields: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Group {
            TextField("Filename", text: filenameBinding, prompt: Text("e.g. ContentView.swift"))
                .help("Optional filename shown as a chip in the header")
                .accessibilityLabel("Filename")
                .accessibilityIdentifier("metadata-filename-field")

            TextField("Title", text: titleBinding, prompt: Text("e.g. Aurora gradient"))
                .help("Optional title shown above the code")
                .accessibilityLabel("Title")
                .accessibilityIdentifier("metadata-title-field")

            TextField("Caption", text: captionBinding, prompt: Text("e.g. A SwiftUI gradient"))
                .help("Optional one-line caption shown under the title")
                .accessibilityLabel("Caption")
                .accessibilityIdentifier("metadata-caption-field")

            Toggle("Language badge", isOn: $settings.config.metadata.showLanguageBadge)
                .help("Show the current language as a badge in the header")
                .accessibilityLabel("Language badge")
                .accessibilityIdentifier("metadata-language-badge-toggle")
        }
    }

    private var filenameBinding: Binding<String> {
        field(\.filename)
    }

    private var titleBinding: Binding<String> {
        field(\.title)
    }

    private var captionBinding: Binding<String> {
        field(\.caption)
    }

    /// A `String` binding over one optional metadata field: reads `nil` as the
    /// empty string and writes a normalized value back (empty/whitespace → `nil`),
    /// so the live config and the field stay in sync without ever storing a blank.
    private func field(_ keyPath: WritableKeyPath<SnapshotMetadata, String?>) -> Binding<String> {
        Binding(
            get: { settings.config.metadata[keyPath: keyPath] ?? "" },
            set: { settings.config.metadata[keyPath: keyPath] = SnapshotMetadata.normalized($0) }
        )
    }
}

/// The core style controls — theme, font, ligatures, padding, font size, window
/// chrome, and drop shadow — as one reusable, labeled cluster (CS-006/052).
///
/// Extracted so the Style settings pane and the editor's inspector (CS-037) share
/// a single accessible set of controls instead of each spelling out (and drifting
/// on) the same pickers, sliders, and toggles. It draws plain rows with no
/// `Section`/`Form` chrome of its own, so a host can drop it inside whichever
/// container it already uses — a grouped `Form` section in Settings, or the
/// inspector's disclosure group — and the row chrome comes from that host.
///
/// The theme picker resolves ids through `CustomThemeStore` so a custom theme
/// (CS-031) round-trips, and the ligature toggle gates itself on whether the
/// selected font actually ships ligatures (CS-052).
struct CoreStyleControls: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var themes: CustomThemeStore

    var body: some View {
        Picker("Theme", selection: themeBinding) {
            Section("Built-in") {
                ForEach(Theme.builtIns) { theme in
                    Text(theme.displayName).tag(theme.id)
                }
            }
            if !themes.customThemes.isEmpty {
                Section("Custom") {
                    ForEach(themes.customThemes) { theme in
                        Text(theme.displayName).tag(theme.id)
                    }
                }
            }
        }
        .help("Choose a built-in or custom syntax theme.")
        .accessibilityIdentifier("style-theme-picker")

        Picker("Font", selection: $settings.config.fontName) {
            ForEach(CodeFont.all, id: \.self) { font in
                Text(font).tag(font)
            }
        }
        .accessibilityIdentifier("style-font-picker")

        Toggle("Ligatures", isOn: $settings.config.fontLigatures)
            .help(ligatureHelp)
            .disabled(!fontHasLigatures)
            .accessibilityIdentifier("ligatures-toggle")

        Slider(value: $settings.config.padding, in: 16...64, step: 4) { Text("Padding") }
            .accessibilityIdentifier("padding-slider")
        Slider(value: $settings.config.fontSize, in: 10...20, step: 1) { Text("Font size") }
            .accessibilityIdentifier("font-size-slider")

        Toggle("Window chrome", isOn: $settings.config.showChrome)
            .accessibilityIdentifier("window-chrome-toggle")
        Toggle("Drop shadow", isOn: $settings.config.showShadow)
            .accessibilityIdentifier("drop-shadow-toggle")
    }

    private var themeBinding: Binding<String> {
        Binding(
            get: { settings.config.theme.id },
            // Resolve through the store so a custom theme id (CS-031) maps to its
            // palette-backed theme; a built-in or unknown id falls back to the
            // built-in lookup.
            set: { settings.config.theme = themes.theme(withID: $0) }
        )
    }

    /// Whether the selected font ships programming ligatures, gating the toggle so
    /// it reads as inert for a font that has none (CS-052).
    private var fontHasLigatures: Bool {
        CodeFont.hasLigatures(settings.config.fontName)
    }

    private var ligatureHelp: String {
        fontHasLigatures
            ? "Render programming ligatures (->, =>, !=) for this font."
            : "The selected font has no ligatures; choose Fira Code or JetBrains Mono."
    }
}

/// The save/apply/import/export controls for named style presets (CS-030).
///
/// Built-ins lead the picker and are immutable: the contextual action for a
/// built-in is "Duplicate", never rename or delete. A user preset can be renamed
/// and deleted. "Save current style…" captures the live presentation (never the
/// code) under a name the user types; Import/Export move presets as JSON files
/// through the existing user-selected file-access entitlement.
struct StylePresetsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: PresetStore

    /// The preset id selected in the picker, or `nil` before the user picks one.
    /// This is a selection cursor for the row actions, not an applied-state mirror;
    /// applying is an explicit button so a preset never silently overwrites the
    /// live style on selection.
    @State private var selectedID: String?
    @State private var showSavePrompt = false
    @State private var saveName = ""
    @State private var showRenamePrompt = false
    @State private var renameName = ""
    @State private var importErrorMessage: String?
    @State private var importSuccessMessage: String?

    /// Sentinel tag for the "no selection" row.
    private static let noneTag = "__none__"

    var body: some View {
        Section {
            Picker("Preset", selection: pickerBinding) {
                Text("Choose a preset…").tag(Self.noneTag)
                Section("Built-in") {
                    ForEach(StylePreset.builtIns) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                if !store.userPresets.isEmpty {
                    Section("Saved") {
                        ForEach(store.userPresets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                }
            }
            .help(
                "Choose a preset to apply, duplicate, rename, or delete. Selecting does not change your current style."
            )
            .accessibilityIdentifier("style-preset-picker")

            presetRowActions

            HStack {
                Button("Save Current Style…") {
                    saveName = settings.config.theme.displayName
                    showSavePrompt = true
                }
                .help("Save the current style as a new named preset you can reuse.")
                .accessibilityIdentifier("save-style-preset-button")

                Spacer()

                Button("Import…") { runImport() }
                    .help("Add presets from a Vitrine preset file (.json).")
                    .accessibilityIdentifier("import-presets-button")
                Button("Export…") {
                    PresetFileExchange.exportWithSavePanel(store: store)
                }
                .disabled(store.userPresets.isEmpty)
                .help(
                    store.userPresets.isEmpty
                        ? "Save a preset first to export your presets."
                        : "Export your saved presets to a JSON file."
                )
                .accessibilityIdentifier("export-presets-button")
            }
        } header: {
            Text("Presets")
        } footer: {
            presetFooter
        }
        .alert("Save Preset", isPresented: $showSavePrompt) {
            TextField("Name", text: $saveName)
                .accessibilityIdentifier("save-style-preset-name-field")
            Button("Save") { saveCurrentStyle() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Save the current style — theme, font, background, and the rest of your current layout — as a named preset."
            )
        }
        .alert("Rename Preset", isPresented: $showRenamePrompt) {
            TextField("Name", text: $renameName)
                .accessibilityIdentifier("rename-style-preset-name-field")
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Import Presets",
            isPresented: Binding(
                get: { importErrorMessage != nil }, set: { if !$0 { importErrorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
        .alert(
            "Presets Imported",
            isPresented: Binding(
                get: { importSuccessMessage != nil },
                set: { if !$0 { importSuccessMessage = nil } })
        ) {
            Button("OK", role: .cancel) { importSuccessMessage = nil }
        } message: {
            Text(importSuccessMessage ?? "")
        }
    }

    /// The Apply / Duplicate / Rename / Delete row for the selected preset.
    ///
    /// The row is always present and reads as a labeled form row ("Selected
    /// preset") so the section's layout and semantics stay steady rather than
    /// appearing and disappearing as the selection changes (HIG: controls in a
    /// grouped form should read as labeled rows). With nothing selected the
    /// buttons are disabled; the destructive Rename/Delete pair stays disabled —
    /// not hidden — for an immutable built-in, so the available actions read as a
    /// stable set the user can see but not invoke.
    private var presetRowActions: some View {
        let preset = selectedPreset
        let canEdit = preset.map { !$0.isBuiltIn } ?? false
        return LabeledContent("Selected preset") {
            HStack {
                Button("Apply") {
                    if let preset { settings.applyStylePreset(preset) }
                }
                .help("Apply this preset's style to the current snapshot.")
                .disabled(preset == nil)
                .accessibilityIdentifier("apply-style-preset-button")
                Button("Duplicate") {
                    if let preset { selectedID = store.duplicate(preset).id }
                }
                .help("Make an editable copy of this preset.")
                .disabled(preset == nil)
                .accessibilityIdentifier("duplicate-style-preset-button")

                Spacer()

                Button("Rename") {
                    if let preset {
                        renameName = preset.name
                        showRenamePrompt = true
                    }
                }
                .help("Rename this saved preset. Built-in presets can't be renamed.")
                .disabled(!canEdit)
                .accessibilityIdentifier("rename-style-preset-button")
                Button("Delete", role: .destructive) {
                    if let preset {
                        store.delete(id: preset.id)
                        selectedID = nil
                    }
                }
                .help("Delete this saved preset. Built-in presets can't be deleted.")
                .disabled(!canEdit)
                .accessibilityIdentifier("delete-style-preset-button")
            }
        }
    }

    @ViewBuilder private var presetFooter: some View {
        if let preset = selectedPreset, preset.isBuiltIn {
            Text("Built-in presets can't be changed — duplicate one to make it your own.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("Save the current style as a preset, then export or import presets as JSON.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// The currently selected preset, resolved across built-ins and user presets.
    private var selectedPreset: StylePreset? {
        guard let selectedID else { return nil }
        return store.preset(withID: selectedID)
    }

    private var pickerBinding: Binding<String> {
        Binding(
            get: { selectedID ?? Self.noneTag },
            set: { selectedID = $0 == Self.noneTag ? nil : $0 }
        )
    }

    private func saveCurrentStyle() {
        let preset = store.savePreset(named: saveName, from: settings.config)
        selectedID = preset.id
    }

    private func commitRename() {
        guard let id = selectedID else { return }
        store.rename(id: id, to: renameName)
    }

    private func runImport() {
        do {
            let count = try PresetFileExchange.importWithOpenPanel(store: store)
            if count > 0 {
                // Count-aware and localized: the String Catalog carries singular
                // and plural variants per locale, and the count is formatted for the
                // user's locale (CS-047).
                importSuccessMessage = String(localized: "Added \(count) presets")
            }
        } catch let error as StylePresetDocument.ImportError {
            importErrorMessage = error.message
        } catch {
            importErrorMessage = "This preset file could not be imported."
        }
    }
}

/// Style pane: theme, background, padding, font, chrome, shadow + live preview (CS-006/010).
struct StyleSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var presets: PresetStore
    @ObservedObject var themes: CustomThemeStore

    var body: some View {
        Form {
            Section {
                DestinationPresetPicker(settings: settings)
            } footer: {
                Text("A destination preset sizes and styles the image for a place to post it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            StylePresetsSection(settings: settings, store: presets)

            Section {
                CoreStyleControls(settings: settings, themes: themes)
            }

            CustomThemesSection(settings: settings, store: themes)

            Section {
                Toggle("Line numbers", isOn: $settings.config.showLineNumbers)
                    .accessibilityIdentifier("line-numbers-toggle")
                HighlightedLinesField(settings: settings)
            } header: {
                Text("Lines")
            } footer: {
                Text("Show a line-number gutter and highlight specific lines or ranges.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                MetadataFields(settings: settings)
            } header: {
                Text("Header")
            } footer: {
                Text("Add an optional filename, title, caption, or language badge above the code.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Background") {
                BackgroundEditor(background: $settings.config.background)
            }

            Section("Preview") {
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 300)
                        .clipShape(
                            RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                        )
                        .brandShadow(Brand.Shadow.card)
                        .help("Live preview of the current style")
                        .accessibilityLabel("Live preview")
                        .accessibilityIdentifier("settings-style-preview")
                } else {
                    previewPlaceholder
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
        .accessibilityIdentifier("settings-style-pane")
    }

    /// Config used for the preview — falls back to a sample snippet when the editor
    /// has no code yet, so the preview is always meaningful.
    private var previewConfig: SnapshotConfig {
        var config = settings.config
        if config.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.code = "func greet(_ name: String) {\n    print(\"Hello, \\(name)!\")\n}"
        }
        return config
    }

    private var previewImage: NSImage? {
        // Reflect a fixed-size preset's exact framing (e.g. OpenGraph 1200×630)
        // in the live preview; scale stays at 2 for a crisp thumbnail since the
        // image is scaled to fit the preview box (CS-020).
        ExportManager.renderNSImage(
            previewConfig, scale: 2, fixedSize: settings.effectiveFixedSize,
            profile: settings.colorProfile)
    }

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

/// The create/apply/rename/delete/import/export controls for custom themes (CS-031).
///
/// A custom theme is a user-defined syntax palette (the documented schema in
/// `ThemePalette`). New and Edit open `CustomThemeEditor`, which shows a live preview
/// before saving; Import/Export move themes as JSON files through the existing
/// user-selected file-access entitlement, surfacing a clear validation error for a
/// bad color or missing key. Built-in themes are never listed here — they are
/// immutable and managed by the Theme picker above.
struct CustomThemesSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: CustomThemeStore

    /// The custom theme id selected for management, or `nil` before the user picks.
    @State private var selectedID: String?
    @State private var editorDraft: CustomThemeDraft?
    @State private var showRenamePrompt = false
    @State private var renameName = ""
    @State private var importErrorMessage: String?
    @State private var importSuccessMessage: String?

    private static let noneTag = "__none__"

    var body: some View {
        Section {
            if store.customThemes.isEmpty {
                Text("No custom themes yet. Create one, or import a theme file.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Custom theme", selection: pickerBinding) {
                    Text("Choose a theme…").tag(Self.noneTag)
                    ForEach(store.customThemes) { theme in
                        Text(theme.displayName).tag(theme.id)
                    }
                }
                .accessibilityIdentifier("custom-theme-picker")

                rowActions
            }

            HStack {
                Button("New Theme…") { editorDraft = CustomThemeDraft() }
                    .help("Create a custom syntax theme with a live preview.")
                    .accessibilityIdentifier("new-custom-theme-button")

                Spacer()

                Button("Import…") { runImport() }
                    .help("Add custom themes from a Vitrine theme file (.json).")
                    .accessibilityIdentifier("import-themes-button")
                Button("Export…") {
                    CustomThemeFileExchange.exportWithSavePanel(store: store)
                }
                .disabled(store.customThemes.isEmpty)
                .help(
                    store.customThemes.isEmpty
                        ? "Create a theme first to export your themes."
                        : "Export your custom themes to a JSON file."
                )
                .accessibilityIdentifier("export-themes-button")
            }
        } header: {
            Text("Custom Themes")
        } footer: {
            Text(
                "Custom themes are your own syntax palettes. Built-in themes can't be changed. Theme files are JSON and never leave your Mac."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .sheet(item: $editorDraft) { draft in
            CustomThemeEditor(
                settings: settings, draft: draft,
                onSave: { name, palette in
                    if let id = draft.editingID {
                        store.rename(id: id, to: name)
                        // Re-create the palette by deleting and re-adding keeps the
                        // store's value-typed contract simple; preserve selection.
                        store.delete(id: id)
                    }
                    let saved = store.addTheme(named: name, palette: palette)
                    selectedID = saved.id
                    // Apply the just-saved theme so the editor's preview matches the
                    // live canvas immediately.
                    settings.config.theme = store.theme(withID: saved.id)
                    editorDraft = nil
                },
                onCancel: { editorDraft = nil })
        }
        .alert("Rename Theme", isPresented: $showRenamePrompt) {
            TextField("Name", text: $renameName)
                .accessibilityIdentifier("rename-custom-theme-name-field")
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Import Themes",
            isPresented: Binding(
                get: { importErrorMessage != nil }, set: { if !$0 { importErrorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
        .alert(
            "Themes Imported",
            isPresented: Binding(
                get: { importSuccessMessage != nil },
                set: { if !$0 { importSuccessMessage = nil } })
        ) {
            Button("OK", role: .cancel) { importSuccessMessage = nil }
        } message: {
            Text(importSuccessMessage ?? "")
        }
    }

    /// Apply / Edit / Rename / Delete for the selected custom theme.
    private var rowActions: some View {
        let theme = selectedTheme
        return LabeledContent("Selected theme") {
            HStack {
                Button("Apply") {
                    if let theme { settings.config.theme = store.theme(withID: theme.id) }
                }
                .help("Use this custom theme for the current snapshot.")
                .disabled(theme == nil)
                .accessibilityIdentifier("apply-custom-theme-button")
                Button("Edit…") {
                    if let theme, let palette = theme.palette {
                        editorDraft = CustomThemeDraft(
                            editingID: theme.id, name: theme.displayName, palette: palette)
                    }
                }
                .help("Edit this custom theme's colors with a live preview.")
                .disabled(theme == nil)
                .accessibilityIdentifier("edit-custom-theme-button")

                Spacer()

                Button("Rename") {
                    if let theme {
                        renameName = theme.displayName
                        showRenamePrompt = true
                    }
                }
                .help("Rename this custom theme.")
                .disabled(theme == nil)
                .accessibilityIdentifier("rename-custom-theme-button")
                Button("Delete", role: .destructive) {
                    if let theme {
                        store.delete(id: theme.id)
                        selectedID = nil
                    }
                }
                .help("Delete this custom theme.")
                .disabled(theme == nil)
                .accessibilityIdentifier("delete-custom-theme-button")
            }
        }
    }

    private var selectedTheme: Theme? {
        guard let selectedID else { return nil }
        return store.customThemes.first { $0.id == selectedID }
    }

    private var pickerBinding: Binding<String> {
        Binding(
            get: { selectedID ?? Self.noneTag },
            set: { selectedID = $0 == Self.noneTag ? nil : $0 }
        )
    }

    private func commitRename() {
        guard let id = selectedID else { return }
        store.rename(id: id, to: renameName)
    }

    private func runImport() {
        do {
            let count = try CustomThemeFileExchange.importWithOpenPanel(store: store)
            if count > 0 {
                // Count-aware, localized, locale-formatted number (CS-047).
                importSuccessMessage = String(localized: "Added \(count) themes")
            }
        } catch let error as CustomThemeDocument.ImportError {
            importErrorMessage = error.message
        } catch {
            importErrorMessage = "This theme file could not be imported."
        }
    }
}

/// A mutable, `Color`-backed draft of a custom-theme palette, used by
/// `CustomThemeEditor` so the color wells bind to live SwiftUI colors and the
/// preview updates as the user edits (CS-031).
///
/// It is `Identifiable` so it can drive a `.sheet(item:)`, and carries an optional
/// `editingID` so the same editor handles both "new" and "edit an existing theme".
/// The draft is the editable form; `palette()` resolves it back to a validated
/// `ThemePalette` for saving.
final class CustomThemeDraft: Identifiable, ObservableObject {
    let id = UUID()
    /// The id of the theme being edited, or `nil` when creating a new one.
    let editingID: String?
    @Published var name: String
    @Published var background: Color
    @Published var foreground: Color
    @Published var keyword: Color
    @Published var string: Color
    @Published var comment: Color
    @Published var number: Color
    @Published var type: Color
    @Published var function: Color
    @Published var variable: Color
    @Published var attribute: Color

    /// A new draft seeded with a clean, legible dark default palette so the editor
    /// opens on a sensible starting point rather than all-black wells.
    init() {
        self.editingID = nil
        self.name = "My Theme"
        self.background = Color(hex: "#1E1E1E")
        self.foreground = Color(hex: "#D4D4D4")
        self.keyword = Color(hex: "#C586C0")
        self.string = Color(hex: "#CE9178")
        self.comment = Color(hex: "#6A9955")
        self.number = Color(hex: "#B5CEA8")
        self.type = Color(hex: "#4EC9B0")
        self.function = Color(hex: "#DCDCAA")
        self.variable = Color(hex: "#9CDCFE")
        self.attribute = Color(hex: "#569CD6")
    }

    /// A draft seeded from an existing theme's palette for editing.
    init(editingID: String, name: String, palette: ThemePalette) {
        self.editingID = editingID
        self.name = name
        self.background = palette.background.color
        self.foreground = palette.foreground.color
        self.keyword = palette.keyword.color
        self.string = palette.string.color
        self.comment = palette.comment.color
        self.number = palette.number.color
        self.type = palette.type.color
        self.function = palette.function.color
        self.variable = palette.variable.color
        self.attribute = palette.attribute.color
    }

    /// Resolves the draft to a validated `ThemePalette`. Each `Color` is captured in
    /// fixed sRGB and round-tripped through `HexColor`, so the saved palette is the
    /// same deterministic value the file schema stores.
    func palette() -> ThemePalette {
        ThemePalette(
            background: background.hexColor,
            foreground: foreground.hexColor,
            keyword: keyword.hexColor,
            string: string.hexColor,
            comment: comment.hexColor,
            number: number.hexColor,
            type: type.hexColor,
            function: function.hexColor,
            variable: variable.hexColor,
            attribute: attribute.hexColor)
    }
}

/// A sheet for creating or editing a custom theme with a live preview before saving
/// (CS-031 "theme preview appears before saving").
///
/// The color wells edit a `CustomThemeDraft`; the preview re-renders the current
/// code (or a sample snippet) with the draft palette on every change, so the user
/// sees the exact syntax coloring before committing. Saving resolves the draft to a
/// validated `ThemePalette` and hands it to the store.
struct CustomThemeEditor: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var draft: CustomThemeDraft
    let onSave: (String, ThemePalette) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            Text(draft.editingID == nil ? "New Custom Theme" : "Edit Custom Theme")
                .font(.headline)

            // The form and preview scroll; the title above and the action row below
            // stay pinned so Cancel/Save are always reachable. This mirrors the
            // AboutSettingsView fix (a ScrollView with a minHeight) so the editor
            // grows and scrolls at large Dynamic Type sizes instead of clipping the
            // controls or the action buttons.
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.md) {
                    Form {
                        TextField("Name", text: $draft.name)
                            .accessibilityIdentifier("custom-theme-name-field")

                        Section("Base") {
                            ColorPicker(
                                "Background", selection: $draft.background, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-background")
                            ColorPicker(
                                "Foreground", selection: $draft.foreground, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-foreground")
                        }
                        Section("Syntax") {
                            ColorPicker(
                                "Keywords", selection: $draft.keyword, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-keyword")
                            ColorPicker("Strings", selection: $draft.string, supportsOpacity: false)
                                .accessibilityIdentifier("custom-theme-color-string")
                            ColorPicker(
                                "Comments", selection: $draft.comment, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-comment")
                            ColorPicker("Numbers", selection: $draft.number, supportsOpacity: false)
                                .accessibilityIdentifier("custom-theme-color-number")
                            ColorPicker("Types", selection: $draft.type, supportsOpacity: false)
                                .accessibilityIdentifier("custom-theme-color-type")
                            ColorPicker(
                                "Functions", selection: $draft.function, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-function")
                            ColorPicker(
                                "Variables", selection: $draft.variable, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-variable")
                            ColorPicker(
                                "Attributes", selection: $draft.attribute, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-attribute")
                        }
                    }
                    .formStyle(.grouped)
                    .frame(minHeight: 280)

                    Text("Preview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    previewImage
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 160)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(draft.name, draft.palette())
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("save-custom-theme-button")
            }
        }
        .padding()
        .frame(width: 460)
        .frame(minHeight: 520)
        .accessibilityIdentifier("custom-theme-editor")
    }

    /// The live preview: the current code (or a sample) rendered with the draft
    /// palette, so the syntax coloring is visible before saving.
    @ViewBuilder private var previewImage: some View {
        if let image = renderedPreview {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
                .accessibilityIdentifier("custom-theme-preview")
        } else {
            RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                .fill(draft.background)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                        .strokeBorder(Brand.Palette.border.color)
                )
                .overlay(
                    Text("Preview unavailable")
                        .font(.footnote)
                        // The fill is the user-chosen draft background, so the label
                        // must read against *that* color, not the app's appearance:
                        // `.secondary` resolves to the environment scheme and goes
                        // invisible on a light draft in Dark Mode (or the inverse).
                        // The draft's own foreground is the color picked to sit on
                        // this background, so it stays legible for any draft palette.
                        .foregroundStyle(draft.foreground)
                )
                .accessibilityIdentifier("custom-theme-preview-unavailable")
        }
    }

    private var renderedPreview: NSImage? {
        var config = settings.config
        config.theme = Theme(
            id: "custom.preview", displayName: draft.name, palette: draft.palette())
        if config.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.code = "func greet(_ name: String) {\n    print(\"Hello, \\(name)!\")\n}"
        }
        return ExportManager.renderNSImage(config, scale: 2, profile: settings.colorProfile)
    }
}

/// Output pane: clipboard/save behavior, resolution, format (CS-010).
struct OutputSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                DestinationPresetPicker(settings: settings)
            } footer: {
                Text("Presets set the image size and resolution for a destination.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Copy to clipboard automatically", isOn: $settings.autoCopy)
                Toggle("Also save to a file", isOn: $settings.alsoSaveToFile)

                Picker("Resolution", selection: $settings.exportScale) {
                    Text("1×").tag(1)
                    Text("2× (Retina)").tag(2)
                    Text("3×").tag(3)
                }
                .accessibilityIdentifier("output-resolution-picker")

                Picker("Format", selection: $settings.exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .accessibilityIdentifier("output-format-picker")
            } footer: {
                // State honestly which output is vector: PDF is the supported
                // scalable format; PNG is raster (CS-023).
                Text(settings.exportFormat.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Rich clipboard is opt-in so the default copy stays a plain image; the
            // explicit "Copy as Data URI" and "Copy Highlighted Code" actions in the
            // editor remain available regardless of this toggle (CS-054).
            Section {
                Toggle("Add highlighted code as rich text", isOn: $settings.richClipboard)
                    .accessibilityIdentifier("rich-clipboard-toggle")
            } header: {
                Text("Clipboard")
            } footer: {
                Text(
                    "When on, Copy also places the highlighted code as rich text, so pasting into a document keeps the colors and font. The image is always included."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            // Color management lives in its own "Advanced" section so the default
            // (sRGB) stays the obvious choice and Display P3 reads as a deliberate
            // opt-in (CS-024).
            Section {
                Picker("Color profile", selection: $settings.colorProfile) {
                    ForEach(ColorProfile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .accessibilityIdentifier("color-profile-picker")
            } header: {
                Text("Advanced")
            } footer: {
                Text(settings.colorProfile.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .accessibilityIdentifier("settings-output-pane")
    }
}

/// Input pane: URL handling (CS-010 · Input) and the web URL-capture viewport and
/// wait strategy (CS-044).
struct InputSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Treat copied URLs as a screenshot target",
                    isOn: $settings.treatURLsAsScreenshot)
            } footer: {
                Text(
                    "When off, a copied URL is rendered as text. URL screenshots arrive in Product Phase 2."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            WebCaptureControls(settings: settings)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
        .accessibilityIdentifier("settings-input-pane")
    }
}

/// The web URL-capture viewport, capture mode, and wait-strategy controls (CS-044).
///
/// URL capture is a Product Phase 2 feature gated on the network entitlement, so
/// these controls set the policy a future URL capture will use; the footer states
/// that plainly. Choosing the viewport, the visible-vs-full-page mode, and the wait
/// strategy here is what makes a web screenshot predictable across sites. The
/// width/height fields appear only for a custom viewport, and the seconds field only
/// for a timed wait strategy, so the surface stays as small as the chosen options.
struct WebCaptureControls: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Section {
            Picker("Viewport", selection: $settings.webViewportKind) {
                ForEach(WebSnapshotConfig.ViewportPreset.Kind.allCases, id: \.self) { kind in
                    Text(viewportLabel(for: kind)).tag(kind)
                }
            }
            .accessibilityIdentifier("web-viewport-picker")

            if settings.webViewportKind == .custom {
                Stepper(
                    value: $settings.webCustomViewportWidth,
                    in: customDimensionRange, step: 10
                ) {
                    LabeledContent("Width", value: "\(settings.webCustomViewportWidth) pt")
                }
                .accessibilityIdentifier("web-custom-width-stepper")

                Stepper(
                    value: $settings.webCustomViewportHeight,
                    in: customDimensionRange, step: 10
                ) {
                    LabeledContent("Height", value: "\(settings.webCustomViewportHeight) pt")
                }
                .accessibilityIdentifier("web-custom-height-stepper")
            }

            Picker("Capture", selection: $settings.webCaptureMode) {
                ForEach(WebSnapshotConfig.CaptureMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .accessibilityIdentifier("web-capture-mode-picker")
        } header: {
            Text("Web capture (Product Phase 2)")
        } footer: {
            Text(captureFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section {
            Picker("Wait until", selection: $settings.webWaitKind) {
                ForEach(WebSnapshotConfig.WaitStrategy.Kind.allCases, id: \.self) { kind in
                    Text(waitLabel(for: kind)).tag(kind)
                }
            }
            .accessibilityIdentifier("web-wait-strategy-picker")

            if settings.webWaitKind != .domContentLoaded {
                Stepper(
                    value: $settings.webWaitSeconds,
                    in: waitSecondsRange, step: 1
                ) {
                    LabeledContent("Extra wait", value: waitSecondsLabel)
                }
                .accessibilityIdentifier("web-wait-seconds-stepper")
            }
        } footer: {
            Text(waitFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// The picker label for a viewport kind. The custom row reads "Custom…" rather
    /// than echoing the stored size, because the size is set by the fields below it.
    private func viewportLabel(for kind: WebSnapshotConfig.ViewportPreset.Kind) -> String {
        switch kind {
        case .openGraph: WebSnapshotConfig.ViewportPreset.openGraph.displayName
        case .desktop: WebSnapshotConfig.ViewportPreset.desktop.displayName
        case .fullHD: WebSnapshotConfig.ViewportPreset.fullHD.displayName
        case .mobile: WebSnapshotConfig.ViewportPreset.mobile.displayName
        case .custom: String(localized: "Custom…")
        }
    }

    /// The picker label for a wait-strategy kind, derived from a representative value
    /// of that kind so the picker and the engine share one set of names.
    private func waitLabel(for kind: WebSnapshotConfig.WaitStrategy.Kind) -> String {
        switch kind {
        case .domContentLoaded: WebSnapshotConfig.WaitStrategy.domContentLoaded.displayName
        case .fixedDelay: WebSnapshotConfig.WaitStrategy.fixedDelay(.zero).displayName
        case .networkQuiet: WebSnapshotConfig.WaitStrategy.networkQuiet(budget: .zero).displayName
        }
    }

    private var waitSecondsLabel: String {
        // One interpolated key whose singular/plural is chosen by the catalog's
        // plural variations (CS-047), rather than a Swift `== 1` branch — so every
        // locale's own plural categories are honored, not just one/other.
        String(localized: "\(settings.webWaitSeconds) seconds")
    }

    private var captureFooter: String {
        switch settings.webCaptureMode {
        case .visibleViewport:
            String(
                localized:
                    "Captures exactly the viewport size. URL capture loads the page locally in WebKit and arrives in Product Phase 2."
            )
        case .fullPage:
            String(
                localized:
                    "Captures the whole page at the viewport width, down to a bounded maximum height. Lazy-loaded content is given a chance to appear by scrolling the page a limited number of times."
            )
        }
    }

    private var waitFooter: String {
        switch settings.webWaitKind {
        case .domContentLoaded:
            String(localized: "Snapshots as soon as the page finishes loading.")
        case .fixedDelay:
            String(
                localized:
                    "Waits a fixed time after the page loads before snapshotting, so content added by scripts has time to appear."
            )
        case .networkQuiet:
            String(
                localized:
                    "Waits, up to the chosen time, for the page to stop loading content before snapshotting. Best effort: a page that never goes quiet is captured when the time runs out."
            )
        }
    }

    private var customDimensionRange: ClosedRange<Int> {
        WebSnapshotConfig.ViewportPreset.customDimensionRange
    }

    private var waitSecondsRange: ClosedRange<Int> { WebDefaults.waitSecondsRange }
}

/// About pane: version, links, copyright (CS-010), and a privacy-safe diagnostics
/// export for bug reports (CS-048).
struct AboutSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(spacing: Brand.Spacing.sm) {
                // Identity cluster: who/what the app is.
                BrandMark(size: 48)
                Text(verbatim: "Vitrine").font(.title.bold())
                // The version line's template is localized through the catalog
                // (CS-047); the version value itself is a semver, inserted verbatim.
                Text("Version \(appVersion)").foregroundStyle(.secondary)
                Text("Turn code into beautiful images, from your menu bar.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Link("GitHub", destination: URL(string: "https://github.com/johnny4young/vitrine")!)

                // Separate the interactive action from the identity/informational
                // text above so it does not read as just another line of copy.
                Divider().padding(.vertical, Brand.Spacing.xs)

                Button("Export Diagnostics…") {
                    DiagnosticsExporter.exportWithSavePanel(settings: settings)
                }
                .accessibilityIdentifier("export-diagnostics-button")
                .help(
                    "Save a privacy-safe report (no code or clipboard contents) to a file you choose."
                )

                // A stable legal/brand string, shown verbatim like the "Vitrine"
                // wordmark above so it bypasses the String Catalog (CS-047).
                Text(verbatim: "© 2026 johnny4young · MIT")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(Brand.Spacing.xl)
        }
        // A minimum height keeps the default layout looking the same, while letting
        // the pane grow (and the ScrollView scroll) at larger Dynamic Type sizes
        // instead of clipping the button/copyright.
        .frame(width: 460)
        .frame(minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("settings-about-pane")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
