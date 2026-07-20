import OSLog
import SwiftUI

/// The app's persisted settings and the live `SnapshotConfig`, shared across the
/// UI, the quick-capture path, and the exporter. `UserDefaults` is
/// injectable so persistence can be unit-tested.
///
/// Reads are deliberately defensive: the schema is versioned and
/// migrated on init, and every typed read tolerates a missing or garbage value
/// by falling back to a documented default (see `SettingsDefaults`). Loading
/// from empty, partial, or corrupt defaults never traps and always yields a
/// valid configuration.
@Observable
final class AppSettings {
    /// The app-wide settings, constructed by the composition root (``AppEnvironment``)
    /// and reached here as a thin forwarder so existing call sites are unchanged.
    static var shared: AppSettings { AppEnvironment.shared.appSettings }

    /// The current snapshot configuration (theme, font, padding, …).
    var config: SnapshotConfig {
        didSet {
            // Typing changes only `config.code`, which `persistStyle` never writes — so
            // re-persisting the whole style block (~15 defaults writes + JSON encodes) and
            // re-checking preset divergence on every keystroke is pure churn. Skip both
            // when nothing but the code changed. Normalizing `code` before the comparison
            // means the whole struct is checked, so no persisted style field can ever be
            // missed — any real change (padding, theme, background, annotations, …) still
            // persists.
            var normalized = config
            normalized.code = oldValue.code
            guard normalized != oldValue else { return }
            SettingsCodec.persistStyle(config, to: defaults)
            dropPresetIfStyleDiverged()
        }
    }

    /// The working social card: the document of the social-card editor,
    /// persisted like `config` so the user's card survives across launches. It is
    /// app-global — there is one working card — so it is shared rather than seeded
    /// per editor window.
    var socialCard: SocialCardModel {
        didSet { SettingsCodec.persistSocialCard(socialCard, to: defaults) }
    }

    /// The image-output settings (auto-copy, save, scale, format, color profile, rich
    /// clipboard, and text sidecar), extracted into a focused sub-store
    /// rather than as members of this object. Access them through `export`,
    /// e.g. `settings.export.scale`. Both objects are `@Observable`, so a SwiftUI surface
    /// that reads `settings.export.<field>` observes the nested store directly. Backed by
    /// the same defaults suite, so an older store loads unchanged.
    ///
    /// Declared `var` (never reassigned after `init`) only so a `$settings.export.field`
    /// SwiftUI binding resolves — a `let` class property forms a read-only key path.
    var export: ExportSettings

    /// What the global hotkey does.
    var hotkeyAction: HotkeyAction {
        didSet { defaults.set(hotkeyAction.rawValue, forKey: Keys.hotkeyAction) }
    }

