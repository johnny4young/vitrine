import Foundation

/// Versioning and migration for the persisted preferences schema (CS-050).
///
/// `AppSettings` reads many `UserDefaults` keys directly. As the schema grows
/// (presets, themes, backgrounds), unversioned reads risk silent breakage or
/// crashes on stale or corrupt data. `SettingsSchema` records a schema version
/// in `UserDefaults` and runs an ordered, **pure** sequence of migrations so an
/// upgrade can repair or reshape old data once, before the typed reads run.
///
/// The migration step is deliberately free of side effects beyond the passed
/// `UserDefaults`: it does not touch `AppSettings`, the file system, or any
/// shared singleton, which keeps it trivial to unit-test with fixtures from
/// older versions.
enum SettingsSchema {
    /// The current schema version. Bump this whenever the meaning, type, or set
    /// of persisted keys changes, and add a matching `Migration` below.
    ///
    /// Version history:
    /// - `1`: the original, *unversioned* layout (no version key was written).
    ///   Any install that predates CS-050 reports this version.
    /// - `2`: CS-050 — introduces the version key and normalizes a few values
    ///   that earlier builds could persist out of range or with names that no
    ///   longer resolve (`exportScale`, `gradientPreset`).
    /// - `3`: CS-051 — backgrounds gain solid/custom-gradient/image kinds and are
    ///   persisted as a single JSON-encoded `backgroundStyle`. A pre-CS-051 store
    ///   only ever wrote a `gradientPreset` name; that name is still honored as a
    ///   read-time fallback, so no value migration is required here.
    /// - `4`: CS-052 — adds the opt-in `fontLigatures` flag. A new boolean key with
    ///   a documented default (off) needs no data transform; a store predating it
    ///   simply reads the default, so this step only advances the version.
    /// - `5`: CS-030 — adds saved style presets, persisted as a single JSON blob
    ///   under `userStylePresets`. It is a brand-new key with a documented default
    ///   (no user presets); an older store simply has no value for it, so this step
    ///   only advances the version.
    /// - `6`: CS-035 — adds the first-run quick-start completion flag
    ///   (`hasSeenWelcome`). A new boolean key with a documented default (false, i.e.
    ///   "not yet shown") needs no data transform; a store predating it simply reads
    ///   the default, so this step only advances the version.
    /// - `7`: CS-049 — adds the last-seen "What's New" version key
    ///   (`lastSeenWhatsNewVersion`). A new optional string key with a documented
    ///   default (nil, treated as a clean first run) needs no data transform; a store
    ///   predating it simply has no value, so this step only advances the version.
    /// - `8`: CS-044 — adds the web URL-capture viewport and wait settings
    ///   (`webViewportKind`, `webCustomViewportWidth`, `webCustomViewportHeight`,
    ///   `webCaptureMode`, `webWaitKind`, `webWaitSeconds`). All brand-new keys with
    ///   documented defaults; an older store simply has no value for them and reads
    ///   the defaults, so this step only advances the version.
    /// - `9`: CS-044 (multi-resolution) — adds the `webViewports` multi-capture set.
    ///   A brand-new key with a documented default (falls back to the single
    ///   `webViewportKind`); an older store has no value for it and falls back, so this
    ///   step only advances the version.
    /// - `10`: CS-092 — adds Brand Kit persistence (`brandKit`, `brandKitEnabled`).
    ///   Both are brand-new keys with documented defaults (empty kit, disabled), so an
    ///   older store simply has no value and reads the defaults; this step only
    ///   advances the version.
    static let current = 10

    /// The `UserDefaults` key that stores the persisted schema version.
    static let versionKey = "settingsSchemaVersion"

    /// The version assumed for an install that has never recorded one. Existing
    /// pre-CS-050 users fall here and are migrated forward on first launch.
    static let legacyVersion = 1

    /// Reads the stored schema version, tolerating a missing or garbage value.
    ///
    /// A brand-new install (no preferences written yet) is treated as already
    /// current so we do not run legacy repairs against empty defaults. An
    /// install that has data but no version key is treated as `legacyVersion`.
    static func storedVersion(in defaults: UserDefaults) -> Int {
        if let version = defaults.object(forKey: versionKey) as? Int { return version }
        // No version key. If the store is otherwise empty this is a fresh
        // install; otherwise it is a pre-versioning ("legacy") layout.
        return hasAnyKnownKey(in: defaults) ? legacyVersion : current
    }

