import Foundation
import Testing

@testable import Vitrine

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "VitrineMigrationTests-\(UUID().uuidString)")!
}

/// A `UserDefaults` that counts value writes routed through `set(_:forKey:)`. Every
/// `persistStyle` run writes several string keys (theme id, language, font) through
/// this overload, so a non-zero delta means the style block was persisted — the hook
/// the Perf-7 test uses to assert a code-only edit does not persist.
///
/// `nonisolated` so its overrides match the `nonisolated` `UserDefaults` members under
/// the module's MainActor-default isolation (it is used synchronously on the main
/// actor by the test).
private nonisolated final class WriteCountingDefaults: UserDefaults {
    private(set) var writeCount = 0
    override func set(_ value: Any?, forKey defaultName: String) {
        writeCount += 1
        super.set(value, forKey: defaultName)
    }
}

// MARK: - Schema versioning

@Suite("SettingsSchema versioning")
struct SettingsSchemaVersioningTests {
    @Test func emptyStoreIsTreatedAsCurrentAndStampsVersion() {
        let defaults = freshDefaults()
        // A brand-new install has no keys at all and should not run legacy
        // repairs; it is already current.
        #expect(SettingsSchema.storedVersion(in: defaults) == SettingsSchema.current)

        let from = SettingsSchema.migrateToCurrent(defaults)
        #expect(from == SettingsSchema.current)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
    }

    @Test func storeWithDataButNoVersionIsLegacy() {
        let defaults = freshDefaults()
        // Simulate a pre-CS-050 install: real settings keys exist, no version.
        defaults.set("dracula", forKey: "themeID")
        #expect(SettingsSchema.storedVersion(in: defaults) == SettingsSchema.legacyVersion)
    }

    @Test func garbageVersionValueFallsBackSafely() {
        let defaults = freshDefaults()
        defaults.set("not-an-int", forKey: SettingsSchema.versionKey)
        defaults.set("dracula", forKey: "themeID")
        // A non-integer version is ignored; the presence of data marks it legacy.
        #expect(SettingsSchema.storedVersion(in: defaults) == SettingsSchema.legacyVersion)
    }

    @Test func migrationIsIdempotent() {
        let defaults = freshDefaults()
        defaults.set("dracula", forKey: "themeID")

        let first = SettingsSchema.migrateToCurrent(defaults)
        #expect(first == SettingsSchema.legacyVersion)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)

        // Running again is a no-op migration that only re-stamps the version.
        let second = SettingsSchema.migrateToCurrent(defaults)
        #expect(second == SettingsSchema.current)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
    }

    @Test func migrateIsPureToThePassedStore() {
        let a = freshDefaults()
        let b = freshDefaults()
        a.set("dracula", forKey: "themeID")
        SettingsSchema.migrate(defaults: a, from: 1, to: 2)
        // Migrating `a` must not touch an unrelated store.
        #expect(b.object(forKey: SettingsSchema.versionKey) == nil)
    }

    @Test func sameVersionMigrationOnlyStampsVersion() {
        let defaults = freshDefaults()
        // A v2 store with an out-of-range scale: a no-op (from == to) migration
        // must not re-run the v1→v2 repair, only (re-)stamp the version. The
        // defensive reads in AppSettings — not the migration — clean an
        // already-current store, so the raw value is left exactly as-is here.
        defaults.set(99, forKey: "exportScale")
        SettingsSchema.migrate(defaults: defaults, from: 2, to: 2)
        #expect(defaults.integer(forKey: "exportScale") == 99)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == 2)
    }

    @Test func futureVersionStoreIsNotDowngradedOrMutated() {
        let defaults = freshDefaults()
        // A store written by a newer build (version ahead of `current`). Older
        // code cannot reshape a newer layout, so migrating to `current` must not
        // run any migration step or disturb the data — it only records the
        // target version. This keeps a forward-then-back launch loss-free.
        let future = SettingsSchema.current + 5
        defaults.set(future, forKey: SettingsSchema.versionKey)
        defaults.set(99, forKey: "exportScale")
        defaults.set("a-future-only-key", forKey: "someUnknownFutureKey")

        SettingsSchema.migrate(defaults: defaults, from: future, to: SettingsSchema.current)

        // The export scale is untouched (no v1→v2 repair ran) and the unknown
        // future key survives intact.
        #expect(defaults.integer(forKey: "exportScale") == 99)
        #expect(defaults.string(forKey: "someUnknownFutureKey") == "a-future-only-key")
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
    }