    /// The app's UI language. `.system` follows the system language order; the
    /// other cases pin a shipped locale. Persisted, and written into `AppleLanguages` so
    /// macOS loads the chosen localization on the next launch (the Settings picker says so).
    var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage)
            applyLanguageOverride()
        }
    }

    /// The UI language this process actually launched with — the effective
    /// localization macOS resolved at launch. It never changes during the process's
    /// life; `appLanguage` may diverge from it once the user picks a new language that
    /// only takes effect on the next launch.
    let launchLanguage: AppLanguage

    /// Whether the selected `appLanguage` differs from the language the running process
    /// was launched with, so a relaunch would change the visible UI language. Drives
    /// the Settings "Relaunch to Apply" affordance.
    var languageChangePendingRelaunch: Bool { appLanguage != launchLanguage }

    /// The id of the last selected destination preset, or `nil` for "Custom"
    /// (no preset, the user's own settings). Persisted so the last choice is
    /// restored on relaunch.
    private(set) var selectedPresetID: String? {
        didSet { defaults.set(selectedPresetID, forKey: Keys.selectedPreset) }
    }

    /// Treat clipboard URLs as a screenshot target (Input). web capture.
    var treatURLsAsScreenshot: Bool {
        didSet { defaults.set(treatURLsAsScreenshot, forKey: Keys.treatURLs) }
    }

    /// Re-indent pasted code automatically (Input). When on, a paste into the
    /// editor is tidied through ``CodeFormatter/tidy(_:language:)`` — brace/JSX languages
    /// are re-indented, whitespace-significant ones only dedented — so a snippet copied
    /// with broken indentation lands clean. The edit is undoable (⌘Z), and the same tidy
    /// is always available on demand via ⌥⌘F. Read globally (it is a behavior preference,
    /// not a per-window style), so it applies in every editor window.
    var reindentOnPaste: Bool {
        didSet { defaults.set(reindentOnPaste, forKey: Keys.reindentOnPaste) }
    }

    /// The web URL-capture viewport, capture-mode, wait, and consent settings,
    /// in their own focused sub-store rather than as members of this object,
    /// "AppSettings is a god object"). Access them through `webCapture`, e.g.
    /// `settings.webCapture.viewportKind`. Both objects are `@Observable`, so a SwiftUI
    /// surface that reads `settings.webCapture.<field>` observes the nested store directly
    /// and refreshes on a web-capture edit — no manual change-forwarding needed. Backed by
    /// the same defaults suite, so its settings persist alongside the rest and an older
    /// store loads unchanged.
    ///
    /// Declared `var` (never reassigned after `init`) only so a `$settings.webCapture.field`
    /// SwiftUI binding resolves: a `let` class property forms a read-only key path, which
    /// would break the writable-binding chain the Settings controls rely on.
    var webCapture: WebCaptureSettings

    /// Recently used languages, most-recent first.
    private(set) var recentLanguages: [Language] {
        didSet { defaults.set(recentLanguages.map(\.rawValue), forKey: Keys.recentLanguages) }
    }

    /// Whether the first-run quick-start has been shown for this defaults suite.
    /// It is written `true` the first time the welcome flow appears so the
    /// app never reshows it, and cleared by `resetToDefaults()` so a "Reset all
    /// settings" returns the user to a first-run experience. Persisting it in the
    /// app's defaults store (which UI tests isolate via `VITRINE_USER_DEFAULTS_SUITE`)
    /// is what lets a test reset the onboarding state without touching real app data.
    var hasSeenWelcome: Bool {
        didSet { defaults.set(hasSeenWelcome, forKey: Keys.hasSeenWelcome) }
    }

    /// The app version whose "What's New" the user has most recently seen,
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
    var lastSeenWhatsNewVersion: String? {
        didSet { defaults.set(lastSeenWhatsNewVersion, forKey: Keys.lastSeenWhatsNewVersion) }
    }

    private let defaults: UserDefaults

    /// The Brand Kit and entitlement that resolve the export watermark, injected so
    /// `exportConfig` is unit-testable without the app-global singletons.
    /// Default to the shared instances, so production and every existing call site keep
    /// the single app-wide brand identity; a test passes its own.
    private let brandKit: BrandKitStore
    private let entitlements: Entitlements

    /// Guards the `config` observer from clearing the selected preset while we are
    /// applying that very preset. Without it, the style writes inside
    /// `selectPreset(_:)` would momentarily look like a user edit.
    private var isApplyingPreset = false

    private typealias Keys = SettingsCodec.Keys

    init(
        defaults: UserDefaults = .standard,
        brandKit: BrandKitStore = .shared,
        entitlements: Entitlements = .shared
    ) {
        self.defaults = defaults
        self.brandKit = brandKit
        self.entitlements = entitlements

        // Bring the persisted layout up to the current schema before any typed
        // read runs, so migrations see the raw on-disk shape.
        let migratedFrom = SettingsSchema.migrateToCurrent(defaults)
        Log.settings.info(
            "Loaded settings (schema \(migratedFrom, privacy: .public) → \(SettingsSchema.current, privacy: .public))"
        )

        // Image-output settings (Output) live in their own focused sub-store,
        // read defensively from the same defaults suite.
        export = ExportSettings(defaults: defaults)
        hotkeyAction = HotkeyAction.resolve(defaults.string(forKey: Keys.hotkeyAction))
        let resolvedLanguage = AppLanguage.resolve(defaults.string(forKey: Keys.appLanguage))
        appLanguage = resolvedLanguage
        // Capture the launch-time language so the Settings pane can tell when a change
        // needs a relaunch to take effect.
        launchLanguage = resolvedLanguage
        // A persisted preset id that no longer maps to a known preset resolves to
        // "Custom" (nil) rather than trapping (documented fallback).
        selectedPresetID =
            ExportPreset.preset(withID: defaults.string(forKey: Keys.selectedPreset))?
            .id
        treatURLsAsScreenshot = defaults.object(forKey: Keys.treatURLs) as? Bool ?? false
        // Default on: a fresh install tidies pastes by default, the behavior the
        // editor's "paste a snippet to screenshot it" flow expects; the toggle opts out.
        reindentOnPaste = defaults.object(forKey: Keys.reindentOnPaste) as? Bool ?? true
        // Web URL-capture viewport/wait/consent settings live in their own
        // focused sub-store, read defensively from the same defaults suite
        // so a missing or garbage value falls back to the documented default.
        webCapture = WebCaptureSettings(defaults: defaults)
        recentLanguages =
            (defaults.array(forKey: Keys.recentLanguages) as? [String] ?? [])
            .compactMap(Language.init(rawValue:))
        // Absent (a fresh suite) reads as `false`, so a brand-new install is treated
        // as first-run and the quick-start is offered once.
        hasSeenWelcome = defaults.object(forKey: Keys.hasSeenWelcome) as? Bool ?? false
        // Absent on a fresh suite, which the What's New gate reads as a clean first
        // run. A non-string (hand-edited/corrupt) value also resolves to nil
        // rather than trapping, so the gate falls back safely (defensive posture).
        lastSeenWhatsNewVersion = defaults.string(forKey: Keys.lastSeenWhatsNewVersion)

        // The working social card, read defensively: a missing or corrupt
        // blob yields a fresh default card, and the model re-validates every field.
        socialCard = SettingsCodec.readSocialCard(from: defaults)

        config = SettingsCodec.readConfig(from: defaults)
    }

    // MARK: - Per-window editor sessions

    /// Builds an independent settings instance for one editor window, seeded from the
    /// app-wide defaults but backed by its own **volatile** store, so the window edits
    /// its own document/style without clobbering the global default. Edits in
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
    /// throwaway suite name so it can be torn down when the window closes.
    private convenience init(defaults: UserDefaults, volatileSuiteName: String) {
        self.init(defaults: defaults)
        self.volatileSuiteName = volatileSuiteName
    }

    /// The throwaway suite name backing a per-window session, or `nil` for the shared
    /// (persistent) instance. Used to clean up the volatile store on window close.
    private(set) var volatileSuiteName: String?

    /// Removes this session's volatile backing store, if any. Called when an editor
    /// window closes so a per-window suite never accumulates on disk. A no-op
    /// for the shared, persistent instance.
    func discardVolatileStore() {
        guard let volatileSuiteName else { return }
        defaults.removePersistentDomain(forName: volatileSuiteName)
        self.volatileSuiteName = nil
    }

    /// Adopts the presentational parts of `session.config` (and the accompanying output
    /// settings) as the new app-wide default. Called
    /// on the shared instance from a window's "Make Default" action so a per-window look
    /// becomes the starting point for future captures and new windows, persisting through
    /// the normal `config` observer. Working content is stripped first: code, annotations,
    /// line marks, and a beautified foreground image are document-specific, not defaults.
    func makeDefault(from session: AppSettings) {
        var defaultConfig = session.config
        defaultConfig.code = ""
        defaultConfig.clearContentMarks()
        config = defaultConfig
        export.scale = session.export.scale
        export.format = session.export.format
        export.colorProfile = session.export.colorProfile
        export.richClipboard = session.export.richClipboard
        export.textSidecar = session.export.textSidecar
        if let preset = session.selectedPreset {
            selectedPresetID = preset.id
        } else {
            selectedPresetID = nil
        }
        Log.settings.info("Adopted an editor window's configuration as the app default")
    }

    /// Sets the default theme (used by the "Theme" submenu).
    func selectTheme(_ theme: Theme) { config.theme = theme }

    // MARK: - Destination presets

    /// The currently selected destination preset, or `nil` for "Custom".
    var selectedPreset: ExportPreset? { ExportPreset.preset(withID: selectedPresetID) }

    /// Applies a destination preset: writes its presentation guidance into the
    /// live `config`, adopts its recommended export scale, and records the
    /// selection so it persists across launches. The preset touches
    /// only presentation/output fields — the code and language are untouched.
    func selectPreset(_ preset: ExportPreset) {
        isApplyingPreset = true
        preset.apply(to: &config)
        isApplyingPreset = false
        export.scale = SettingsDefaults.clampExportScale(preset.scale)
        selectedPresetID = preset.id
    }

    /// Drops back to "Custom": no preset is applied and none is persisted. The
    /// current style is left exactly as-is.
    func clearPreset() { selectedPresetID = nil }

    // MARK: - Style presets

    /// Applies a saved style preset to the live config, writing only presentation
    /// fields and never the code or language.
    ///
    /// A style preset is independent of the destination preset: applying
    /// one may move the style away from an active destination preset, in which case
    /// the existing "diverged from preset" check naturally drops that selection to
    /// "Custom". The user's source is untouched.
    func applyStylePreset(_ preset: StylePreset) {
        preset.style.apply(to: &config)
        Log.settings.info("Applied a style preset")
    }

    /// Applies the next curated built-in look without altering document content.
    /// Returning the chosen preset keeps feedback and automation deterministic.
    @discardableResult
    func applySurpriseStyle() -> StylePreset {
        let preset = StylePreset.surprise(after: config)
        applyStylePreset(preset)
        return preset
    }

    /// The export scale a render should use.
    ///
    /// Selecting a preset *seeds* `exportScale` with the preset's recommended
    /// value (e.g. OpenGraph → 1, so logical and pixel sizes match), but the
    /// Resolution control stays authoritative afterward: a later override is
    /// honored ("OpenGraph exports 1200×630 at 1× unless overridden"). So the
    /// effective scale is simply the current `export.scale`.
    var effectiveExportScale: Int { export.scale }

    /// The exact logical canvas size to render, when the active preset pins one
    /// (e.g. OpenGraph 1200×630); `nil` lets the canvas hug its content.
    var effectiveFixedSize: CGSize? { selectedPreset?.sizing.fixedSize }

    /// The live `config` with the PRO Brand Kit watermark applied — what every image
    /// export surface renders.
    ///
    /// The watermark lives only on this derived value, never on the stored `config`:
    /// so persistence, the "diverged from preset" bookkeeping, per-window sessions,
    /// and the golden suite (which builds its own `SnapshotConfig`) all stay
    /// byte-for-byte unchanged — the brand mark exists purely on the rendered output.
    /// It is resolved from the injected `BrandKitStore` and entitlement (the shared
    /// instances by default), so every window and the quick-capture path share one brand
    /// identity, and it appears only when the user enabled it *and* PRO is unlocked.
    var exportConfig: SnapshotConfig {
        var resolved = config
        resolved.watermark = brandKit.resolvedWatermark(isPro: entitlements.isPro)
        return resolved
    }

    /// Records a language as recently used (MRU, capped at 6).
    func noteLanguageUsed(_ language: Language) {
        var list = recentLanguages.filter { $0 != language }
        list.insert(language, at: 0)
        recentLanguages = Array(list.prefix(6))
    }

    /// Languages ordered recent-first, then the rest of the catalog.
    var orderedLanguages: [Language] {
        recentLanguages + Language.allCases.filter { !recentLanguages.contains($0) }
    }

    /// A privacy-safe snapshot of the current settings for diagnostics.
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
            autoCopy: export.autoCopy,
            alsoSaveToFile: export.alsoSaveToFile,
            exportScale: export.scale,
            exportFormat: export.format.rawValue,
            colorProfile: export.colorProfile.rawValue,
            richClipboard: export.richClipboard,
            textSidecar: export.textSidecar,
            hotkeyAction: hotkeyAction.rawValue,
            treatURLsAsScreenshot: treatURLsAsScreenshot,
            recentLanguageCount: recentLanguages.count,
            schemaVersion: SettingsSchema.storedVersion(in: defaults)
        )
    }

    /// Writes the chosen UI language into `AppleLanguages` (or removes the override for
    /// `.system`) in this instance's defaults domain — `.standard` for the shared app, an
    /// isolated suite under test — so macOS loads the selected localization on the next
    /// launch.
    private func applyLanguageOverride() {
        if let code = appLanguage.localeCode {
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    /// Restores every setting to its factory default without an app reinstall.
    /// Clears the persisted keys, re-stamps the current schema
    /// version, and resets the live published state so the UI updates at once.
    func resetToDefaults() {
        Log.settings.notice("Resetting all settings to defaults")
        for key in Keys.all { defaults.removeObject(forKey: key) }
        defaults.removeObject(forKey: SettingsSchema.versionKey)
        SettingsSchema.migrateToCurrent(defaults)

        // The output sub-store resets its own published state; its persisted
        // keys were cleared by the `Keys.all` sweep above.
        export.resetToDefaults()
        hotkeyAction = .fallback
        appLanguage = .system
        treatURLsAsScreenshot = false
        reindentOnPaste = true
        // The web-capture sub-store resets its own published state; its
        // persisted keys were cleared by the `Keys.all` sweep above. This includes
        // returning consent to the pre-disclosure state, re-arming the disclosure.
        webCapture.resetToDefaults()
        recentLanguages = []
        selectedPresetID = nil
        // Returns the user to a first-run experience after a full reset.
        hasSeenWelcome = false
        // Clearing this restores the clean-install What's New behavior: the
        // next launch stamps the current version as seen rather than showing notes.
        lastSeenWhatsNewVersion = nil
        socialCard = SocialCardModel()
        config = SnapshotConfig()
    }

    /// Falls back to "Custom" once the user edits the style away from the active
    /// preset, so the picker never claims a preset that no longer describes the
    /// canvas. Skipped while a preset is being applied.
    private func dropPresetIfStyleDiverged() {
        guard !isApplyingPreset, let preset = selectedPreset else { return }
        if !preset.matches(config) { selectedPresetID = nil }
    }
}

// MARK: - Line-wrap control bindings

extension AppSettings {
    /// Binding for the "Wrap long lines" toggle, driving the optional `config.wrapColumns`:
    /// on adopts the default wrap width, off clears it (no wrap). Lives here so the editor
    /// inspector and the Settings pane drive the same field identically rather than each
    /// re-deriving the optional-to-Bool mapping.
    var wrapsLongLines: Binding<Bool> {
        Binding(
            get: { self.config.wrapsLongLines },
            set: { self.config.wrapColumns = $0 ? SettingsDefaults.wrapColumns : nil }
        )
    }

    /// Binding for the wrap-width slider as a `Double`, clamped into the safe range on
    /// write. Only meaningful while wrapping is on.
    var wrapColumnsValue: Binding<Double> {
        Binding(
            get: { Double(self.config.wrapColumns ?? SettingsDefaults.wrapColumns) },
            set: { self.config.wrapColumns = SettingsDefaults.clampWrapColumns(Int($0)) }
        )
    }
}