    /// Brings `defaults` up to `current`, running every intervening migration in
    /// order, then records the new version. Safe to call on every launch: when
    /// the store is already current it only ensures the version key is present.
    ///
    /// - Returns: the version the store was migrated *from* (useful for tests
    ///   and logging).
    @discardableResult
    static func migrateToCurrent(_ defaults: UserDefaults) -> Int {
        let from = storedVersion(in: defaults)
        migrate(defaults: defaults, from: from, to: current)
        return from
    }

    /// Pure, ordered migration from `from` to `to`.
    ///
    /// Each step is applied exactly once and in ascending version order, so the
    /// transform from any older version to the current one is deterministic.
    /// Downgrades (`from > to`) and no-ops (`from == to`) only stamp the target
    /// version; we never attempt to "un-migrate" because older code cannot read
    /// a newer layout anyway.
    static func migrate(defaults: UserDefaults, from: Int, to: Int) {
        if from < to {
            for migration in migrations where migration.from >= from && migration.to <= to {
                migration.apply(defaults)
            }
        }
        defaults.set(to, forKey: versionKey)
    }

    /// A single ordered transform that upgrades the store by one version.
    private struct Migration {
        let from: Int
        let to: Int
        let apply: (UserDefaults) -> Void
    }

    /// The full ordered migration chain. Add a new entry (and bump `current`)
    /// whenever a key's type, range, or meaning changes.
    private static let migrations: [Migration] = [
        // v1 → v2: earlier builds had no validation on these reads, so a hand-
        // edited or corrupted store could hold an out-of-range export scale or a
        // gradient name that no longer maps to a `GradientPreset`. Normalize both
        // once so the live, typed reads always see clean values.
        Migration(from: 1, to: 2) { defaults in
            if defaults.object(forKey: LegacyKeys.exportScale) != nil {
                let clamped = SettingsDefaults.clampExportScale(
                    defaults.integer(forKey: LegacyKeys.exportScale))
                defaults.set(clamped, forKey: LegacyKeys.exportScale)
            }
            if let raw = defaults.string(forKey: LegacyKeys.gradientPreset),
                GradientPreset(rawValue: raw) == nil
            {
                // An unrecognized preset name would otherwise be ignored on read
                // and silently fall back; remove it so the store stays clean and
                // the default applies explicitly.
                defaults.removeObject(forKey: LegacyKeys.gradientPreset)
            }
        },
        // v2 → v3: CS-051 expands backgrounds (solid/custom-gradient/image) and
        // persists them as a JSON `backgroundStyle`. Any legacy `gradientPreset`
        // name is still read as a fallback by `AppSettings` and is re-encoded
        // into the new key on the next style change, so this step needs no data
        // transform; it only advances the version.
        Migration(from: 2, to: 3) { _ in },
        // v3 → v4: CS-052 adds the opt-in `fontLigatures` flag. It is a brand-new
        // boolean key with a documented default (off); an older store simply has
        // no value for it and reads the default, so there is nothing to transform.
        Migration(from: 3, to: 4) { _ in },
        // v4 → v5: CS-030 adds saved style presets under `userStylePresets`. It is
        // a brand-new JSON key with a documented default (no presets); an older
        // store simply has no value for it, so there is nothing to transform.
        Migration(from: 4, to: 5) { _ in },
        // v5 → v6: CS-035 adds the first-run quick-start flag `hasSeenWelcome`. It is
        // a brand-new boolean key with a documented default (false); an older store
        // simply has no value for it and reads the default, so there is nothing to
        // transform. An upgrading user has clearly already used the app, but it is
        // harmless and on-brand for the lightweight quick-start to appear once after
        // the upgrade, so the flag is intentionally left at its default rather than
        // back-filled to true here.
        Migration(from: 5, to: 6) { _ in },
        // v6 → v7: CS-049 adds the last-seen "What's New" version key
        // `lastSeenWhatsNewVersion`. It is a brand-new optional string key with a
        // documented default (nil); an older store simply has no value for it and
        // reads the default, so there is nothing to transform. The default (nil) is
        // intentionally left in place: on the next launch the What's New gate treats
        // an upgrading user the same as a clean install for one cycle — it stamps the
        // current version as seen rather than showing notes for a version they were
        // effectively already running — so the surface first appears on the upgrade
        // *after* this one.
        Migration(from: 6, to: 7) { _ in },
        // v7 → v8: CS-044 adds the web URL-capture viewport and wait settings
        // (`webViewportKind`, `webCustomViewportWidth`, `webCustomViewportHeight`,
        // `webCaptureMode`, `webWaitKind`, `webWaitSeconds`). All brand-new keys with
        // documented defaults; an older store simply has no value for them and reads
        // the defaults via `WebDefaults`, so there is nothing to transform.
        Migration(from: 7, to: 8) { _ in },
        // v8 → v9: CS-044 (multi-resolution) adds the `webViewports` multi-capture set.
        // A brand-new key with a documented default (falls back to the single
        // viewport); an older store has no value for it, so there is nothing to
        // transform.
        Migration(from: 8, to: 9) { _ in },
        // v9 → v10: CS-092 adds the Brand Kit JSON blob and "apply to captures"
        // switch. Both are additive keys with documented defaults (`BrandKit()` and
        // disabled), so there is no data to transform.
        Migration(from: 9, to: 10) { _ in },
    ]