    @Test func storedVersionReadsBackAFutureVersion() {
        let defaults = freshDefaults()
        let future = SettingsSchema.current + 5
        defaults.set(future, forKey: SettingsSchema.versionKey)
        // A valid integer version ahead of `current` is reported verbatim, not
        // mistaken for a legacy or fresh store.
        #expect(SettingsSchema.storedVersion(in: defaults) == future)
    }
}

// MARK: - v1 → v2 migration fixtures

@Suite("SettingsSchema v1 → v2 migration")
struct SettingsSchemaV1ToV2Tests {
    @Test func clampsOutOfRangeExportScale() {
        let defaults = freshDefaults()
        // Fixture from a v1 store: an export scale far outside the supported set.
        defaults.set(99, forKey: "exportScale")

        SettingsSchema.migrate(defaults: defaults, from: 1, to: 2)

        #expect(
            defaults.integer(forKey: "exportScale") == SettingsDefaults.exportScaleRange.upperBound)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == 2)
    }

    @Test func raisesZeroExportScaleToDefault() {
        let defaults = freshDefaults()
        defaults.set(0, forKey: "exportScale")
        SettingsSchema.migrate(defaults: defaults, from: 1, to: 2)
        #expect(defaults.integer(forKey: "exportScale") == SettingsDefaults.exportScale)
    }

    @Test func leavesValidExportScaleUntouched() {
        let defaults = freshDefaults()
        defaults.set(3, forKey: "exportScale")
        SettingsSchema.migrate(defaults: defaults, from: 1, to: 2)
        #expect(defaults.integer(forKey: "exportScale") == 3)
    }

    @Test func dropsUnknownGradientPreset() {
        let defaults = freshDefaults()
        // A gradient name that no longer maps to a `GradientPreset`.
        defaults.set("Retired Preset", forKey: "gradientPreset")
        SettingsSchema.migrate(defaults: defaults, from: 1, to: 2)
        #expect(defaults.string(forKey: "gradientPreset") == nil)
    }

    @Test func keepsKnownGradientPreset() {
        let defaults = freshDefaults()
        defaults.set(GradientPreset.ocean.rawValue, forKey: "gradientPreset")
        SettingsSchema.migrate(defaults: defaults, from: 1, to: 2)
        #expect(defaults.string(forKey: "gradientPreset") == GradientPreset.ocean.rawValue)
    }

    @Test func doesNotInventKeysForEmptyStore() {
        let defaults = freshDefaults()
        SettingsSchema.migrate(defaults: defaults, from: 1, to: 2)
        // The migration only repairs keys that already exist.
        #expect(defaults.object(forKey: "exportScale") == nil)
        #expect(defaults.object(forKey: "gradientPreset") == nil)
    }

    @Test func preservesKeysTheMigrationDoesNotTouch() {
        let defaults = freshDefaults()
        // A v1 store carrying both a known setting and a key this migration has
        // no rule for. Migration must leave both intact: it only normalizes the
        // values it explicitly targets and never discards unrelated data
        // (CS-050: "unknown future keys are preserved without data loss").
        defaults.set("dracula", forKey: "themeID")
        defaults.set("a-future-only-key", forKey: "someUnknownFutureKey")

        SettingsSchema.migrate(defaults: defaults, from: 1, to: 2)

        #expect(defaults.string(forKey: "themeID") == "dracula")
        #expect(defaults.string(forKey: "someUnknownFutureKey") == "a-future-only-key")
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == 2)
    }
}

// MARK: - SettingsDefaults clamping

@Suite("SettingsDefaults clamping")
struct SettingsDefaultsTests {
    @Test func clampsExportScale() {
        #expect(SettingsDefaults.clampExportScale(2) == 2)
        #expect(SettingsDefaults.clampExportScale(0) == SettingsDefaults.exportScale)
        #expect(SettingsDefaults.clampExportScale(-5) == SettingsDefaults.exportScale)
        #expect(SettingsDefaults.clampExportScale(100) == 3)
    }

