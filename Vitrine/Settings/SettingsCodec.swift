import Foundation
import OSLog

/// The persistence codec for `AppSettings`: it owns the `UserDefaults` key names and
/// the defensive (de)serialization between the store and the typed model
/// (CS-050/CS-051).
///
/// `AppSettings` stays the observable state surface — the `@Published` properties and
/// every `$settings.x` binding live there. Keeping this a plain, non-observable enum
/// lets the "how settings are read and written" concern be read, tested, and evolved
/// on its own, without widening the settings object or risking SwiftUI's
/// nested-`ObservableObject` change-propagation pitfalls.
///
/// Every read tolerates a missing or garbage value by falling back to a documented
/// default; nothing here renders or publishes.
enum SettingsCodec {
    enum Keys {
        static let themeID = "themeID"
        static let languageID = "languageID"
        static let fontSize = "fontSize"
        static let padding = "padding"
        static let cornerRadius = "cornerRadius"
        static let showChrome = "showChrome"
        static let windowTitle = "windowTitle"
        static let showShadow = "showShadow"
        static let showLineNumbers = "showLineNumbers"
        static let highlightedLines = "highlightedLines"
        static let focusHighlightedLines = "focusHighlightedLines"
        static let diffDecorations = "diffDecorations"
        /// Snapshot annotations (CS-083), stored as a JSON-encoded `[Annotation]`.
        /// Part of the document/style, so it seeds new editor windows.
        static let annotations = "annotations"
        static let metadata = "metadata"
        static let gradientPreset = "gradientPreset"
        static let backgroundStyle = "backgroundStyle"
        static let autoCopy = "autoCopy"
        static let alsoSaveToFile = "alsoSaveToFile"
        static let closeAfterCopy = "closeAfterCopy"
        static let exportScale = "exportScale"
        static let exportFormat = "exportFormat"
        static let colorProfile = "colorProfile"
        static let richClipboard = "richClipboard"
        static let hotkeyAction = "hotkeyAction"
        static let appLanguage = "appLanguage"
        static let treatURLs = "treatURLsAsScreenshot"
        static let reindentOnPaste = "reindentOnPaste"
        /// Web URL-capture viewport/wait settings (CS-044). All additive keys with
        /// documented defaults, so an older store simply reads the defaults.
        static let webViewportKind = "webViewportKind"
        static let webViewports = "webViewports"
        static let webCustomViewportWidth = "webCustomViewportWidth"
        static let webCustomViewportHeight = "webCustomViewportHeight"
        static let webCaptureMode = "webCaptureMode"
        static let webWaitKind = "webWaitKind"
        static let webWaitSeconds = "webWaitSeconds"
        static let recentLanguages = "recentLanguages"
        static let fontName = "fontName"
        static let fontLigatures = "fontLigatures"
        static let selectedPreset = "selectedPreset"
        /// The last-edited social card (CS-041), stored as a JSON-encoded
        /// `SocialCardModel`. App-global (there is one working card, like the
        /// working document), so it is not part of `editorSessionSeed`.
        static let socialCard = "socialCard"
        /// Whether the user has confirmed the first-use URL-capture privacy
        /// disclosure (CS-045). Defaults false; URL capture shows the disclosure once
        /// until confirmed, and the Settings transparency row can revoke it.
        static let urlCaptureConsent = "urlCaptureConsentGiven"
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
        /// Brand Kit (CS-092). Owned by `BrandKitStore`, listed here so a
        /// "Reset all settings" clears the user's watermark identity and apply switch
        /// along with the rest of their preferences; the store reloads its in-memory
        /// copy afterward.
        static let brandKit = BrandKitStore.storageKey
        static let brandKitEnabled = BrandKitStore.enabledStorageKey

