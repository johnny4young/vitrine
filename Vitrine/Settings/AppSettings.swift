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

    /// Add a rich-text representation (highlighted RTF/HTML) alongside the PNG on
    /// every copy (CS-054). Off by default so the one-shortcut copy stays a plain
    /// image; when on, a paste into a rich-text editor keeps the syntax colors and
    /// font while an image well still receives the picture.
    @Published var richClipboard: Bool {
        didSet { defaults.set(richClipboard, forKey: Keys.richClipboard) }
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

    /// The viewport preset a URL capture lays the page out in (CS-044). Stored as a
    /// flat discriminant; the custom size rides in `webCustomViewportWidth/Height`.
    @Published var webViewportKind: WebSnapshotConfig.ViewportPreset.Kind {
        didSet { defaults.set(webViewportKind.rawValue, forKey: Keys.webViewportKind) }
    }

    /// The custom viewport width in points, used only when `webViewportKind` is
    /// `.custom` (CS-044). Clamped into the safe range on read.
    @Published var webCustomViewportWidth: Int {
        didSet { defaults.set(webCustomViewportWidth, forKey: Keys.webCustomViewportWidth) }
    }

    /// The custom viewport height in points, used only when `webViewportKind` is
    /// `.custom` (CS-044). Clamped into the safe range on read.
    @Published var webCustomViewportHeight: Int {
        didSet { defaults.set(webCustomViewportHeight, forKey: Keys.webCustomViewportHeight) }
    }

    /// Whether a URL capture grabs the visible viewport or the full scrollable page
    /// (CS-044). The default is the deterministic visible viewport.
    @Published var webCaptureMode: WebSnapshotConfig.CaptureMode {
        didSet { defaults.set(webCaptureMode.rawValue, forKey: Keys.webCaptureMode) }
    }

    /// Which wait strategy a URL capture uses before snapshotting (CS-044). Stored
    /// as a flat discriminant; the post-load delay rides in `webWaitSeconds`.
    @Published var webWaitKind: WebSnapshotConfig.WaitStrategy.Kind {
        didSet { defaults.set(webWaitKind.rawValue, forKey: Keys.webWaitKind) }
    }

    /// The post-load wait, in seconds, for the fixed-delay and network-quiet
    /// strategies (CS-044). Ignored by `.domContentLoaded`. Clamped non-negative.
    @Published var webWaitSeconds: Int {
        didSet { defaults.set(webWaitSeconds, forKey: Keys.webWaitSeconds) }
    }

    /// The composed viewport preset for a URL capture (CS-044): the persisted
    /// discriminant resolved with the stored custom size, defensively clamped so a
    /// custom preset is always a usable, memory-safe size.
    var webViewportPreset: WebSnapshotConfig.ViewportPreset {
        .resolve(
            kind: webViewportKind,
            customWidth: webCustomViewportWidth,
            customHeight: webCustomViewportHeight)
    }

    /// The composed wait strategy for a URL capture (CS-044): the persisted
    /// discriminant resolved with the stored post-load delay.
    var webWaitStrategy: WebSnapshotConfig.WaitStrategy {
        .resolve(kind: webWaitKind, extraWaitSeconds: webWaitSeconds)
    }

    /// Recently used languages, most-recent first (CS-004).
    @Published private(set) var recentLanguages: [Language] {
        didSet { defaults.set(recentLanguages.map(\.rawValue), forKey: Keys.recentLanguages) }
    }

    /// Whether the first-run quick-start has been shown for this defaults suite
    /// (CS-035). It is written `true` the first time the welcome flow appears so the
    /// app never reshows it, and cleared by `resetToDefaults()` so a "Reset all
    /// settings" returns the user to a first-run experience. Persisting it in the
    /// app's defaults store (which UI tests isolate via `VITRINE_USER_DEFAULTS_SUITE`)
    /// is what lets a test reset the onboarding state without touching real app data.
    @Published var hasSeenWelcome: Bool {
        didSet { defaults.set(hasSeenWelcome, forKey: Keys.hasSeenWelcome) }
    }

    /// The app version whose "What's New" the user has most recently seen (CS-049),
    /// or `nil` when none has been recorded yet. The version-gated What's New surface
    /// appears only when the newest bundled release notes are strictly newer than
    /// this value, and never on a clean first run (`nil`), which onboarding owns.
    ///
    /// It is written the first time the notes for a version are dismissed, and on a
    /// clean first run the launch path stamps it with the current version so What's
    /// New starts surfacing only from the next upgrade onward. A full reset clears it
    /// so a "Reset all settings" returns the user to the same fresh-install behavior.
    /// Storing it in the app's defaults store (which UI tests isolate via
    /// `VITRINE_USER_DEFAULTS_SUITE`) lets a test drive the gate without touching real
    /// app data.
    @Published var lastSeenWhatsNewVersion: String? {
        didSet { defaults.set(lastSeenWhatsNewVersion, forKey: Keys.lastSeenWhatsNewVersion) }
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
        static let richClipboard = "richClipboard"
        static let hotkeyAction = "hotkeyAction"
        static let treatURLs = "treatURLsAsScreenshot"
        /// Web URL-capture viewport/wait settings (CS-044). All additive keys with
        /// documented defaults, so an older store simply reads the defaults.
        static let webViewportKind = "webViewportKind"
        static let webCustomViewportWidth = "webCustomViewportWidth"
        static let webCustomViewportHeight = "webCustomViewportHeight"
        static let webCaptureMode = "webCaptureMode"
        static let webWaitKind = "webWaitKind"
        static let webWaitSeconds = "webWaitSeconds"
        static let recentLanguages = "recentLanguages"
        static let fontName = "fontName"
        static let fontLigatures = "fontLigatures"
        static let selectedPreset = "selectedPreset"
        /// First-run quick-start completion flag (CS-035).
        static let hasSeenWelcome = "hasSeenWelcome"
        /// Last app version whose "What's New" the user has seen (CS-049).
        static let lastSeenWhatsNewVersion = "lastSeenWhatsNewVersion"
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
            colorProfile, richClipboard, hotkeyAction, treatURLs,
            webViewportKind, webCustomViewportWidth, webCustomViewportHeight,
            webCaptureMode, webWaitKind, webWaitSeconds, recentLanguages,
            fontName, fontLigatures, selectedPreset, hasSeenWelcome,
            lastSeenWhatsNewVersion, userStylePresets, userCustomThemes,
        ]

        /// The keys an editor window seeds from the app-wide defaults when it opens
        /// (CS-053): the document/style fields plus the per-capture output knobs and
        /// the selected destination preset. Deliberately excludes the app-global,
        /// non-per-window state — the onboarding/What's-New flags and the hotkey
        /// action — and the shared preset/theme *catalogs* (those resolve through the
        /// shared stores, not the window's volatile store). Seeding only these keys is
        /// what lets a new window open looking like the user's default while editing
        /// its own copy.
        static let editorSessionSeed = [
            themeID, languageID, fontSize, padding, cornerRadius, showChrome,
            showShadow, showLineNumbers, highlightedLines, metadata, gradientPreset,
            backgroundStyle, fontName, fontLigatures, exportScale, exportFormat,
            colorProfile, richClipboard, selectedPreset,
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
        richClipboard = defaults.object(forKey: Keys.richClipboard) as? Bool ?? false
        hotkeyAction = HotkeyAction.resolve(defaults.string(forKey: Keys.hotkeyAction))
        // A persisted preset id that no longer maps to a known preset resolves to
        // "Custom" (nil) rather than trapping (CS-020 / CS-050 documented fallback).
        selectedPresetID =
            ExportPreset.preset(withID: defaults.string(forKey: Keys.selectedPreset))?
            .id
        treatURLsAsScreenshot = defaults.object(forKey: Keys.treatURLs) as? Bool ?? false
        // Web URL-capture viewport/wait settings (CS-044). Each read tolerates a
        // missing or garbage value by falling back to the documented default and
        // clamping numeric values into the safe range (CS-050 posture).
        webViewportKind = WebDefaults.viewportKind(from: defaults)
        webCustomViewportWidth = WebDefaults.customViewportWidth(from: defaults)
        webCustomViewportHeight = WebDefaults.customViewportHeight(from: defaults)
        webCaptureMode = WebDefaults.captureMode(from: defaults)
        webWaitKind = WebDefaults.waitKind(from: defaults)
        webWaitSeconds = WebDefaults.waitSeconds(from: defaults)
        recentLanguages =
            (defaults.array(forKey: Keys.recentLanguages) as? [String] ?? [])
            .compactMap(Language.init(rawValue:))
        // Absent (a fresh suite) reads as `false`, so a brand-new install is treated
        // as first-run and the quick-start is offered once (CS-035).
        hasSeenWelcome = defaults.object(forKey: Keys.hasSeenWelcome) as? Bool ?? false
        // Absent on a fresh suite, which the What's New gate reads as a clean first
        // run (CS-049). A non-string (hand-edited/corrupt) value also resolves to nil
        // rather than trapping, so the gate falls back safely (CS-050 posture).
        lastSeenWhatsNewVersion = defaults.string(forKey: Keys.lastSeenWhatsNewVersion)

        config = Self.readConfig(from: defaults)
    }

    // MARK: - Per-window editor sessions (CS-053)

    /// Builds an independent settings instance for one editor window, seeded from the
    /// app-wide defaults but backed by its own **volatile** store, so the window edits
    /// its own document/style without clobbering the global default (CS-053). Edits in
    /// the returned instance persist only to its throwaway suite; the user adopts a
    /// window's look as the new default explicitly via ``makeDefault(from:)``.
    ///
    /// Seeding copies just the document/style and output keys (``Keys.editorSessionSeed``)
    /// from `source` into a fresh, uniquely-named suite, then loads through the normal
    /// defensive read path so the window starts from exactly what the user would see —
    /// same theme (built-in or custom), font, background, and output settings. The
    /// preset/theme *catalogs* are not copied: those resolve through the shared
    /// `PresetStore`/`CustomThemeStore`, so saved presets and custom themes are visible
    /// in every window. Returns a standalone instance backed by `.standard` only if a
    /// volatile suite cannot be created, which still keeps each window functional.
    static func makeEditorSession(
        seededFrom source: UserDefaults = AppDefaults.current
    )
        -> AppSettings
    {
        let suiteName = "app.vitrine.editor-session.\(UUID().uuidString)"
        guard let volatile = UserDefaults(suiteName: suiteName) else {
            return AppSettings(defaults: .standard)
        }
        // Start from a clean slate so a reused suite name (it never is — the name is a
        // fresh UUID) cannot leak prior values, then copy the seed keys verbatim.
        volatile.removePersistentDomain(forName: suiteName)
        for key in Keys.editorSessionSeed {
            if let value = source.object(forKey: key) { volatile.set(value, forKey: key) }
        }
        return AppSettings(defaults: volatile, volatileSuiteName: suiteName)
    }

    /// Convenience initializer for a volatile per-window session that records its
    /// throwaway suite name so it can be torn down when the window closes (CS-053).
    private convenience init(defaults: UserDefaults, volatileSuiteName: String) {
        self.init(defaults: defaults)
        self.volatileSuiteName = volatileSuiteName
    }

    /// The throwaway suite name backing a per-window session, or `nil` for the shared
    /// (persistent) instance. Used to clean up the volatile store on window close.
    private(set) var volatileSuiteName: String?

    /// Removes this session's volatile backing store, if any. Called when an editor
    /// window closes so a per-window suite never accumulates on disk (CS-053). A no-op
    /// for the shared, persistent instance.
    func discardVolatileStore() {
        guard let volatileSuiteName else { return }
        defaults.removePersistentDomain(forName: volatileSuiteName)
        self.volatileSuiteName = nil
    }

    /// Adopts `config` (and the accompanying output settings of `session`) as the new
    /// app-wide default (CS-053 "make default is explicit"). Called on the shared
    /// instance from a window's "Make Default" action so a per-window look becomes the
    /// starting point for future captures and new windows, persisting through the
    /// normal `config` observer. Output knobs ride along so "make default" captures the
    /// whole presentation the user dialed in, not just the canvas style.
    func makeDefault(from session: AppSettings) {
        config = session.config
        exportScale = session.exportScale
        exportFormat = session.exportFormat
        colorProfile = session.colorProfile
        richClipboard = session.richClipboard
        if let preset = session.selectedPreset {
            selectedPresetID = preset.id
        } else {
            selectedPresetID = nil
        }
        Log.settings.info("Adopted an editor window's configuration as the app default")
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
            richClipboard: richClipboard,
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
        richClipboard = false
        hotkeyAction = .fallback
        treatURLsAsScreenshot = false
        webViewportKind = WebDefaults.viewportKind
        webCustomViewportWidth = WebDefaults.customViewportWidth
        webCustomViewportHeight = WebDefaults.customViewportHeight
        webCaptureMode = WebDefaults.captureMode
        webWaitKind = WebDefaults.waitKind
        webWaitSeconds = WebDefaults.waitSeconds
        recentLanguages = []
        selectedPresetID = nil
        // Returns the user to a first-run experience after a full reset (CS-035).
        hasSeenWelcome = false
        // Clearing this restores the clean-install What's New behavior (CS-049): the
        // next launch stamps the current version as seen rather than showing notes.
        lastSeenWhatsNewVersion = nil
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

/// Canonical defaults and defensive reads for the web URL-capture viewport and wait
/// settings (CS-044), mirroring `SettingsDefaults` for the rest of the store.
///
/// URL capture is a Product Phase 2 feature gated on the network entitlement, so
/// these settings have no effect in a Phase 1 build; they are still persisted with
/// the same versioned, defensively-read discipline as every other setting (CS-050),
/// so the choice survives across launches and a corrupt or hand-edited value can
/// never reach the renderer as a degenerate viewport or a negative wait.
enum WebDefaults {
    /// The default viewport: OpenGraph's social-card size.
    static let viewportKind: WebSnapshotConfig.ViewportPreset.Kind = .openGraph

    /// The default custom viewport, used only when the kind is `.custom`. Seeds the
    /// width/height fields with a sensible desktop-ish size the first time a user
    /// switches to a custom viewport.
    static let customViewportWidth = 1280
    static let customViewportHeight = 800

    /// The default capture mode: the deterministic visible viewport.
    static let captureMode: WebSnapshotConfig.CaptureMode = .visibleViewport

    /// The default wait strategy: snapshot as soon as the load settles.
    static let waitKind: WebSnapshotConfig.WaitStrategy.Kind = .domContentLoaded

    /// The default post-load wait seconds for a timed strategy.
    static let waitSeconds = WebSnapshotConfig.WaitStrategy.defaultExtraWaitSeconds

    /// Reads the persisted viewport kind, falling back to the default for a missing
    /// or unrecognized raw value.
    static func viewportKind(
        from defaults: UserDefaults
    )
        -> WebSnapshotConfig.ViewportPreset.Kind
    {
        guard let raw = defaults.string(forKey: "webViewportKind"),
            let kind = WebSnapshotConfig.ViewportPreset.Kind(rawValue: raw)
        else { return viewportKind }
        return kind
    }

    /// Reads the persisted custom viewport width, clamped into the safe range and
    /// falling back to the default for a missing or non-integer value.
    static func customViewportWidth(from defaults: UserDefaults) -> Int {
        guard let value = defaults.object(forKey: "webCustomViewportWidth") as? Int else {
            return customViewportWidth
        }
        return WebSnapshotConfig.ViewportPreset.clampCustomDimension(value)
    }

    /// Reads the persisted custom viewport height, clamped into the safe range and
    /// falling back to the default for a missing or non-integer value.
    static func customViewportHeight(from defaults: UserDefaults) -> Int {
        guard let value = defaults.object(forKey: "webCustomViewportHeight") as? Int else {
            return customViewportHeight
        }
        return WebSnapshotConfig.ViewportPreset.clampCustomDimension(value)
    }

    /// Reads the persisted capture mode, falling back to the default for a missing
    /// or unrecognized raw value.
    static func captureMode(from defaults: UserDefaults) -> WebSnapshotConfig.CaptureMode {
        guard let raw = defaults.string(forKey: "webCaptureMode"),
            let mode = WebSnapshotConfig.CaptureMode(rawValue: raw)
        else { return captureMode }
        return mode
    }

    /// Reads the persisted wait kind, falling back to the default for a missing or
    /// unrecognized raw value.
    static func waitKind(from defaults: UserDefaults) -> WebSnapshotConfig.WaitStrategy.Kind {
        guard let raw = defaults.string(forKey: "webWaitKind"),
            let kind = WebSnapshotConfig.WaitStrategy.Kind(rawValue: raw)
        else { return waitKind }
        return kind
    }

    /// Reads the persisted post-load wait seconds, clamped non-negative and bounded
    /// by the wait cap, falling back to the default for a missing or non-integer value.
    static func waitSeconds(from defaults: UserDefaults) -> Int {
        guard let value = defaults.object(forKey: "webWaitSeconds") as? Int else {
            return waitSeconds
        }
        return min(max(value, 0), waitSecondsRange.upperBound)
    }

    /// The inclusive bounds the post-load wait seconds are clamped into. The ceiling
    /// keeps the total wait comfortably inside the hard timeout cap so the picker can
    /// never seed a wait that would always hit the safety ceiling.
    static let waitSecondsRange = 0...30
}