    @Test func clampsFontSize() {
        #expect(SettingsDefaults.clampFontSize(14) == 14)
        #expect(SettingsDefaults.clampFontSize(2) == SettingsDefaults.fontSizeRange.lowerBound)
        #expect(SettingsDefaults.clampFontSize(999) == SettingsDefaults.fontSizeRange.upperBound)
    }

    @Test func replacesNonFiniteWithFallback() {
        #expect(SettingsDefaults.clampFontSize(.nan) == SettingsDefaults.fontSize)
        #expect(SettingsDefaults.clampPadding(.infinity) == SettingsDefaults.padding)
        #expect(SettingsDefaults.clampCornerRadius(-.infinity) == SettingsDefaults.cornerRadius)
    }

    @Test func clampsPaddingAndCornerRadius() {
        #expect(SettingsDefaults.clampPadding(8) == SettingsDefaults.paddingRange.lowerBound)
        #expect(SettingsDefaults.clampPadding(200) == SettingsDefaults.paddingRange.upperBound)
        #expect(
            SettingsDefaults.clampCornerRadius(-1) == SettingsDefaults.cornerRadiusRange.lowerBound)
        #expect(
            SettingsDefaults.clampCornerRadius(500) == SettingsDefaults.cornerRadiusRange.upperBound
        )
    }
}

// MARK: - AppSettings resilience to corrupt / partial defaults

