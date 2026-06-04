import OSLog
import SwiftUI

/// The app's persisted settings and the live `SnapshotConfig`, shared across the
/// UI, the quick-capture path, and the exporter (CS-010). `UserDefaults` is
/// injectable so persistence can be unit-tested.
///
/// Reads are deliberately defensive (CS-050): the schema is versioned and
/// migrated on init, and every typed read tolerates a missing or garbage value
/// by falling back to a documented default (see `SettingsDefaults`). Loading
/// from empty, partial, or corrupt defaults never traps and always yields a
/// valid configuration.
final class AppSettings: ObservableObject {
    static let shared = AppSettings(defaults: AppDefaults.current)

    /// The current snapshot configuration (theme, font, padding, …).
    @Published var config: SnapshotConfig {
        didSet {
            persistStyle()
            dropPresetIfStyleDiverged()
        }
    }

    /// Copy the rendered image to the clipboard automatically (quick mode).
    @Published var autoCopy: Bool { didSet { defaults.set(autoCopy, forKey: Keys.autoCopy) } }

    /// Also save the rendered image to a file (CS-010 · Output).
    @Published var alsoSaveToFile: Bool {
        didSet { defaults.set(alsoSaveToFile, forKey: Keys.alsoSaveToFile) }
    }

    /// Export resolution multiplier: 1, 2 (retina), or 3.
    @Published var exportScale: Int {
        didSet { defaults.set(exportScale, forKey: Keys.exportScale) }
    }

    /// Exported image format (CS-010 · Output).
    @Published var exportFormat: ExportFormat {
        didSet { defaults.set(exportFormat.rawValue, forKey: Keys.exportFormat) }
    }

    /// PNG color profile: sRGB by default, Display P3 as an advanced option
    /// (CS-024).
    @Published var colorProfile: ColorProfile {
        didSet { defaults.set(colorProfile.rawValue, forKey: Keys.colorProfile) }
    }

    /// What the global hotkey does (CS-002).
    @Published var hotkeyAction: HotkeyAction {
        didSet { defaults.set(hotkeyAction.rawValue, forKey: Keys.hotkeyAction) }
    }

    /// The id of the last selected destination preset, or `nil` for "Custom"
    /// (no preset, the user's own settings). Persisted so the last choice is
    /// restored on relaunch (CS-020).
    @Published private(set) var selectedPresetID: String? {
        didSet { defaults.set(selectedPresetID, forKey: Keys.selectedPreset) }
    }

    /// Treat clipboard URLs as a screenshot target (CS-010 · Input). Product Phase 2.
    @Published var treatURLsAsScreenshot: Bool {
        didSet { defaults.set(treatURLsAsScreenshot, forKey: Keys.treatURLs) }
    }

    /// Recently used languages, most-recent first (CS-004).
    @Published private(set) var recentLanguages: [Language] {
        didSet { defaults.set(recentLanguages.map(\.rawValue), forKey: Keys.recentLanguages) }
    }

    private let defaults: UserDefaults

    /// Guards the `config` observer from clearing the selected preset while we are
    /// applying that very preset (CS-020). Without it, the style writes inside
    /// `selectPreset(_:)` would momentarily look like a user edit.
    private var isApplyingPreset = false

    private enum Keys {
        static let themeID = "themeID"
        static let languageID = "languageID"
        static let fontSize = "fontSize"
        static let padding = "padding"
        static let cornerRadius = "cornerRadius"
        static let showChrome = "showChrome"
        static let showShadow = "showShadow"
        static let showLineNumbers = "showLineNumbers"
        static let highlightedLines = "highlightedLines"
        static let metadata = "metadata"
        static let gradientPreset = "gradientPreset"
        static let backgroundStyle = "backgroundStyle"
        static let autoCopy = "autoCopy"
        static let alsoSaveToFile = "alsoSaveToFile"
        static let exportScale = "exportScale"
        static let exportFormat = "exportFormat"
        static let colorProfile = "colorProfile"
        static let hotkeyAction = "hotkeyAction"
        static let treatURLs = "treatURLsAsScreenshot"
        static let recentLanguages = "recentLanguages"
        static let fontName = "fontName"
        static let fontLigatures = "fontLigatures"
        static let selectedPreset = "selectedPreset"
        /// Saved style presets (CS-030). Owned by `PresetStore`, listed here so a
        /// "Reset all settings" clears the user's presets along with the rest of
        /// their data; the store reloads its in-memory copy afterward.
        static let userStylePresets = PresetStore.storageKey
        /// Custom themes (CS-031). Owned by `CustomThemeStore`, listed here so a
        /// "Reset all settings" clears the user's themes along with the rest of their
        /// data; the store reloads its in-memory copy afterward.
        static let userCustomThemes = CustomThemeStore.storageKey

