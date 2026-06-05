import Foundation
import Testing

@testable import Vitrine

/// First-run quick-start state and its persistence (CS-035).
///
/// The quick-start is gated by a single persisted flag, `AppSettings.hasSeenWelcome`,
/// stored in the app's defaults store. UI tests isolate that store with
/// `VITRINE_USER_DEFAULTS_SUITE`, so these unit tests use the same pattern (a fresh
/// suite per test) to prove the flag defaults to "first run", persists across
/// relaunches, and is cleared by a full reset.
private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "VitrineOnboardingTests-\(UUID().uuidString)")!
}

@MainActor
@Suite("Onboarding first-run flag")
struct OnboardingFirstRunTests {
    @Test func freshInstallIsTreatedAsFirstRun() {
        // A brand-new defaults suite has no value for the flag, so the app must
        // treat it as a first run and offer the quick-start.
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.hasSeenWelcome == false)
    }

    @Test func markingSeenPersistsAcrossRelaunch() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.hasSeenWelcome == false)

        first.hasSeenWelcome = true
        // The flag is written through to the backing store, not just held in
        // memory, so a separate instance (a relaunch) sees it.
        #expect(defaults.object(forKey: "hasSeenWelcome") as? Bool == true)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.hasSeenWelcome, "the quick-start would reappear after relaunch")
    }

    @Test func toleratesAWronglyTypedFlag() {
        let defaults = freshDefaults()
        // A hand-edited or corrupt store could hold a non-boolean under the key;
        // the read must fall back to the first-run default rather than trapping
        // (CS-050 documented-fallback posture).
        defaults.set("definitely-not-a-bool", forKey: "hasSeenWelcome")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.hasSeenWelcome == false)
    }

    @Test func suitesAreIsolatedFromEachOther() {
        // Two suites (as two UI-test runs would use) do not share the flag, which
        // is what lets a test reset onboarding without touching real app data.
        let a = freshDefaults()
        let b = freshDefaults()
        AppSettings(defaults: a).hasSeenWelcome = true
        #expect(AppSettings(defaults: b).hasSeenWelcome == false)
    }
}

@MainActor
@Suite("Onboarding reset behavior")
struct OnboardingResetTests {
    @Test func resetReturnsToFirstRun() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.hasSeenWelcome = true

        settings.resetToDefaults()

        // A "Reset all settings" returns the user to a first-run experience so the
        // quick-start is offered again (CS-035 / CS-050).
        #expect(settings.hasSeenWelcome == false)
    }

    @Test func resetPersistsFirstRunSoAFreshInstanceSeesIt() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.hasSeenWelcome = true
        first.resetToDefaults()

        // The reset writes the first-run state through to the store (the published
        // property's observer persists the `false`), so a relaunch after a reset is
        // also a first run — whether the key reads back as `false` or absent, a fresh
        // instance resolves it to "not yet seen".
        #expect(defaults.object(forKey: "hasSeenWelcome") as? Bool == false)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.hasSeenWelcome == false)
    }
}

@Suite("Onboarding schema migration")
struct OnboardingSchemaMigrationTests {
    @Test func v5StoreMigratesToCurrentWithoutInventingTheFlag() {
        let defaults = freshDefaults()
        // A store written by the build just before CS-035 (schema 5) carrying a
        // real setting. Migrating forward must advance the version but never
        // back-fill the new flag — an upgrading user is allowed to see the
        // lightweight quick-start once, and the key only appears once the flow is
        // actually shown.
        defaults.set(5, forKey: SettingsSchema.versionKey)
        defaults.set("dracula", forKey: "themeID")

        let from = SettingsSchema.migrateToCurrent(defaults)

        #expect(from == 5)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
        #expect(defaults.object(forKey: "hasSeenWelcome") == nil)
        // The unrelated setting is untouched by the additive migration.
        #expect(defaults.string(forKey: "themeID") == "dracula")
    }

    @Test func currentSchemaIncludesTheOnboardingStep() {
        // Guards against bumping `current` for this ticket but forgetting the
        // matching migration step (the chain must reach `current` without a gap).
        #expect(SettingsSchema.current >= 6)
        let defaults = freshDefaults()
        defaults.set(1, forKey: SettingsSchema.versionKey)
        defaults.set("dracula", forKey: "themeID")
        SettingsSchema.migrateToCurrent(defaults)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
    }
}