@MainActor
@Suite("AppSettings migration resilience")
struct AppSettingsMigrationTests {
    @Test func loadsFromEmptyDefaultsWithoutCrashing() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.exportScale == SettingsDefaults.exportScale)
        #expect(settings.exportFormat == .png)
        #expect(settings.hotkeyAction == .quickCapture)
        #expect(settings.autoCopy)
        #expect(settings.config.theme.id == Theme.oneDark.id)
        #expect(settings.config.fontName == CodeFont.default)
    }

    @Test func typingOnlyCodeDoesNotRepersistTheStyleBlock() {
        let defaults = WriteCountingDefaults(suiteName: "VitrinePerf-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let baseline = defaults.writeCount

        // A code-only change (a keystroke) must not churn the persisted style block —
        // `persistStyle` never writes `code` (audit Perf-7).
        settings.config.code = "let answer = 42"
        #expect(defaults.writeCount == baseline)

        // A real style change still persists.
        settings.config.padding = 40
        #expect(defaults.writeCount > baseline)
    }

    @Test func toleratesWronglyTypedValues() {
        let defaults = freshDefaults()
        // Every typed key holds a value of the wrong type.
        defaults.set("not-a-number", forKey: "fontSize")
        defaults.set("not-a-number", forKey: "padding")
        defaults.set("not-a-number", forKey: "cornerRadius")
        defaults.set("not-an-int", forKey: "exportScale")
        defaults.set(42, forKey: "showChrome")
        defaults.set("yes", forKey: "autoCopy")
        defaults.set("bogus-theme", forKey: "themeID")
        defaults.set("bogus-language", forKey: "languageID")
        defaults.set("Comic Sans", forKey: "fontName")
        defaults.set("bogus-format", forKey: "exportFormat")
        defaults.set("bogus-action", forKey: "hotkeyAction")
        defaults.set(["bogus-lang", "swift"], forKey: "recentLanguages")

        let settings = AppSettings(defaults: defaults)

        // Numeric reads fall back to documented defaults.
        #expect(settings.config.fontSize == SnapshotConfig().fontSize)
        #expect(settings.config.padding == SnapshotConfig().padding)
        #expect(settings.config.cornerRadius == SnapshotConfig().cornerRadius)
        #expect(settings.exportScale == SettingsDefaults.exportScale)
        // Wrong-typed bools fall back to their defaults.
        #expect(settings.config.showChrome)
        #expect(settings.autoCopy)
        // Unrecognized enum / catalog values fall back.
        #expect(settings.config.theme.id == Theme.oneDark.id)
        #expect(settings.config.language == .swift)
        #expect(settings.config.fontName == CodeFont.default)
        #expect(settings.exportFormat == .png)
        #expect(settings.hotkeyAction == .quickCapture)
        // The one valid recent language survives; the bogus one is dropped.
        #expect(settings.recentLanguages == [.swift])
    }

    @Test func clampsOutOfRangePersistedNumbers() {
        let defaults = freshDefaults()
        defaults.set(999.0, forKey: "fontSize")
        defaults.set(2.0, forKey: "padding")
        defaults.set(99, forKey: "exportScale")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.config.fontSize == SettingsDefaults.fontSizeRange.upperBound)
        #expect(settings.config.padding == SettingsDefaults.paddingRange.lowerBound)
        #expect(settings.exportScale == SettingsDefaults.exportScaleRange.upperBound)
    }

    @Test func migratesLegacyStoreOnInit() {
        let defaults = freshDefaults()
        // Pre-CS-050 store: data present, no version, an out-of-range scale.
        defaults.set(99, forKey: "exportScale")
        defaults.set("dracula", forKey: "themeID")

        let settings = AppSettings(defaults: defaults)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
        #expect(settings.exportScale == SettingsDefaults.exportScaleRange.upperBound)
        #expect(settings.config.theme.id == "dracula")
    }

    @Test func partialDefaultsKeepUnsetValuesAtDefault() {
        let defaults = freshDefaults()
        // Only a couple of keys are set; the rest must stay at their defaults.
        defaults.set("github", forKey: "themeID")
        defaults.set(48.0, forKey: "padding")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.config.theme.id == "github")
        #expect(settings.config.padding == 48)
        #expect(settings.config.fontSize == SnapshotConfig().fontSize)
        #expect(settings.exportFormat == .png)
        #expect(settings.config.showChrome)
    }

    @Test func toleratesCorruptValuesInAnAlreadyCurrentStore() {
        let defaults = freshDefaults()
        // A store already stamped at the current schema version (so no migration
        // runs) but holding out-of-range and wrongly-typed values — e.g. after a
        // later build wrote a new version and the user hand-edited the plist.
        // The defensive reads, not the migration, are the safety net here.
        defaults.set(SettingsSchema.current, forKey: SettingsSchema.versionKey)
        defaults.set(99, forKey: "exportScale")
        defaults.set(999.0, forKey: "fontSize")
        defaults.set("not-a-number", forKey: "padding")
        defaults.set("bogus-theme", forKey: "themeID")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.exportScale == SettingsDefaults.exportScaleRange.upperBound)
        #expect(settings.config.fontSize == SettingsDefaults.fontSizeRange.upperBound)
        #expect(settings.config.padding == SnapshotConfig().padding)
        #expect(settings.config.theme.id == Theme.oneDark.id)
        // The version was already current, so it is left in place.
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
    }

    @Test func initPreservesUnknownKeysWhileMigratingLegacyStore() {
        let defaults = freshDefaults()
        // A legacy store (data, no version) that also carries a key this build
        // does not know about. Constructing AppSettings migrates the store but
        // must not drop the unrelated key.
        defaults.set("dracula", forKey: "themeID")
        defaults.set("keep-me", forKey: "someUnknownFutureKey")

        _ = AppSettings(defaults: defaults)

        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
        #expect(defaults.string(forKey: "someUnknownFutureKey") == "keep-me")
    }
}

// MARK: - Reset behavior

@MainActor
@Suite("AppSettings reset to defaults")
struct AppSettingsResetTests {
    @Test func resetRestoresDefaultsInMemory() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.hotkeyAction = .openEditor
        settings.exportFormat = .pdf
        settings.exportScale = 3
        settings.autoCopy = false
        settings.treatURLsAsScreenshot = true
        settings.config.theme = .dracula
        settings.config.padding = 64
        settings.noteLanguageUsed(.python)

        settings.resetToDefaults()

        #expect(settings.hotkeyAction == .quickCapture)
        #expect(settings.exportFormat == .png)
        #expect(settings.exportScale == SettingsDefaults.exportScale)
        #expect(settings.autoCopy)
        #expect(!settings.treatURLsAsScreenshot)
        #expect(settings.config.theme.id == Theme.oneDark.id)
        #expect(settings.config.padding == SnapshotConfig().padding)
        #expect(settings.recentLanguages.isEmpty)
    }

    @Test func resetPersistsSoAFreshInstanceSeesDefaults() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.exportFormat = .pdf
        first.config.theme = .dracula
        first.resetToDefaults()

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.exportFormat == .png)
        #expect(reloaded.config.theme.id == Theme.oneDark.id)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
    }
}