        /// Every key this app writes, used by `resetToDefaults()` to clear the
        /// store without an app reinstall. The schema version key is reset by
        /// the migration step that runs afterward.
        static let all = [
            themeID, languageID, fontSize, padding, cornerRadius, showChrome,
            showShadow, showLineNumbers, highlightedLines, metadata, gradientPreset,
            backgroundStyle, autoCopy, alsoSaveToFile, exportScale, exportFormat,
            colorProfile, hotkeyAction, treatURLs, recentLanguages, fontName,
            fontLigatures, selectedPreset, userStylePresets, userCustomThemes,
        ]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Bring the persisted layout up to the current schema before any typed
        // read runs, so migrations see the raw on-disk shape (CS-050).
        let migratedFrom = SettingsSchema.migrateToCurrent(defaults)
        Log.settings.info(
            "Loaded settings (schema \(migratedFrom, privacy: .public) → \(SettingsSchema.current, privacy: .public))"
        )

        autoCopy = defaults.object(forKey: Keys.autoCopy) as? Bool ?? true
        alsoSaveToFile = defaults.object(forKey: Keys.alsoSaveToFile) as? Bool ?? false
        exportScale = Self.readExportScale(from: defaults)
        exportFormat = ExportFormat.resolve(defaults.string(forKey: Keys.exportFormat))
        colorProfile = ColorProfile.resolve(defaults.string(forKey: Keys.colorProfile))
        hotkeyAction = HotkeyAction.resolve(defaults.string(forKey: Keys.hotkeyAction))
        // A persisted preset id that no longer maps to a known preset resolves to
        // "Custom" (nil) rather than trapping (CS-020 / CS-050 documented fallback).
        selectedPresetID =
            ExportPreset.preset(withID: defaults.string(forKey: Keys.selectedPreset))?
            .id
        treatURLsAsScreenshot = defaults.object(forKey: Keys.treatURLs) as? Bool ?? false
        recentLanguages =
            (defaults.array(forKey: Keys.recentLanguages) as? [String] ?? [])
            .compactMap(Language.init(rawValue:))

        config = Self.readConfig(from: defaults)
    }

    /// Sets the default theme (used by the "Theme" submenu).
    func selectTheme(_ theme: Theme) { config.theme = theme }

    // MARK: - Destination presets (CS-020)

    /// The currently selected destination preset, or `nil` for "Custom".
    var selectedPreset: ExportPreset? { ExportPreset.preset(withID: selectedPresetID) }

    /// Applies a destination preset: writes its presentation guidance into the
    /// live `config`, adopts its recommended export scale, and records the
    /// selection so it persists across launches (CS-020). The preset touches
    /// only presentation/output fields — the code and language are untouched.
    func selectPreset(_ preset: ExportPreset) {
        isApplyingPreset = true
        preset.apply(to: &config)
        isApplyingPreset = false
        exportScale = SettingsDefaults.clampExportScale(preset.scale)
        selectedPresetID = preset.id
    }

    /// Drops back to "Custom": no preset is applied and none is persisted. The
    /// current style is left exactly as-is.
    func clearPreset() { selectedPresetID = nil }

    // MARK: - Style presets (CS-030)

    /// Applies a saved style preset to the live config, writing only presentation
    /// fields and never the code or language (CS-030).
    ///
    /// A style preset is independent of the destination preset (CS-020): applying
    /// one may move the style away from an active destination preset, in which case
    /// the existing "diverged from preset" check naturally drops that selection to
    /// "Custom". The user's source is untouched.
    func applyStylePreset(_ preset: StylePreset) {
        preset.style.apply(to: &config)
        Log.settings.info("Applied a style preset")
    }

    /// The export scale a render should use (CS-020).
    ///
    /// Selecting a preset *seeds* `exportScale` with the preset's recommended
    /// value (e.g. OpenGraph → 1, so logical and pixel sizes match), but the
    /// Resolution control stays authoritative afterward: a later override is
    /// honored ("OpenGraph exports 1200×630 at 1× unless overridden"). So the
    /// effective scale is simply the current `exportScale`.
    var effectiveExportScale: Int { exportScale }

    /// The exact logical canvas size to render, when the active preset pins one
    /// (e.g. OpenGraph 1200×630); `nil` lets the canvas hug its content (CS-020).
    var effectiveFixedSize: CGSize? { selectedPreset?.sizing.fixedSize }

    /// Records a language as recently used (MRU, capped at 6).
    func noteLanguageUsed(_ language: Language) {
        var list = recentLanguages.filter { $0 != language }
        list.insert(language, at: 0)
        recentLanguages = Array(list.prefix(6))
    }

    /// Languages ordered recent-first, then the rest of the catalog (CS-004).
    var orderedLanguages: [Language] {
        recentLanguages + Language.allCases.filter { !recentLanguages.contains($0) }
    }