        /// Every key this app writes, used by `resetToDefaults()` to clear the
        /// store without an app reinstall. The schema version key is reset by
        /// the migration step that runs afterward.
        static let all = [
            themeID, languageID, fontSize, padding, cornerRadius, showChrome, windowTitle,
            showShadow, showLineNumbers, highlightedLines, focusHighlightedLines,
            diffDecorations, annotations, metadata, gradientPreset,
            backgroundStyle, autoCopy, alsoSaveToFile, closeAfterCopy, exportScale, exportFormat,
            colorProfile, richClipboard, hotkeyAction, appLanguage, treatURLs,
            reindentOnPaste,
            webViewportKind, webViewports, webCustomViewportWidth, webCustomViewportHeight,
            webCaptureMode, webWaitKind, webWaitSeconds, recentLanguages,
            fontName, fontLigatures, selectedPreset, socialCard, urlCaptureConsent,
            hasSeenWelcome, lastSeenWhatsNewVersion, userStylePresets, userCustomThemes,
            brandKit, brandKitEnabled,
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
            themeID, languageID, fontSize, padding, cornerRadius, showChrome, windowTitle,
            showShadow, showLineNumbers, highlightedLines, focusHighlightedLines,
            diffDecorations, annotations, metadata, gradientPreset,
            backgroundStyle, fontName, fontLigatures, exportScale, exportFormat,
            colorProfile, richClipboard, selectedPreset,
        ]
    }

    // MARK: - Defensive reads

    /// Builds a `SnapshotConfig` from `defaults`, tolerating any missing or
    /// wrongly-typed key. Each branch only overrides a default when a valid
    /// value is present; numeric values are clamped to their documented ranges.
    static func readConfig(from defaults: UserDefaults) -> SnapshotConfig {
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
        // Window-title text is normalized on the way into the renderer, so an
        // all-whitespace stored value reads as "no title".
        if let value = defaults.string(forKey: Keys.windowTitle) {
            config.windowTitle = value
        }
        if let value = defaults.object(forKey: Keys.showShadow) as? Bool {
            config.showShadow = value
        }
        if let value = defaults.object(forKey: Keys.showLineNumbers) as? Bool {
            config.showLineNumbers = value
        }
        if let value = defaults.object(forKey: Keys.focusHighlightedLines) as? Bool {
            config.focusHighlightedLines = value
        }
        if let value = defaults.object(forKey: Keys.diffDecorations) as? Bool {
            config.diffDecorations = value
        }
        // Highlighted lines persist as the canonical spec string ("3, 7-9"); a
        // missing or malformed value parses to no highlight rather than trapping
        // (CS-021 / CS-050).
        if let spec = defaults.string(forKey: Keys.highlightedLines) {
            config.highlightedLineRanges = LineHighlight.parse(spec)
        }
        config.annotations = readAnnotations(from: defaults)
        if let metadata = readMetadata(from: defaults) {
            config.metadata = metadata
        }
        if let background = readBackground(from: defaults) {
            config.background = background
        }
        return config
    }

    /// Reads the persisted annotations, tolerating a missing or corrupt value
    /// (CS-083 / CS-050). Stored as a JSON-encoded `[Annotation]`; a garbage blob
    /// (or any single un-decodable element) yields the empty default — annotations
    /// are non-critical chrome, so a bad store degrades to "no marks" rather than
    /// failing the whole read.
    static func readAnnotations(from defaults: UserDefaults) -> [Annotation] {
        guard let data = defaults.data(forKey: Keys.annotations),
            let decoded = try? JSONDecoder().decode([Annotation].self, from: data)
        else { return [] }
        return decoded
    }