// MARK: - Round-trip stability

@MainActor
@Suite("AppSettings round-trip stability")
struct AppSettingsRoundTripTests {
    @Test func reloadingDoesNotMutateCleanValues() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.exportFormat = .pdf
        first.exportScale = 3
        first.hotkeyAction = .openEditor
        first.treatURLsAsScreenshot = true
        first.config.theme = .monokai
        first.config.language = .python
        first.config.fontName = "Fira Code"
        first.config.fontSize = 16
        first.config.padding = 40
        first.config.showChrome = false
        first.config.showShadow = false
        first.config.background = .gradient(.sunset)

        // Reload twice: values must be stable across repeated load cycles.
        let second = AppSettings(defaults: defaults)
        let third = AppSettings(defaults: defaults)

        for reloaded in [second, third] {
            #expect(reloaded.exportFormat == .pdf)
            #expect(reloaded.exportScale == 3)
            #expect(reloaded.hotkeyAction == .openEditor)
            #expect(reloaded.treatURLsAsScreenshot)
            #expect(reloaded.config.theme.id == "monokai")
            #expect(reloaded.config.language == .python)
            #expect(reloaded.config.fontName == "Fira Code")
            #expect(reloaded.config.fontSize == 16)
            #expect(reloaded.config.padding == 40)
            #expect(!reloaded.config.showChrome)
            #expect(!reloaded.config.showShadow)
            #expect(reloaded.config.background == .gradient(.sunset))
        }
    }

    @Test func versionKeyStaysCurrentAcrossReloads() {
        let defaults = freshDefaults()
        _ = AppSettings(defaults: defaults)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
        _ = AppSettings(defaults: defaults)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
    }

    /// The opt-in `fontLigatures` flag survives a persist→reload cycle, writing
    /// through to the store and reading back unchanged (CS-052). It defaults to
    /// `false`, so flipping it on is the only way to prove the new key is actually
    /// persisted and restored — a read that ignored the key would silently keep the
    /// default and slip past every other test, which never sets this flag.
    @Test func fontLigaturesRoundTripsWhenEnabled() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.config.fontLigatures == false)  // documented default

        first.config.fontLigatures = true
        // The toggle is written through to the backing store, not just held in
        // memory, so a separate instance can see it.
        #expect(defaults.object(forKey: "fontLigatures") as? Bool == true)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.config.fontLigatures, "ligature flag was lost across reload")
    }

    /// Disabling the flag again persists the `false` and a reload honors it, so the
    /// read is genuinely value-driven rather than hard-wired to either constant
    /// (CS-052).
    @Test func fontLigaturesRoundTripsWhenDisabledAfterEnabling() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.config.fontLigatures = true
        first.config.fontLigatures = false
        #expect(defaults.object(forKey: "fontLigatures") as? Bool == false)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.config.fontLigatures == false, "ligature flag did not stay off")
    }
}

// MARK: - App UI language persistence

/// The Settings language switcher and its persistence (CS-047). macOS loads an app's
/// localization at launch from `AppleLanguages` in its preferences domain, so the
/// choice is stored both as the raw enum (to drive the picker) and as the
/// `AppleLanguages` override (to take effect on the next launch). These tests use an
/// isolated suite, so they never touch the real app's language.
@MainActor
@Suite("App UI language persistence · CS-047")
struct AppLanguagePersistenceTests {
    /// The raw key the choice is stored under and the system key macOS reads at launch.
    private static let languageKey = "appLanguage"
    private static let appleLanguagesKey = "AppleLanguages"

    /// Creates a named suite for tests that must inspect the suite's persisted domain
    /// directly, bypassing the host's NSArgumentDomain language pin.
    private static func freshLanguageDefaults() -> (suite: String, defaults: UserDefaults) {
        let suite = "VitrineMigrationTests-\(UUID().uuidString)"
        return (suite, UserDefaults(suiteName: suite)!)
    }

    /// Reads only what this app stored in its own preferences suite. `array(forKey:)`
    /// also sees the test scheme's `AppleLanguages=(en)` argument-domain override, which
    /// can mask whether CS-047 actually wrote or cleared the app-level override.
    private static func persistedAppleLanguages(
        in defaults: UserDefaults, suite: String
    )
        -> [String]?
    {
        defaults.persistentDomain(forName: suite)?[appleLanguagesKey] as? [String]
    }

