import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// The destination preset as the redesign's segmented pill row: "Custom"
/// leading, then the presets under the handoff's short labels (CS-020). The
/// settings panes use this; the editor's Output disclosure carries its own
/// two-row variant with the full preset list.
struct DestinationSegmentedPicker: View {
    @ObservedObject var settings: AppSettings

    /// Sentinel tag for the "Custom" segment (no preset). Not a valid preset id.
    private static let customTag = ""

    /// Preset ids in the handoff's display order with their short chip labels.
    /// The labels are product/brand tokens shown verbatim in every locale.
    /// Transparent Slide is deliberately absent (the handoff's list is final
    /// and the row only fits six segments); it stays selectable through the
    /// editor header's popup picker.
    private static let segments: [(id: String, label: String)] = [
        ("twitter", "X"),
        ("linkedin", "LinkedIn"),
        ("opengraph", "OG"),
        ("keynote", "Keynote"),
        ("docs", "Docs"),
    ]

    var body: some View {
        TokenSegmentedPicker(options: options, selection: selectionBinding)
            .help(presetHelp)
            .accessibilityLabel("Destination preset")
            .accessibilityIdentifier("destination-preset-picker")
    }

    private var options: [(String, Text)] {
        [(Self.customTag, Text("Custom"))]
            + Self.segments.map { ($0.id, Text(verbatim: $0.label)) }
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

    /// Where the `vitrine` CLI is currently linked, if anywhere (CS-033).
    @State private var cliInstalledAt: URL?
    /// A failed install attempt's message; drives the fallback alert.
    @State private var cliInstallError: String?

    var body: some View {
        SettingsPaneScroll {
            TokenGroup(title: Text("Capture")) {
                TokenRow(label: Text("Global hotkey")) {
                    KeyboardShortcuts.Recorder(for: .quickCapture)
                        .accessibilityLabel("Global hotkey")
                }
                TokenRow(label: Text("Hotkey runs")) {
                    TokenSegmentedPicker(
                        options: [
                            (HotkeyAction.quickCapture, Text("Capture")),
                            (HotkeyAction.openEditor, Text("Editor")),
                        ],
                        selection: $settings.hotkeyAction
                    )
                    .accessibilityLabel("Hotkey runs")
                }
                TokenRow(label: Text("Launch at login")) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("launch-at-login-toggle")
                        .onChange(of: launchAtLogin) { _, newValue in
                            LaunchAtLogin.setEnabled(newValue)
                        }
                }
            }

            TokenGroup(title: Text("App")) {
                TokenRow(
                    label: Text("App language"),
                    caption: Text("Vitrine reopens in the selected language next launch")
                ) {
                    TokenSegmentedPicker(
                        options: AppLanguage.allCases.map {
                            ($0, Text(verbatim: $0.displayName))
                        },
                        selection: $settings.appLanguage
                    )
                    .accessibilityLabel("App language")
                    .accessibilityIdentifier("app-language-picker")
                }

                // Shown only once the choice differs from the language the app is
                // running in, so the user can apply it now instead of quitting and
                // reopening a Dock-less menu-bar agent by hand (CS-047).
                if settings.languageChangePendingRelaunch {
                    TokenRow {
                        Button("Relaunch to Apply") { AppRelauncher.relaunch() }
                            .accessibilityIdentifier("relaunch-to-apply-button")
                    }
                }

                // The DMG-install counterpart of the Homebrew cask's `binary`
                // stanza (CS-033): link the embedded CLI onto PATH from here.
                if let cli = CLIToolInstaller.embeddedCLI {
                    TokenRow(label: Text("Command-line tool"), caption: cliToolCaption) {
                        HStack(spacing: VitrineTokens.Spacing.xs) {
                            Button("Install…") { installCLITool(cli) }
                                .help(
                                    "Link the vitrine command onto your PATH so scripts can render images."
                                )
                                .accessibilityIdentifier("install-cli-button")
                            Button("Copy Command") {
                                copyToClipboard(CLIToolInstaller.terminalCommand(for: cli))
                            }
                            .help(
                                "Copy the equivalent Terminal command, for system folders that need sudo."
                            )
                            .accessibilityIdentifier("copy-cli-command-button")
                        }
                        .fixedSize()
                    }
                }

                TokenRow(
                    label: Text("Reset"),
                    caption: Text("Restores every preference to its default")
                ) {
                    Button("Reset All Settings…", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .accessibilityIdentifier("reset-all-settings-button")
                }
            }
        }
        .onAppear {
            if let cli = CLIToolInstaller.embeddedCLI {
                cliInstalledAt = CLIToolInstaller.installedLocation(of: cli)
            }
        }
        .alert(
            "Couldn't Install the Command",
            isPresented: Binding(
                get: { cliInstallError != nil }, set: { if !$0 { cliInstallError = nil } })
        ) {
            Button("Copy Command") {
                if let cli = CLIToolInstaller.embeddedCLI {
                    copyToClipboard(CLIToolInstaller.terminalCommand(for: cli))
                }
                cliInstallError = nil
            }
            Button("OK", role: .cancel) { cliInstallError = nil }
        } message: {
            Text(
                "\(cliInstallError ?? "") System folders need an administrator: run the copied command in Terminal instead."
            )
        }
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

    // MARK: - Command-line tool (CS-033)

    /// The CLI row's caption: where the link lives once installed, otherwise
    /// what installing gets you.
    private var cliToolCaption: Text {
        if let cliInstalledAt {
            return Text("Linked at \(cliInstalledAt.path)")
        }
        return Text("Render images from scripts with the vitrine command")
    }

    /// Runs the sandbox-true install flow: the user picks the destination
    /// folder (the panel's grant is what authorizes the write), then the
    /// symlink is created inside it. A refusal (e.g. root-owned
    /// /usr/local/bin) surfaces the copyable Terminal fallback.
    private func installCLITool(_ cli: URL) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = String(
            localized:
                "Choose a folder on your PATH for the vitrine command — for example /opt/homebrew/bin."
        )
        panel.prompt = String(localized: "Install")
        panel.directoryURL = CLIToolInstaller.knownBinDirectories.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        switch CLIToolInstaller.install(cli, into: directory) {
        case .installed(let link):
            cliInstalledAt = link
            cliInstallError = nil
        case .failed(let message):
            cliInstallError = message
        }
    }

    /// Places `command` on the general pasteboard (the Copy Command actions).
    private func copyToClipboard(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
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
        TokenTextField(prompt: Text("e.g. 3, 7-9, 12"), text: $text)
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
            TokenRow(label: Text("Filename")) {
                TokenTextField(prompt: Text("e.g. ContentView.swift"), text: filenameBinding)
                    .help("Optional filename shown as a chip in the header")
                    .accessibilityLabel("Filename")
                    .accessibilityIdentifier("metadata-filename-field")
            }

            TokenRow(label: Text("Title")) {
                TokenTextField(prompt: Text("e.g. Aurora gradient"), text: titleBinding)
                    .help("Optional title shown above the code")
                    .accessibilityLabel("Title")
                    .accessibilityIdentifier("metadata-title-field")
            }

            TokenRow(label: Text("Caption")) {
                TokenTextField(prompt: Text("e.g. A SwiftUI gradient"), text: captionBinding)
                    .help("Optional one-line caption shown under the title")
                    .accessibilityLabel("Caption")
                    .accessibilityIdentifier("metadata-caption-field")
            }

            TokenRow(label: Text("Language badge")) {
                Toggle("Language badge", isOn: $settings.config.metadata.showLanguageBadge)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Show the current language as a badge in the header")
                    .accessibilityLabel("Language badge")
                    .accessibilityIdentifier("metadata-language-badge-toggle")
            }
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

    /// True while the Brand Kit upsell's paywall sheet is presented (CS-092).
    @State private var showingBrandKitPaywall = false

    /// True when the last brand-kit logo pick failed to import (audit P1-UX-3).
    @State private var brandKitLogoError = false

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
                        case .brandKit: brandKitGroups
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

    // MARK: Brand Kit (PRO · CS-092)

    /// The Brand Kit sub-tab: the configuration controls when PRO is unlocked, or a
    /// compact upsell that opens the paywall when it is locked. Either way the kit can
    /// be inspected; it only marks an export once PRO is active and the user enables it.
    @ViewBuilder private var brandKitGroups: some View {
        if entitlements.isUnlocked(.brandKit) {
            brandKitControls
        } else {
            brandKitUpsell
        }
    }

    private var brandKitControls: some View {
        TokenGroup(title: Text("Brand Kit")) {
            TokenRow(
                label: Text("Apply to captures"),
                caption: Text("Adds your mark to every exported image")
            ) {
                Toggle("Apply to captures", isOn: $brandKit.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("brand-kit-enabled-toggle")
            }
            TokenRow(label: Text("Logo"), caption: Text("Shown small in the chosen corner")) {
                brandKitLogoControl
            }
            TokenRow(label: Text("Handle")) {
                TokenTextField(prompt: Text(verbatim: "@jane"), text: brandKitHandle)
                    .accessibilityIdentifier("brand-kit-handle-field")
            }
            TokenRow(label: Text("Project")) {
                TokenTextField(prompt: Text(verbatim: "vitrine"), text: brandKitProject)
                    .accessibilityIdentifier("brand-kit-project-field")
            }
            TokenRow(label: Text("Accent"), caption: Text("Tints the mark's text")) {
                HStack(spacing: 8) {
                    // A way back to the legible default — the model's `nil` accent (audit P1-UX-2).
                    if brandKit.brandKit.accent != nil {
                        Button("Reset") { brandKit.brandKit.accent = nil }
                            .buttonStyle(.plain)
                            .foregroundStyle(VitrineTokens.Accent.base)
                            .accessibilityIdentifier("brand-kit-accent-reset")
                    }
                    ColorPicker("Accent", selection: brandKitAccent, supportsOpacity: false)
                        .labelsHidden()
                        .accessibilityIdentifier("brand-kit-accent-picker")
                }
            }
            TokenRow(label: Text("Placement")) {
                Picker("Placement", selection: brandKitPlacement) {
                    ForEach(Watermark.Placement.allCases, id: \.self) { placement in
                        Text(placement.label).tag(placement)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("brand-kit-placement-picker")
            }
        }
        .accessibilityIdentifier("settings-brand-kit-controls")
    }

    /// The logo thumbnail (when set) plus Choose/Replace and Remove actions.
    @ViewBuilder private var brandKitLogoControl: some View {
        HStack(spacing: 8) {
            if let logo = brandKit.logoImage {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Button("Remove") { brandKit.removeLogo() }
                    .buttonStyle(.plain)
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    .accessibilityIdentifier("brand-kit-remove-logo-button")
            }
            Button(brandKit.logoImage == nil ? "Choose…" : "Replace…") { pickBrandKitLogo() }
                .accessibilityIdentifier("brand-kit-choose-logo-button")
            if brandKitLogoError {
                Text("Couldn't load that image")
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(.red)
            }
        }
    }

    /// The locked state: a crown + PRO badge, the value blurb, and an unlock button
    /// that presents the shared `PaywallSheet` for the brand-kit feature (CS-091/092).
    private var brandKitUpsell: some View {
        TokenGroup(title: Text("Brand Kit")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(VitrineTokens.Accent.base)
                    Text("Brand Kit")
                        .font(.system(size: VitrineTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(VitrineTokens.Text.primary)
                    ProBadge()
                }
                Text("Add your logo, handle, and accent color to every snapshot.")
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showingBrandKitPaywall = true
                } label: {
                    Text("Unlock Vitrine PRO")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("brand-kit-unlock-button")
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showingBrandKitPaywall) { PaywallSheet(feature: .brandKit) }
        .accessibilityIdentifier("settings-brand-kit-upsell")
    }

    /// Picks a logo image through an open panel and imports it into the container
    /// (CS-092), reusing the same content-addressed image store the backgrounds use.
    private func pickBrandKitLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = String(localized: "Choose a logo image for your brand kit.")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        brandKitLogoError = !brandKit.importLogo(from: url)
    }

    // Bindings into the app-global brand kit; mutating a field reassigns the whole
    // value, so the store persists and the preview refreshes (CS-092).
    private var brandKitHandle: Binding<String> {
        Binding(get: { brandKit.brandKit.handle }, set: { brandKit.brandKit.handle = $0 })
    }
    private var brandKitProject: Binding<String> {
        Binding(get: { brandKit.brandKit.project }, set: { brandKit.brandKit.project = $0 })
    }
    private var brandKitAccent: Binding<Color> {
        Binding(
            get: { brandKit.brandKit.accent?.color ?? .white },
            set: { brandKit.brandKit.accent = RGBAColor($0) })
    }
    private var brandKitPlacement: Binding<Watermark.Placement> {
        Binding(get: { brandKit.brandKit.placement }, set: { brandKit.brandKit.placement = $0 })
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
        SettingsPaneScroll {
            TokenGroup(title: Text("Export")) {
                TokenRow(
                    label: Text("Destination"),
                    caption: Text("Presets set the image size and resolution for a destination")
                ) {
                    DestinationSegmentedPicker(settings: settings)
                }
                TokenRow(label: Text("Copy to clipboard automatically")) {
                    Toggle("Copy to clipboard automatically", isOn: $settings.autoCopy)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                TokenRow(label: Text("Also save to a file")) {
                    Toggle("Also save to a file", isOn: $settings.alsoSaveToFile)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                TokenRow(label: Text("Close the editor after copying")) {
                    Toggle("Close the editor after copying", isOn: $settings.closeAfterCopy)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("close-after-copy-toggle")
                }
                TokenRow(label: Text("Resolution")) {
                    TokenSegmentedPicker(
                        options: [
                            (1, Text(verbatim: "1×")),
                            (2, Text(verbatim: "2×")),
                            (3, Text(verbatim: "3×")),
                        ],
                        selection: $settings.exportScale
                    )
                    .accessibilityLabel("Resolution")
                    .accessibilityIdentifier("output-resolution-picker")
                }
                // The caption states honestly which output is vector: PDF is the
                // supported scalable format; PNG is raster (CS-023).
                TokenRow(label: Text("Format"), caption: Text(settings.exportFormat.summary)) {
                    TokenSegmentedPicker(
                        options: ExportFormat.allCases.map {
                            ($0, Text(verbatim: $0.displayName))
                        },
                        selection: $settings.exportFormat
                    )
                    .accessibilityLabel("Format")
                    .accessibilityIdentifier("output-format-picker")
                }
            }

            // Rich clipboard is opt-in so the default copy stays a plain image; the
            // explicit "Copy as Data URI" and "Copy Highlighted Code" actions in the
            // editor remain available regardless of this toggle (CS-054).
            TokenGroup(title: Text("Clipboard")) {
                TokenRow(
                    label: Text("Rich-text code on copy"),
                    caption: Text(
                        "Keeps colors and font when pasting; the image is always included")
                ) {
                    Toggle("Rich-text code on copy", isOn: $settings.richClipboard)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("rich-clipboard-toggle")
                }
            }

            // Color management lives in its own "Advanced" group so the default
            // (sRGB) stays the obvious choice and Display P3 reads as a deliberate
            // opt-in (CS-024).
            TokenGroup(title: Text("Advanced")) {
                TokenRow(
                    label: Text("Color profile"),
                    caption: Text(settings.colorProfile.summary)
                ) {
                    TokenSegmentedPicker(
                        options: [
                            (ColorProfile.sRGB, Text(verbatim: "sRGB")),
                            (.displayP3, Text(verbatim: "P3")),
                        ],
                        selection: $settings.colorProfile
                    )
                    .accessibilityLabel("Color profile")
                    .accessibilityIdentifier("color-profile-picker")
                }
            }
        }
        .accessibilityIdentifier("settings-output-pane")
    }
}

/// Input pane: URL handling (CS-010 · Input) and the web URL-capture viewport and
/// wait strategy (CS-044).
struct InputSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPaneScroll {
            TokenGroup(title: Text("Pasting")) {
                TokenRow(
                    label: Text("Re-indent code on paste"),
                    caption: Text("Undo with ⌘Z, or format anytime with ⌥⌘F")
                ) {
                    Toggle("Re-indent code on paste", isOn: $settings.reindentOnPaste)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("reindent-on-paste-toggle")
                }
                TokenRow(
                    label: Text("Treat copied URLs as a screenshot target"),
                    caption: Text("When off, a copied URL is rendered as text")
                ) {
                    Toggle(
                        "Treat copied URLs as a screenshot target",
                        isOn: $settings.treatURLsAsScreenshot
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            TokenGroup(title: Text("Web capture")) {
                WebCaptureControls(settings: settings)
                WebCaptureConsentRow(settings: settings)
            }
        }
        .accessibilityIdentifier("settings-input-pane")
    }
}

/// The Web-capture transparency + consent row (CS-045): states plainly what URL
/// capture does to the network, reflects the first-use consent state, and lets the
/// user revoke it (re-arming the disclosure) — or shows that capture is unavailable on
/// this build. The network model lives here so it is always consultable in Settings,
/// not only at the first-use sheet.
struct WebCaptureConsentRow: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TokenRow(
            label: Text("Network use"),
            caption: Text(
                "URL capture loads the page you ask for locally in WebKit — no Vitrine server, no analytics. Your code never leaves your Mac."
            )
        ) {
            trailing
        }
    }

    @ViewBuilder private var trailing: some View {
        if !NetworkCapability.isURLCaptureEnabled {
            Text("Direct-download only")
                .font(.system(size: VitrineTokens.FontSize.subhead))
                .foregroundStyle(VitrineTokens.Text.tertiary)
        } else if settings.webCapture.consentGiven {
            Button("Revoke") {
                settings.webCapture.consentGiven = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(VitrineTokens.Accent.base)
            .accessibilityIdentifier("web-capture-revoke-consent-button")
        } else {
            Text("Not used yet")
                .font(.system(size: VitrineTokens.FontSize.subhead))
                .foregroundStyle(VitrineTokens.Text.tertiary)
        }
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
        TokenRow(label: Text("Viewports"), caption: Text(viewportsFooter)) {
            HStack(spacing: 6) {
                ForEach(WebSnapshotConfig.ViewportPreset.Kind.allCases, id: \.self) { kind in
                    viewportChip(kind)
                }
            }
            .accessibilityLabel("Viewports")
            .accessibilityIdentifier("web-viewport-picker")
        }

        if settings.webCapture.viewports.contains(.custom) {
            TokenRow(label: Text("Width")) {
                Stepper(
                    value: $settings.webCapture.customViewportWidth,
                    in: customDimensionRange, step: 10
                ) {
                    Text(verbatim: "\(settings.webCapture.customViewportWidth) pt")
                        .font(.system(size: VitrineTokens.FontSize.subhead))
                        .foregroundStyle(VitrineTokens.Text.secondary)
                }
                .accessibilityLabel("Width")
                .accessibilityIdentifier("web-custom-width-stepper")
            }

            TokenRow(label: Text("Height")) {
                Stepper(
                    value: $settings.webCapture.customViewportHeight,
                    in: customDimensionRange, step: 10
                ) {
                    Text(verbatim: "\(settings.webCapture.customViewportHeight) pt")
                        .font(.system(size: VitrineTokens.FontSize.subhead))
                        .foregroundStyle(VitrineTokens.Text.secondary)
                }
                .accessibilityLabel("Height")
                .accessibilityIdentifier("web-custom-height-stepper")
            }
        }

        TokenRow(label: Text("Capture"), caption: Text(captureFooter)) {
            TokenSegmentedPicker(
                options: [
                    (WebSnapshotConfig.CaptureMode.visibleViewport, Text("Visible")),
                    (.fullPage, Text("Full page")),
                ],
                selection: $settings.webCapture.captureMode
            )
            .accessibilityLabel("Capture")
            .accessibilityIdentifier("web-capture-mode-picker")
        }

        TokenRow(label: Text("Wait until"), caption: Text(waitFooter)) {
            TokenSegmentedPicker(
                options: [
                    (WebSnapshotConfig.WaitStrategy.Kind.domContentLoaded, Text("Loaded")),
                    (.networkQuiet, Text("Idle")),
                    (.fixedDelay, Text("Delay")),
                ],
                selection: $settings.webCapture.waitKind
            )
            .accessibilityLabel("Wait until")
            .accessibilityIdentifier("web-wait-strategy-picker")
        }

        if settings.webCapture.waitKind != .domContentLoaded {
            TokenRow(label: Text("Extra wait")) {
                Stepper(value: $settings.webCapture.waitSeconds, in: waitSecondsRange, step: 1) {
                    Text(waitSecondsLabel)
                        .font(.system(size: VitrineTokens.FontSize.subhead))
                        .foregroundStyle(VitrineTokens.Text.secondary)
                }
                .accessibilityLabel("Extra wait")
                .accessibilityIdentifier("web-wait-seconds-stepper")
            }
        }
    }

    /// The segment label for a viewport kind — the handoff's short names. The
    /// custom segment reads "Custom…" rather than echoing the stored size,
    /// because the size is set by the rows below it.
    private func viewportSegmentLabel(for kind: WebSnapshotConfig.ViewportPreset.Kind) -> Text {
        switch kind {
        case .openGraph: Text("Social")
        case .desktop: Text("Desktop")
        case .fullHD: Text(verbatim: "Full HD")
        case .mobile: Text("Phone")
        case .custom: Text("Custom…")
        }
    }

    /// A selectable chip for one viewport kind in the multi-capture set (CS-044).
    /// Toggling adds/removes the kind in `settings.webCapture.viewports`; the last selected
    /// kind cannot be removed, so a capture always has at least one size.
    private func viewportChip(_ kind: WebSnapshotConfig.ViewportPreset.Kind) -> some View {
        let isOn = settings.webCapture.viewports.contains(kind)
        return Button {
            toggleViewport(kind)
        } label: {
            viewportSegmentLabel(for: kind)
                .font(.system(size: VitrineTokens.FontSize.subhead, weight: .medium))
                .foregroundStyle(
                    isOn ? VitrineTokens.Accent.contrast : VitrineTokens.Text.secondary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isOn ? VitrineTokens.Accent.base : Color.clear))
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? Color.clear : VitrineTokens.Line.border, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewportSegmentLabel(for: kind))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("web-viewport-chip-\(kind.rawValue)")
    }

    /// Toggles `kind` in the multi-capture viewport set, keeping it ordered and never
    /// empty (the last selected kind stays), and syncing the single `webCapture.viewportKind`
    /// to the primary selection so the back-compat single-viewport path stays valid.
    private func toggleViewport(_ kind: WebSnapshotConfig.ViewportPreset.Kind) {
        var set = settings.webCapture.viewports
        if let index = set.firstIndex(of: kind) {
            guard set.count > 1 else { return }
            set.remove(at: index)
        } else {
            set.append(kind)
        }
        settings.webCapture.viewports = set
        settings.webCapture.viewportKind = set.first ?? .openGraph
    }

    /// The footer under the viewport chips: a multi-selection captures every chosen
    /// size in one pass; a single selection behaves like the original single capture.
    private var viewportsFooter: String {
        settings.webCapture.viewports.count > 1
            ? String(localized: "Captures every selected size in one pass.")
            : String(localized: "Pick one or more sizes to capture.")
    }

    private var waitSecondsLabel: String {
        // One interpolated key whose singular/plural is chosen by the catalog's
        // plural variations (CS-047), rather than a Swift `== 1` branch — so every
        // locale's own plural categories are honored, not just one/other.
        String(localized: "\(settings.webCapture.waitSeconds) seconds")
    }

    private var captureFooter: String {
        switch settings.webCapture.captureMode {
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
        switch settings.webCapture.waitKind {
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
            VStack(spacing: 6) {
                // Identity cluster: who/what the app is.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 76, height: 76)
                    .accessibilityHidden(true)
                Text(verbatim: "Vitrine")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.primary)
                    .padding(.top, 10)
                // The version line's template is localized through the catalog
                // (CS-047); the version value itself is a semver, inserted verbatim.
                Text("Version \(appVersion) · MIT")
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                Text("Turn code into beautiful images, from your menu bar.")
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VitrineTokens.Text.secondary)
                Link("GitHub", destination: URL(string: "https://github.com/johnny4young/vitrine")!)
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .foregroundStyle(VitrineTokens.Accent.base)
                    .padding(.top, 4)

                Button("Export Diagnostics…") {
                    DiagnosticsExporter.exportWithSavePanel(settings: settings)
                }
                .accessibilityIdentifier("export-diagnostics-button")
                .help(
                    "Save a privacy-safe report (no code or clipboard contents) to a file you choose."
                )
                .padding(.top, 14)

                // A stable legal/brand string, shown verbatim like the "Vitrine"
                // wordmark above so it bypasses the String Catalog (CS-047).
                Text(verbatim: "© 2026 johnny4young · MIT")
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30 + 22)
            .padding(.horizontal, 26)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("settings-about-pane")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
