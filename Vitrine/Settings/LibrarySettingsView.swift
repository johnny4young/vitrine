import SwiftUI

/// Library pane (CS-010): the reusable save-and-manage surfaces split out of the Style
/// pane so neither grows an exaggerated height — saved **style presets** (CS-030) and
/// user **custom themes** (CS-031). Each renders its own section(s), hosted in one Form.
struct LibrarySettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var presets: PresetStore
    @ObservedObject var themes: CustomThemeStore

    var body: some View {
        SettingsPaneScroll {
            StylePresetsSection(settings: settings, store: presets)
            CustomThemesSection(settings: settings, store: themes)
        }
        .accessibilityIdentifier("settings-library-pane")
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
        TokenGroup(title: Text("Presets")) {
            TokenRow(
                label: Text("Preset"),
                caption: Text("Apply a saved style in one click")
            ) {
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
                .labelsHidden()
                .fixedSize()
                .help(
                    "Choose a preset to apply, duplicate, rename, or delete. Selecting does not change your current style."
                )
                .accessibilityLabel("Preset")
                .accessibilityIdentifier("style-preset-picker")
            }

            TokenRow(
                label: Text("Selected preset"),
                caption: Text("Save the current style, then export or import as JSON")
            ) {
                HStack(spacing: VitrineTokens.Spacing.xs) {
                    Button("Save Current Style…") {
                        saveName = settings.config.theme.displayName
                        showSavePrompt = true
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Save the current style as a new named preset you can reuse.")
                    .accessibilityIdentifier("save-style-preset-button")

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
                .buttonStyle(.bordered)
                .fixedSize()
            }

            presetRowActions
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
    /// The row is always present so the group's layout and semantics stay
    /// steady rather than appearing and disappearing as the selection changes.
    /// With nothing selected the buttons are disabled; the destructive
    /// Rename/Delete pair stays disabled — not hidden — for an immutable
    /// built-in, so the available actions read as a stable set the user can
    /// see but not invoke.
    private var presetRowActions: some View {
        let preset = selectedPreset
        let canEdit = preset.map { !$0.isBuiltIn } ?? false
        return TokenRow {
            HStack(spacing: VitrineTokens.Spacing.xs) {
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
            .buttonStyle(.bordered)
            .fixedSize()
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
        TokenGroup(title: Text("Custom themes")) {
            if store.customThemes.isEmpty {
                TokenRow(
                    label: Text("No custom themes yet"),
                    caption: Text("Theme files are JSON and never leave your Mac")
                ) {
                    themeActionButtons
                }
            } else {
                TokenRow(label: Text("Custom theme")) {
                    Picker("Custom theme", selection: pickerBinding) {
                        Text("Choose a theme…").tag(Self.noneTag)
                        ForEach(store.customThemes) { theme in
                            Text(theme.displayName).tag(theme.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Custom theme")
                    .accessibilityIdentifier("custom-theme-picker")
                }

                rowActions

                TokenRow(caption: Text("Theme files are JSON and never leave your Mac")) {
                    themeActionButtons
                }
            }
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

    /// The New / Import / Export actions, shown both for the empty state and
    /// under the populated list.
    private var themeActionButtons: some View {
        HStack(spacing: VitrineTokens.Spacing.xs) {
            Button("New Theme…") { editorDraft = CustomThemeDraft() }
                .buttonStyle(.borderedProminent)
                .help("Create a custom syntax theme with a live preview.")
                .accessibilityIdentifier("new-custom-theme-button")

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
        .buttonStyle(.bordered)
        .fixedSize()
    }

    /// Apply / Edit / Rename / Delete for the selected custom theme.
    private var rowActions: some View {
        let theme = selectedTheme
        return TokenRow(label: Text("Selected theme")) {
            HStack(spacing: VitrineTokens.Spacing.xs) {
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
            .buttonStyle(.bordered)
            .fixedSize()
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