    /// Reads the persisted metadata header, tolerating a missing or corrupt value
    /// (CS-022 / CS-050). Stored as a JSON-encoded `SnapshotMetadata`; a garbage
    /// blob simply yields `nil`, leaving the empty default (no header) in place.
    /// `SnapshotMetadata`'s decoder re-normalizes its text fields, so an empty or
    /// untrimmed persisted string can never reach the renderer.
    static func readMetadata(from defaults: UserDefaults) -> SnapshotMetadata? {
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
    static func readBackground(from defaults: UserDefaults) -> BackgroundStyle? {
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

    /// Reads the persisted social card, tolerating a missing or corrupt value
    /// (CS-041 / CS-050). Stored as a JSON-encoded `SocialCardModel`; a garbage
    /// blob yields a fresh default card. The model's decoder re-normalizes its
    /// text fields, re-truncates the excerpt, and re-clamps the font size, so an
    /// out-of-range or hand-edited value can never reach the renderer.
    static func readSocialCard(from defaults: UserDefaults) -> SocialCardModel {
        guard let data = defaults.data(forKey: Keys.socialCard),
            let decoded = try? JSONDecoder().decode(SocialCardModel.self, from: data)
        else { return SocialCardModel() }
        return decoded
    }

    /// Reads the export scale, clamping a stored value into the supported set and
    /// falling back to the default for a missing or non-integer value.
    static func readExportScale(from defaults: UserDefaults) -> Int {
        guard let value = defaults.object(forKey: Keys.exportScale) as? Int else {
            return SettingsDefaults.exportScale
        }
        return SettingsDefaults.clampExportScale(value)
    }

    // MARK: - Writes

    /// Persists every styled field of `config` into `defaults`, the write side of
    /// `readConfig`. The metadata header and background are JSON-encoded through their
    /// own helpers so every kind round-trips.
    static func persistStyle(_ config: SnapshotConfig, to defaults: UserDefaults) {
        defaults.set(config.theme.id, forKey: Keys.themeID)
        defaults.set(config.language.rawValue, forKey: Keys.languageID)
        defaults.set(config.fontName, forKey: Keys.fontName)
        defaults.set(config.fontLigatures, forKey: Keys.fontLigatures)
        defaults.set(config.fontSize, forKey: Keys.fontSize)
        defaults.set(config.padding, forKey: Keys.padding)
        defaults.set(config.cornerRadius, forKey: Keys.cornerRadius)
        defaults.set(config.showChrome, forKey: Keys.showChrome)
        defaults.set(config.windowTitle, forKey: Keys.windowTitle)
        defaults.set(config.showShadow, forKey: Keys.showShadow)
        defaults.set(config.showLineNumbers, forKey: Keys.showLineNumbers)
        defaults.set(config.focusHighlightedLines, forKey: Keys.focusHighlightedLines)
        defaults.set(config.diffDecorations, forKey: Keys.diffDecorations)
        defaults.set(
            LineHighlight.describe(config.highlightedLineRanges), forKey: Keys.highlightedLines)
        persistAnnotations(config.annotations, to: defaults)
        persistMetadata(config.metadata, to: defaults)
        persistBackground(config.background, to: defaults)
    }

    /// Persists the annotations as a JSON-encoded `[Annotation]` so every mark's
    /// kind, normalized geometry, text, and color round-trip (CS-083). An empty
    /// array clears the key so the store has no stale value and a later read
    /// restores the default (no marks); an unexpected encode failure also drops the
    /// key rather than leaving a stale blob behind.
    static func persistAnnotations(_ annotations: [Annotation], to defaults: UserDefaults) {
        guard !annotations.isEmpty, let data = try? JSONEncoder().encode(annotations) else {
            defaults.removeObject(forKey: Keys.annotations)
            return
        }
        defaults.set(data, forKey: Keys.annotations)
    }

    /// Persists the metadata header as a JSON-encoded `SnapshotMetadata` so its
    /// fields round-trip (CS-022). An empty header clears the key so the store has
    /// no stale value and the default (no header) is what a later read restores;
    /// an unexpected encode failure also drops the key rather than leaving a stale
    /// blob behind.
    static func persistMetadata(_ metadata: SnapshotMetadata, to defaults: UserDefaults) {
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
    static func persistBackground(_ background: BackgroundStyle, to defaults: UserDefaults) {
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

    /// Persists the social card as a JSON-encoded `SocialCardModel` so every field
    /// round-trips (CS-041). An encode failure drops the key so a later read restores
    /// a fresh default card rather than leaving a stale blob behind.
    static func persistSocialCard(_ card: SocialCardModel, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(card) else {
            defaults.removeObject(forKey: Keys.socialCard)
            Log.settings.error("Social card encode failed; persisting default on next change")
            return
        }
        defaults.set(data, forKey: Keys.socialCard)
    }
}