    /// Whether the store holds any key this app is known to write. Used to tell a
    /// fresh install (skip legacy migration) apart from a pre-versioning one.
    private static func hasAnyKnownKey(in defaults: UserDefaults) -> Bool {
        LegacyKeys.all.contains { defaults.object(forKey: $0) != nil }
    }

    /// Key names referenced by migrations. Kept here, separate from
    /// `SettingsCodec.Keys`, so migration logic does not depend on the live
    /// settings type and stays purely about the on-disk shape.
    private enum LegacyKeys {
        static let exportScale = "exportScale"
        static let gradientPreset = "gradientPreset"

        /// Every key a non-CS-050 build of the app could have written. Presence
        /// of any of these (without a version key) marks a legacy store.
        static let all = [
            "themeID", "languageID", "fontSize", "padding", "cornerRadius",
            "showChrome", "showShadow", "gradientPreset", "autoCopy",
            "alsoSaveToFile", "exportScale", "exportFormat", "hotkeyAction",
            "treatURLsAsScreenshot", "recentLanguages", "fontName", "selectedPreset",
        ]
    }
}

/// Canonical default values and clamping rules for persisted settings (CS-050).
///
/// Centralizing these keeps the "documented fallback" for each typed read in one
/// place and lets both `AppSettings` and `SettingsSchema` agree on what a valid
/// value looks like. Ranges mirror the controls in the Style and Output panes.
enum SettingsDefaults {
    /// Allowed export resolution multipliers (Output pane).
    static let exportScaleRange = 1...3
    static let exportScale = 2

    /// Font-size slider bounds (Style pane), in points.
    static let fontSizeRange = 10.0...20.0
    static let fontSize = SnapshotConfig().fontSize

    /// Padding slider bounds (Style pane), in points.
    static let paddingRange = 16.0...64.0
    static let padding = SnapshotConfig().padding

    /// Sane bounds for the code-card corner radius. The Style pane does not yet
    /// expose this, but persisted/hand-edited values are still clamped so a wild
    /// number cannot distort the render.
    static let cornerRadiusRange = 0.0...48.0
    static let cornerRadius = SnapshotConfig().cornerRadius

    static func clampExportScale(_ value: Int) -> Int {
        guard value >= exportScaleRange.lowerBound else { return exportScale }
        return min(value, exportScaleRange.upperBound)
    }

    static func clampFontSize(_ value: Double) -> Double {
        clamp(value, to: fontSizeRange, fallback: fontSize)
    }

    static func clampPadding(_ value: Double) -> Double {
        clamp(value, to: paddingRange, fallback: padding)
    }

    static func clampCornerRadius(_ value: Double) -> Double {
        clamp(value, to: cornerRadiusRange, fallback: cornerRadius)
    }

    /// Clamps `value` into `range`, replacing a non-finite (NaN/∞) value with
    /// `fallback` so corrupt floating-point data can never reach the renderer.
    private static func clamp(
        _ value: Double, to range: ClosedRange<Double>, fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