    /// A privacy-safe snapshot of the current settings for diagnostics (CS-048).
    ///
    /// Deliberately copies only behavioral knobs — never `config.code` or any
    /// other free-form user input — so a diagnostics bundle built from this can
    /// never echo the code being edited. The number of recent languages is
    /// reported as a count, not a list.
    var diagnosticsSnapshot: DiagnosticsSettingsSnapshot {
        DiagnosticsSettingsSnapshot(
            themeID: config.theme.id,
            languageID: config.language.rawValue,
            fontName: config.fontName,
            fontLigatures: config.fontLigatures,
            fontSize: config.fontSize,
            padding: config.padding,
            cornerRadius: config.cornerRadius,
            showChrome: config.showChrome,
            showShadow: config.showShadow,
            backgroundKind: config.background.diagnosticsKind,
            autoCopy: autoCopy,
            alsoSaveToFile: alsoSaveToFile,
            exportScale: exportScale,
            exportFormat: exportFormat.rawValue,
            colorProfile: colorProfile.rawValue,
            hotkeyAction: hotkeyAction.rawValue,
            treatURLsAsScreenshot: treatURLsAsScreenshot,
            recentLanguageCount: recentLanguages.count,
            schemaVersion: SettingsSchema.storedVersion(in: defaults)
        )
    }

    /// Restores every setting to its factory default without an app reinstall
    /// (CS-050). Clears the persisted keys, re-stamps the current schema
    /// version, and resets the live published state so the UI updates at once.
    func resetToDefaults() {
        Log.settings.notice("Resetting all settings to defaults")
        for key in Keys.all { defaults.removeObject(forKey: key) }
        defaults.removeObject(forKey: SettingsSchema.versionKey)
        SettingsSchema.migrateToCurrent(defaults)

        autoCopy = true
        alsoSaveToFile = false
        exportScale = SettingsDefaults.exportScale
        exportFormat = .fallback
        colorProfile = .fallback
        hotkeyAction = .fallback
        treatURLsAsScreenshot = false
        recentLanguages = []
        selectedPresetID = nil
        config = SnapshotConfig()
    }

    // MARK: - Defensive reads

    /// Builds a `SnapshotConfig` from `defaults`, tolerating any missing or
    /// wrongly-typed key. Each branch only overrides a default when a valid
    /// value is present; numeric values are clamped to their documented ranges.
    private static func readConfig(from defaults: UserDefaults) -> SnapshotConfig {
        var config = SnapshotConfig()
        if let id = defaults.string(forKey: Keys.themeID) {
            // Resolve through a store bound to the same defaults so a persisted
            // *custom* theme (CS-031) is restored on relaunch, falling back to the
            // built-in lookup (and ultimately One Dark) for a built-in or unknown id.
            config.theme = CustomThemeStore(defaults: defaults).theme(withID: id)
        }
        if let id = defaults.string(forKey: Keys.languageID), let language = Language(rawValue: id)
        {
            config.language = language
        }
        if let value = defaults.object(forKey: Keys.fontSize) as? Double {
            config.fontSize = SettingsDefaults.clampFontSize(value)
        }
        if let value = defaults.string(forKey: Keys.fontName), CodeFont.all.contains(value) {
            config.fontName = value
        }
        if let value = defaults.object(forKey: Keys.fontLigatures) as? Bool {
            config.fontLigatures = value
        }
        if let value = defaults.object(forKey: Keys.padding) as? Double {
            config.padding = SettingsDefaults.clampPadding(value)
        }
        if let value = defaults.object(forKey: Keys.cornerRadius) as? Double {
            config.cornerRadius = SettingsDefaults.clampCornerRadius(value)
        }
        if let value = defaults.object(forKey: Keys.showChrome) as? Bool {
            config.showChrome = value
        }
        if let value = defaults.object(forKey: Keys.showShadow) as? Bool {
            config.showShadow = value
        }
        if let value = defaults.object(forKey: Keys.showLineNumbers) as? Bool {
            config.showLineNumbers = value
        }
        // Highlighted lines persist as the canonical spec string ("3, 7-9"); a
        // missing or malformed value parses to no highlight rather than trapping
        // (CS-021 / CS-050).
        if let spec = defaults.string(forKey: Keys.highlightedLines) {
            config.highlightedLineRanges = LineHighlight.parse(spec)
        }
        if let metadata = readMetadata(from: defaults) {
            config.metadata = metadata
        }
        if let background = readBackground(from: defaults) {
            config.background = background
        }
        return config
    }

