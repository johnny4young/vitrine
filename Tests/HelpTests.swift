import Foundation
import Testing

@testable import Vitrine

/// In-app Help, documentation, and version-aware "What's New" (CS-049).
///
/// The user-visible surfaces (Help window, What's New window) are SwiftUI/AppKit
/// and smoke-tested in the UI suite; here we unit-test the *pure* pieces the spec
/// calls out: the version-gating logic (seen/unseen), the numeric version ordering
/// it relies on, the persisted last-seen flag, and the schema migration. Like the
/// onboarding tests, persistence is exercised against a fresh, isolated defaults
/// suite per test (the same isolation UI tests get from `VITRINE_USER_DEFAULTS_SUITE`).
private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "VitrineHelpTests-\(UUID().uuidString)")!
}

@Suite("Semantic version ordering")
struct SemanticVersionTests {
    @Test func parsesDottedNumericComponents() {
        #expect(SemanticVersion("1.2.3")?.components == [1, 2, 3])
        #expect(SemanticVersion("0.1.0")?.components == [0, 1, 0])
        #expect(SemanticVersion("2")?.components == [2])
    }

    @Test func ordersNumericallyNotLexically() {
        // The headline reason for a numeric compare: as strings, "0.10.0" < "0.9.0".
        #expect(SemanticVersion("0.10.0")! > SemanticVersion("0.9.0")!)
        #expect(SemanticVersion("1.0.0")! > SemanticVersion("0.99.0")!)
        #expect(SemanticVersion("0.2.0")! > SemanticVersion("0.1.9")!)
    }

    @Test func missingTrailingComponentsAreZero() {
        // "1.2" and "1.2.0" describe the same version for ordering purposes.
        #expect(SemanticVersion("1.2")! == SemanticVersion("1.2.0")!)
        #expect(!(SemanticVersion("1.2")! < SemanticVersion("1.2.0")!))
        #expect(!(SemanticVersion("1.2.0")! < SemanticVersion("1.2")!))
    }

    @Test func ignoresPreReleaseAndBuildSuffix() {
        // A pre-release/build suffix does not change the numeric ordering core.
        #expect(SemanticVersion("1.2.3-beta.1")?.components == [1, 2, 3])
        #expect(SemanticVersion("1.2.3+build.99")?.components == [1, 2, 3])
        #expect(SemanticVersion("1.2.3-rc1")! == SemanticVersion("1.2.3")!)
    }

    @Test func unparseableStringsReturnNil() {
        // Empty or non-numeric input fails to parse so callers can fall back to a
        // safe floor rather than trap.
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("abc") == nil)
        #expect(SemanticVersion("1.x.0") == nil)
        #expect(SemanticVersion("-1.0") == nil)
    }

    @Test func zeroIsTheFloor() {
        // `.zero` is the smallest version, used as the fallback for corrupt input.
        #expect(SemanticVersion.zero < SemanticVersion("0.0.1")!)
        #expect(SemanticVersion("0")! == SemanticVersion.zero)
    }
}

@Suite("What's New version gate")
struct WhatsNewGateTests {
    private func note(_ version: String) -> ReleaseNote {
        ReleaseNote(version: version, headline: "Test", highlights: ["A highlight."])
    }

    @Test func neverPresentsWhenNoNotesAreBundled() {
        // With nothing to show, the gate is closed regardless of the last-seen value.
        #expect(ReleaseNotes.shouldPresent(latest: nil, lastSeenVersion: nil) == false)
        #expect(ReleaseNotes.shouldPresent(latest: nil, lastSeenVersion: "0.0.1") == false)
    }

    @Test func neverPresentsOnACleanFirstRun() {
        // A clean install (no last-seen version) is owned by onboarding, so What's
        // New must not appear even though there are notes (CS-049 acceptance: "never
        // on a clean first run").
        #expect(ReleaseNotes.shouldPresent(latest: note("1.0.0"), lastSeenVersion: nil) == false)
    }