    /// A clean install defaults to `.system` and persists nothing: construction reads the
    /// absent value without writing a choice or an app-level override back, so the app
    /// simply follows the system language order until the user picks otherwise. (`.system`
    /// resolves to the host's `AppleLanguages` list, which is inherited from the global
    /// domain and so is *not* `nil` here; the meaningful invariant is that the app wrote
    /// nothing.)
    @Test func defaultsToSystemWritesNothing() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.appLanguage == .system)
        #expect(defaults.string(forKey: Self.languageKey) == nil)
    }

    /// Choosing Spanish survives a close/open cycle: the choice is written through to the
    /// store, the `AppleLanguages` override is set so macOS loads Spanish next launch, and
    /// a fresh instance reads the choice back. This is the "persisted when the app is
    /// closed and reopened" guarantee the picker's footnote promises.
    @Test func spanishPersistsAndOverridesAppleLanguages() {
        let (suite, defaults) = Self.freshLanguageDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppSettings(defaults: defaults)

        first.appLanguage = .spanish
        #expect(defaults.string(forKey: Self.languageKey) == "spanish")
        // Read the suite's *persisted* override, not `array(forKey:)`: the test scheme
        // pins `AppleLanguages=(en)` in the host's NSArgumentDomain (project.yml), which
        // would otherwise mask what the app wrote. The persistent domain has only what
        // was stored in this suite.
        #expect(Self.persistedAppleLanguages(in: defaults, suite: suite) == ["es"])

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.appLanguage == .spanish, "language choice was lost across reload")
    }

    /// Pinning English writes the `en` override — the symmetric case to Spanish — so the
    /// app opens in English even when the system prefers another language.
    @Test func englishOverridesAppleLanguages() {
        let (suite, defaults) = Self.freshLanguageDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.appLanguage = .english
        #expect(Self.persistedAppleLanguages(in: defaults, suite: suite) == ["en"])
    }

    /// Returning to System clears the per-app override so the app follows the system
    /// language order again, and the cleared state survives a reload. The baseline is
    /// captured before any override so the assertion holds regardless of the host's
    /// language list (`AppleLanguages` is inherited from the global domain).
    @Test func systemClearsTheOverrideAndPersists() {
        let (suite, defaults) = Self.freshLanguageDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        // Read the suite's persisted override directly, bypassing the host-locale pin the
        // test scheme writes into the NSArgumentDomain (project.yml). A fresh suite has
        // stored no override yet (nil).
        let inherited = Self.persistedAppleLanguages(in: defaults, suite: suite)
        let first = AppSettings(defaults: defaults)

        first.appLanguage = .spanish
        #expect(Self.persistedAppleLanguages(in: defaults, suite: suite) == ["es"])

        first.appLanguage = .system
        #expect(
            Self.persistedAppleLanguages(in: defaults, suite: suite) == inherited,
            "clearing the override should remove it, falling back to the system list")

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.appLanguage == .system)
    }

    /// `resetToDefaults()` returns the language to `.system`, removes the override, and
    /// the reset persists so a fresh instance also sees System (CS-047/CS-050).
    @Test func resetReturnsLanguageToSystem() {
        let (suite, defaults) = Self.freshLanguageDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let inherited = Self.persistedAppleLanguages(in: defaults, suite: suite)
        let first = AppSettings(defaults: defaults)
        first.appLanguage = .spanish
        first.resetToDefaults()
        #expect(first.appLanguage == .system)
        #expect(Self.persistedAppleLanguages(in: defaults, suite: suite) == inherited)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.appLanguage == .system)
    }

    /// `AppLanguage.resolve` defends against a missing or corrupt persisted value by
    /// falling back to `.system`, and round-trips every valid raw value (CS-050).
    @Test func resolveIsDefensiveAndRoundTrips() {
        #expect(AppLanguage.resolve(nil) == .system)
        #expect(AppLanguage.resolve("not-a-language") == .system)
        for language in AppLanguage.allCases {
            #expect(AppLanguage.resolve(language.rawValue) == language)
        }
    }
}