    /// Reads the persisted metadata header, tolerating a missing or corrupt value
    /// (CS-022 / CS-050). Stored as a JSON-encoded `SnapshotMetadata`; a garbage
    /// blob simply yields `nil`, leaving the empty default (no header) in place.
    /// `SnapshotMetadata`'s decoder re-normalizes its text fields, so an empty or
    /// untrimmed persisted string can never reach the renderer.
    private static func readMetadata(from defaults: UserDefaults) -> SnapshotMetadata? {
        guard let data = defaults.data(forKey: Keys.metadata),
            let decoded = try? JSONDecoder().decode(SnapshotMetadata.self, from: data)
        else { return nil }
        return decoded
    }

    /// Reads the persisted background, tolerating any missing or corrupt value
    /// (CS-050 / CS-051).
    ///
    /// All background kinds — solid, gradient preset, custom gradient, image, and
    /// transparent — are stored as a single JSON-encoded `BackgroundStyle` under
    /// `backgroundStyle`. For installs that predate CS-051 (which only ever wrote
    /// a `gradientPreset` name), a legacy preset name is honored as a fallback so
    /// the user's chosen gradient survives the upgrade. A garbage JSON blob or an
    /// unknown legacy name simply yields `nil`, leaving the default in place.
    private static func readBackground(from defaults: UserDefaults) -> BackgroundStyle? {
        if let data = defaults.data(forKey: Keys.backgroundStyle),
            let decoded = try? JSONDecoder().decode(BackgroundStyle.self, from: data)
        {
            return decoded
        }
        if let raw = defaults.string(forKey: Keys.gradientPreset),
            let preset = GradientPreset(rawValue: raw)
        {
            return .gradient(preset)
        }
        return nil
    }

    /// Reads the export scale, clamping a stored value into the supported set and
    /// falling back to the default for a missing or non-integer value.
    private static func readExportScale(from defaults: UserDefaults) -> Int {
        guard let value = defaults.object(forKey: Keys.exportScale) as? Int else {
            return SettingsDefaults.exportScale
        }
        return SettingsDefaults.clampExportScale(value)
    }

    /// Falls back to "Custom" once the user edits the style away from the active
    /// preset, so the picker never claims a preset that no longer describes the
    /// canvas (CS-020). Skipped while a preset is being applied.
    private func dropPresetIfStyleDiverged() {
        guard !isApplyingPreset, let preset = selectedPreset else { return }
        if !preset.matches(config) { selectedPresetID = nil }
    }

    private func persistStyle() {
        defaults.set(config.theme.id, forKey: Keys.themeID)
        defaults.set(config.language.rawValue, forKey: Keys.languageID)
        defaults.set(config.fontName, forKey: Keys.fontName)
        defaults.set(config.fontLigatures, forKey: Keys.fontLigatures)
        defaults.set(config.fontSize, forKey: Keys.fontSize)
        defaults.set(config.padding, forKey: Keys.padding)
        defaults.set(config.cornerRadius, forKey: Keys.cornerRadius)
        defaults.set(config.showChrome, forKey: Keys.showChrome)
        defaults.set(config.showShadow, forKey: Keys.showShadow)
        defaults.set(config.showLineNumbers, forKey: Keys.showLineNumbers)
        defaults.set(
            LineHighlight.describe(config.highlightedLineRanges), forKey: Keys.highlightedLines)
        persistMetadata(config.metadata)
        persistBackground(config.background)
    }

    /// Persists the metadata header as a JSON-encoded `SnapshotMetadata` so its
    /// fields round-trip (CS-022). An empty header clears the key so the store has
    /// no stale value and the default (no header) is what a later read restores;
    /// an unexpected encode failure also drops the key rather than leaving a stale
    /// blob behind.
    private func persistMetadata(_ metadata: SnapshotMetadata) {
        guard !metadata.isEmpty, let data = try? JSONEncoder().encode(metadata) else {
            defaults.removeObject(forKey: Keys.metadata)
            return
        }
        defaults.set(data, forKey: Keys.metadata)
    }

    /// Persists the background as a JSON-encoded `BackgroundStyle` so every kind
    /// (solid, gradient, custom gradient, image, transparent) round-trips
    /// (CS-051). The legacy `gradientPreset` string key is cleared on write so the
    /// store has a single source of truth and a stale name can never shadow the
    /// new value on a later read.
    private func persistBackground(_ background: BackgroundStyle) {
        defaults.removeObject(forKey: Keys.gradientPreset)
        guard let data = try? JSONEncoder().encode(background) else {
            // Encoding a value type with fixed-shape members is not expected to
            // fail; if it ever does, drop the key so the default applies rather
            // than leaving a stale background behind.
            defaults.removeObject(forKey: Keys.backgroundStyle)
            Log.settings.error("Background encode failed; persisting default on next change")
            return
        }
        defaults.set(data, forKey: Keys.backgroundStyle)
    }
}