    @Test func presentsWhenBundledVersionIsNewerThanLastSeen() {
        // The core case: notes newer than what the user last saw should appear once
        // (CS-049 acceptance: "appears only when the bundled notes version is newer").
        #expect(
            ReleaseNotes.shouldPresent(latest: note("1.1.0"), lastSeenVersion: "1.0.0") == true)
        #expect(
            ReleaseNotes.shouldPresent(latest: note("0.10.0"), lastSeenVersion: "0.9.0") == true)
    }

    @Test func doesNotPresentForTheSameVersionAlreadySeen() {
        // Showing it at most once per version means the same last-seen version
        // closes the gate.
        #expect(
            ReleaseNotes.shouldPresent(latest: note("1.0.0"), lastSeenVersion: "1.0.0") == false)
    }

    @Test func doesNotPresentWhenLastSeenIsNewer() {
        // A downgrade (or a hand-edited future value) never reopens the gate.
        #expect(
            ReleaseNotes.shouldPresent(latest: note("1.0.0"), lastSeenVersion: "1.1.0") == false)
    }

    @Test func toleratesACorruptLastSeenValueButStillRequiresPastFirstRun() {
        // An unparseable persisted value, once past the first-run guard, is treated
        // as the zero floor — so a real, newer bundled version still surfaces once
        // rather than the gate trapping (CS-050 documented-fallback posture).
        #expect(
            ReleaseNotes.shouldPresent(latest: note("1.0.0"), lastSeenVersion: "garbage") == true)
    }

    @Test func theBundledCatalogIsOrderedNewestFirst() {
        // `latest` (index 0) must be the highest version, since the gate and the
        // What's New list both assume it. Guards against a misordered hand edit.
        let versions = ReleaseNotes.all.map(\.semanticVersion)
        for (newer, older) in zip(versions, versions.dropFirst()) {
            #expect(newer >= older, "ReleaseNotes.all is not ordered newest-first")
        }
        if let latest = ReleaseNotes.latest {
            #expect(ReleaseNotes.all.allSatisfy { latest.semanticVersion >= $0.semanticVersion })
        }
    }

    @Test func everyBundledNoteHasContent() {
        // Each shipped note must carry a version, a headline, and at least one
        // highlight so the What's New surface is never blank.
        for entry in ReleaseNotes.all {
            #expect(!entry.version.isEmpty)
            #expect(SemanticVersion(entry.version) != nil, "Note version is not numeric")
            #expect(!entry.headline.isEmpty)
            #expect(!entry.highlights.isEmpty)
            #expect(entry.highlights.allSatisfy { !$0.isEmpty })
        }
    }
}

@MainActor
@Suite("Last-seen What's New version persistence")
struct WhatsNewVersionPersistenceTests {
    @Test func freshInstallHasNoLastSeenVersion() {
        // A brand-new suite has no value, which the gate reads as a clean first run.
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.lastSeenWhatsNewVersion == nil)
    }

    @Test func writingPersistsAcrossRelaunch() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.lastSeenWhatsNewVersion = "0.1.0"

        // The value is written through to the backing store, so a separate instance
        // (a relaunch) sees it and the gate stays closed for that version.
        #expect(defaults.string(forKey: "lastSeenWhatsNewVersion") == "0.1.0")
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.lastSeenWhatsNewVersion == "0.1.0")
    }

    @Test func resetReturnsToCleanInstallState() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.lastSeenWhatsNewVersion = "0.1.0"

        settings.resetToDefaults()

        // A "Reset all settings" restores the clean-install What's New behavior, so
        // the next launch stamps the current version rather than showing notes.
        #expect(settings.lastSeenWhatsNewVersion == nil)
    }

    @Test func toleratesAWronglyTypedValue() {
        let defaults = freshDefaults()
        // A hand-edited or corrupt store could hold a non-string under the key; the
        // read must fall back to nil rather than trapping (CS-050 posture).
        defaults.set(["not", "a", "string"], forKey: "lastSeenWhatsNewVersion")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.lastSeenWhatsNewVersion == nil)
    }

    @Test func suitesAreIsolatedFromEachOther() {
        let a = freshDefaults()
        let b = freshDefaults()
        AppSettings(defaults: a).lastSeenWhatsNewVersion = "9.9.9"
        #expect(AppSettings(defaults: b).lastSeenWhatsNewVersion == nil)
    }
}

@MainActor
@Suite("What's New launch gate (controller)")
struct WhatsNewLaunchGateTests {
    // `ReleaseNotes.shouldPresent` is the pure predicate; these cover the launch-path
    // wrapper `WhatsNewWindowController.presentIfNewVersion`, which adds two behaviors
    // the predicate does not model and that the app relies on at startup (CS-049):
    //   1. its Bool return value (the launch path uses it to avoid stacking the window
    //      over onboarding), and
    //   2. the clean-first-run *stamp* side effect — on a fresh install it records the
    //      current version as seen (rather than showing notes) so What's New first
    //      appears on the *next* upgrade, leaving the first launch to onboarding.
    // Only the non-presenting branches are exercised so the suite stays headless: each
    // returns before `show()` would create a window. Settings are injected per test
    // against an isolated defaults suite, so driving the `.shared` controller leaves no
    // window or cross-test residue.

