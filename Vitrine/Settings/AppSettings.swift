import Combine
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
            SettingsCodec.persistStyle(config, to: defaults)
            dropPresetIfStyleDiverged()
        }
    }

    /// The working social card (CS-041): the document of the social-card editor,
    /// persisted like `config` so the user's card survives across launches. It is
    /// app-global — there is one working card — so it is shared rather than seeded
    /// per editor window.
    @Published var socialCard: SocialCardModel {
        didSet { SettingsCodec.persistSocialCard(socialCard, to: defaults) }
    }

    /// Copy the rendered image to the clipboard automatically (quick mode).
    @Published var autoCopy: Bool { didSet { defaults.set(autoCopy, forKey: Keys.autoCopy) } }

    /// Also save the rendered image to a file (CS-010 · Output).
    @Published var alsoSaveToFile: Bool {
        didSet { defaults.set(alsoSaveToFile, forKey: Keys.alsoSaveToFile) }
    }

    /// Close the editor window after a successful "Copy image" (CS-084). On by
    /// default: the window's job is done once the image is on the clipboard, so it
    /// gets out of the way like a focused capture utility. Users who copy repeatedly
    /// can turn it off in Settings.
    @Published var closeAfterCopy: Bool {
        didSet { defaults.set(closeAfterCopy, forKey: Keys.closeAfterCopy) }
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

    /// Send the source along with the image as plain, copyable text. Off by default so
    /// a copy stays a plain image; when on, a copy also places the text on the clipboard
    /// (paste the image anywhere, paste the text into an editor) and the multi-size
    /// export writes a `.txt` beside each image. Terminal output is stripped of its
    /// escape codes first, matching the rendered card.
    @Published var textSidecar: Bool {
        didSet { defaults.set(textSidecar, forKey: Keys.textSidecar) }
    }

    /// What the global hotkey does (CS-002).
    @Published var hotkeyAction: HotkeyAction {
        didSet { defaults.set(hotkeyAction.rawValue, forKey: Keys.hotkeyAction) }
    }

    /// The app's UI language (CS-047). `.system` follows the system language order; the
    /// other cases pin a shipped locale. Persisted, and written into `AppleLanguages` so
    /// macOS loads the chosen localization on the next launch (the Settings picker says so).
    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage)
            applyLanguageOverride()
        }
    }

    /// The UI language this process actually launched with — the effective
    /// localization macOS resolved at launch. It never changes during the process's
    /// life; `appLanguage` may diverge from it once the user picks a new language that
    /// only takes effect on the next launch (CS-047).
    let launchLanguage: AppLanguage

    /// Whether the selected `appLanguage` differs from the language the running process
    /// was launched with, so a relaunch would change the visible UI language. Drives
    /// the Settings "Relaunch to Apply" affordance (CS-047).
    var languageChangePendingRelaunch: Bool { appLanguage != launchLanguage }

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

    /// Re-indent pasted code automatically (CS-049 · Input). When on, a paste into the
    /// editor is tidied through ``CodeFormatter/tidy(_:language:)`` — brace/JSX languages
    /// are re-indented, whitespace-significant ones only dedented — so a snippet copied
    /// with broken indentation lands clean. The edit is undoable (⌘Z), and the same tidy
    /// is always available on demand via ⌥⌘F. Read globally (it is a behavior preference,
    /// not a per-window style), so it applies in every editor window.
    @Published var reindentOnPaste: Bool {
        didSet { defaults.set(reindentOnPaste, forKey: Keys.reindentOnPaste) }
    }

    /// The web URL-capture viewport, capture-mode, wait, and consent settings (CS-044),
    /// in their own focused sub-store rather than as members of this object (audit P2-1,
    /// "AppSettings is a god object"). Access them through `webCapture`, e.g.
    /// `settings.webCapture.viewportKind`. `AppSettings` forwards the sub-store's change
    /// notifications (see `init`), so SwiftUI surfaces observing `AppSettings` still refresh
    /// when a web-capture knob changes. Backed by the same defaults suite, so its settings
    /// persist alongside the rest and an older store loads unchanged.
    ///
    /// Declared `var` (never reassigned after `init`) only so a `$settings.webCapture.field`
    /// SwiftUI binding resolves: a `let` class property forms a read-only key path, which
    /// would break the writable-binding chain the Settings controls rely on.
    var webCapture: WebCaptureSettings

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

    /// Keeps the forwarded `webCapture` change subscription alive for this instance's
    /// lifetime (audit P2-1). A nested `ObservableObject` does not re-publish through its
    /// parent automatically, so without this re-broadcast a view observing `AppSettings`
    /// would miss web-capture edits.
    private var webCaptureObserver: AnyCancellable?

    /// Guards the `config` observer from clearing the selected preset while we are
    /// applying that very preset (CS-020). Without it, the style writes inside
    /// `selectPreset(_:)` would momentarily look like a user edit.
    private var isApplyingPreset = false

    private typealias Keys = SettingsCodec.Keys

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
        closeAfterCopy = defaults.object(forKey: Keys.closeAfterCopy) as? Bool ?? true
        exportScale = SettingsCodec.readExportScale(from: defaults)
        exportFormat = ExportFormat.resolve(defaults.string(forKey: Keys.exportFormat))
        colorProfile = ColorProfile.resolve(defaults.string(forKey: Keys.colorProfile))
        richClipboard = defaults.object(forKey: Keys.richClipboard) as? Bool ?? false
        textSidecar = defaults.object(forKey: Keys.textSidecar) as? Bool ?? false
        hotkeyAction = HotkeyAction.resolve(defaults.string(forKey: Keys.hotkeyAction))
        let resolvedLanguage = AppLanguage.resolve(defaults.string(forKey: Keys.appLanguage))
        appLanguage = resolvedLanguage
        // Capture the launch-time language so the Settings pane can tell when a change
        // needs a relaunch to take effect (CS-047).
        launchLanguage = resolvedLanguage
        // A persisted preset id that no longer maps to a known preset resolves to
        // "Custom" (nil) rather than trapping (CS-020 / CS-050 documented fallback).
        selectedPresetID =
            ExportPreset.preset(withID: defaults.string(forKey: Keys.selectedPreset))?
            .id
        treatURLsAsScreenshot = defaults.object(forKey: Keys.treatURLs) as? Bool ?? false
        // Default on: a fresh install tidies pastes by default (CS-049), the behavior the
        // editor's "paste a snippet to screenshot it" flow expects; the toggle opts out.
        reindentOnPaste = defaults.object(forKey: Keys.reindentOnPaste) as? Bool ?? true
        // Web URL-capture viewport/wait/consent settings (CS-044) live in their own
        // focused sub-store (audit P2-1), read defensively from the same defaults suite
        // so a missing or garbage value falls back to the documented default (CS-050).
        webCapture = WebCaptureSettings(defaults: defaults)
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

        // The working social card (CS-041), read defensively: a missing or corrupt
        // blob yields a fresh default card, and the model re-validates every field.
        socialCard = SettingsCodec.readSocialCard(from: defaults)

        config = SettingsCodec.readConfig(from: defaults)

        // Re-broadcast the web-capture sub-store's changes as our own (audit P2-1) so
        // SwiftUI surfaces bound to `AppSettings` refresh when a web-capture knob changes;
        // a nested `ObservableObject` does not propagate to its parent on its own.
        webCaptureObserver = webCapture.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
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
        let suiteName = "com.johnny4young.vitrine.editor-session.\(UUID().uuidString)"
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
        textSidecar = session.textSidecar
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

    /// The live `config` with the PRO Brand Kit watermark applied — what every image
    /// export surface renders (CS-092).
    ///
    /// The watermark lives only on this derived value, never on the stored `config`:
    /// so persistence, the "diverged from preset" bookkeeping, per-window sessions,
    /// and the golden suite (which builds its own `SnapshotConfig`) all stay
    /// byte-for-byte unchanged — the brand mark exists purely on the rendered output.
    /// It is resolved from the app-global `BrandKitStore` and the global entitlement,
    /// so every window and the quick-capture path share one brand identity, and it
    /// appears only when the user enabled it *and* PRO is unlocked.
    var exportConfig: SnapshotConfig {
        var resolved = config
        resolved.watermark = BrandKitStore.shared.resolvedWatermark(
            isPro: Entitlements.shared.isPro)
        return resolved
    }

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
            textSidecar: textSidecar,
            hotkeyAction: hotkeyAction.rawValue,
            treatURLsAsScreenshot: treatURLsAsScreenshot,
            recentLanguageCount: recentLanguages.count,
            schemaVersion: SettingsSchema.storedVersion(in: defaults)
        )
    }

    /// Writes the chosen UI language into `AppleLanguages` (or removes the override for
    /// `.system`) in this instance's defaults domain — `.standard` for the shared app, an
    /// isolated suite under test — so macOS loads the selected localization on the next
    /// launch (CS-047).
    private func applyLanguageOverride() {
        if let code = appLanguage.localeCode {
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
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
        closeAfterCopy = true
        exportScale = SettingsDefaults.exportScale
        exportFormat = .fallback
        colorProfile = .fallback
        richClipboard = false
        textSidecar = false
        hotkeyAction = .fallback
        appLanguage = .system
        treatURLsAsScreenshot = false
        reindentOnPaste = true
        // The web-capture sub-store resets its own published state (audit P2-1); its
        // persisted keys were cleared by the `Keys.all` sweep above. This includes
        // returning consent to the pre-disclosure state, re-arming the disclosure.
        webCapture.resetToDefaults()
        recentLanguages = []
        selectedPresetID = nil
        // Returns the user to a first-run experience after a full reset (CS-035).
        hasSeenWelcome = false
        // Clearing this restores the clean-install What's New behavior (CS-049): the
        // next launch stamps the current version as seen rather than showing notes.
        lastSeenWhatsNewVersion = nil
        socialCard = SocialCardModel()
        config = SnapshotConfig()
    }

    /// Falls back to "Custom" once the user edits the style away from the active
    /// preset, so the picker never claims a preset that no longer describes the
    /// canvas (CS-020). Skipped while a preset is being applied.
    private func dropPresetIfStyleDiverged() {
        guard !isApplyingPreset, let preset = selectedPreset else { return }
        if !preset.matches(config) { selectedPresetID = nil }
    }
}