    @Test func cleanFirstRunDoesNotPresentButStampsTheCurrentVersionSeen() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.lastSeenWhatsNewVersion == nil)

        let presented = WhatsNewWindowController.shared.presentIfNewVersion(settings: settings)

        // Never shown on a clean first run (onboarding owns it)...
        #expect(presented == false)
        // ...and the current bundled version is recorded as already seen, so the gate
        // stays closed until a genuinely newer version ships.
        #expect(settings.lastSeenWhatsNewVersion == ReleaseNotes.latestVersion)
        #expect(ReleaseNotes.latestVersion != nil, "A bundled note is required for this gate")
    }

    @Test func alreadySeenCurrentVersionDoesNotPresentAndLeavesTheStampUnchanged() {
        let settings = AppSettings(defaults: freshDefaults())
        // Pretend the user already saw the newest bundled notes.
        settings.lastSeenWhatsNewVersion = ReleaseNotes.latestVersion

        let presented = WhatsNewWindowController.shared.presentIfNewVersion(settings: settings)

        // Nothing newer to show, so the window stays closed and the stamp is untouched
        // (the gate shows at most once per version).
        #expect(presented == false)
        #expect(settings.lastSeenWhatsNewVersion == ReleaseNotes.latestVersion)
    }

    @Test func aNewerLastSeenVersionDoesNotReopenTheGate() {
        let settings = AppSettings(defaults: freshDefaults())
        // A downgrade or hand-edited future value must never re-present the notes, and
        // must not be overwritten by the gate (only a real dismissal stamps it).
        settings.lastSeenWhatsNewVersion = "999.0.0"

        let presented = WhatsNewWindowController.shared.presentIfNewVersion(settings: settings)

        #expect(presented == false)
        #expect(settings.lastSeenWhatsNewVersion == "999.0.0")
    }
}

@Suite("What's New schema migration")
struct WhatsNewSchemaMigrationTests {
    @Test func v6StoreMigratesToCurrentWithoutInventingTheKey() {
        let defaults = freshDefaults()
        // A store written by the build just before CS-049 (schema 6) carrying a real
        // setting. Migrating forward must advance the version but never back-fill the
        // new key — an upgrading user is treated like a clean install for one cycle
        // (the key appears only once a launch stamps it).
        defaults.set(6, forKey: SettingsSchema.versionKey)
        defaults.set("dracula", forKey: "themeID")

        let from = SettingsSchema.migrateToCurrent(defaults)

        #expect(from == 6)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
        #expect(defaults.object(forKey: "lastSeenWhatsNewVersion") == nil)
        // The unrelated setting is untouched by the additive migration.
        #expect(defaults.string(forKey: "themeID") == "dracula")
    }

    @Test func currentSchemaIncludesTheWhatsNewStep() {
        // Guards against bumping `current` for this ticket but forgetting the
        // matching migration step (the chain must reach `current` without a gap).
        #expect(SettingsSchema.current >= 7)
        let defaults = freshDefaults()
        defaults.set(1, forKey: SettingsSchema.versionKey)
        defaults.set("dracula", forKey: "themeID")
        SettingsSchema.migrateToCurrent(defaults)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
    }
}

@MainActor
@Suite("VitrineCommand Help surface")
struct HelpCommandTests {
    @Test func helpAndWhatsNewAreAppScopedNotEditorScoped() {
        // Both Help-menu commands are always available (not gated on a key editor).
        #expect(!VitrineCommand.help.isEditorScoped)
        #expect(!VitrineCommand.whatsNew.isEditorScoped)
    }

    @Test func whatsNewHasContentAndNoReservedShortcut() {
        // The command carries the metadata the menu builder needs, and stays
        // shortcut-free so it cannot collide with a reserved key.
        #expect(!VitrineCommand.whatsNew.title.isEmpty)
        #expect(!VitrineCommand.whatsNew.systemImageName.isEmpty)
        #expect(!VitrineCommand.whatsNew.accessibilityLabel.isEmpty)
        #expect(VitrineCommand.whatsNew.keyEquivalent == nil)
    }

    @Test func helpMenuExposesHelpAndWhatsNew() {
        // The Help menu surfaces both the Help and What's New commands (CS-049).
        let help = AppMenu.make().items.compactMap(\.submenu).first { $0.title == "Help" }
        let identifiers = help?.items.map { $0.accessibilityIdentifier() } ?? []
        #expect(identifiers.contains(VitrineCommand.help.accessibilityIdentifier))
        #expect(identifiers.contains(VitrineCommand.whatsNew.accessibilityIdentifier))
    }
}
