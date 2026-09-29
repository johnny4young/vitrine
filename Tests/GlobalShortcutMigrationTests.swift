import AppKit
import Foundation
import KeyboardShortcuts
import Testing
import VitrineDomain

@testable import Vitrine

@Suite("Opt-in global shortcut migration")
struct GlobalShortcutMigrationTests {
    private struct FreeProvider: EntitlementProvider {
        var cachedIsPro: Bool { false }
        func currentIsPro() async -> Bool { false }
    }

    @Test func freshGraphRemainsUnassignedAcrossLaunchesAndReset() {
        let defaults = testDefaults()
        let first = AppEnvironment(
            defaults: defaults, entitlements: Entitlements(provider: FreeProvider()))
        #expect(defaults.object(forKey: GlobalShortcutMigration.shortcutKey) == nil)
        #expect(defaults.integer(forKey: GlobalShortcutMigration.policyKey) == 1)
        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
        first.appSettings.resetToDefaults()
        _ = AppEnvironment(defaults: defaults, entitlements: Entitlements(provider: FreeProvider()))
        #expect(defaults.object(forKey: GlobalShortcutMigration.shortcutKey) == nil)
        #expect(KeyboardShortcuts.Name.quickCapture.defaultShortcut == nil)
    }

    @Test(arguments: [false, true])
    func missingLegacyAssignmentRetainsPreviousBehavior(versioned: Bool) throws {
        let defaults = testDefaults(
            initialValues: versioned ? [SettingsSchema.versionKey: 12] : ["padding": 32])
        GlobalShortcutMigration.prepare(in: defaults)
        let raw = try #require(defaults.string(forKey: GlobalShortcutMigration.shortcutKey))
        let shortcut = try JSONDecoder().decode(
            KeyboardShortcuts.Shortcut.self, from: Data(raw.utf8))
        #expect(shortcut == KeyboardShortcuts.Shortcut(.s, modifiers: [.command, .shift]))
        // Clearing the recorder removes the key when Name has no default.
        defaults.removeObject(forKey: GlobalShortcutMigration.shortcutKey)
        GlobalShortcutMigration.prepare(in: defaults)
        #expect(defaults.object(forKey: GlobalShortcutMigration.shortcutKey) == nil)
    }

    @Test(arguments: [false, true])
    func preservesExplicitDisableEvenWithoutOtherPreferences(versioned: Bool) {
        let defaults = testDefaults(initialValues: [GlobalShortcutMigration.shortcutKey: false])
        if versioned { defaults.set(12, forKey: SettingsSchema.versionKey) }
        GlobalShortcutMigration.prepare(in: defaults)
        #expect(defaults.object(forKey: GlobalShortcutMigration.shortcutKey) as? Bool == false)
        GlobalShortcutMigration.prepare(in: defaults)
        #expect(defaults.object(forKey: GlobalShortcutMigration.shortcutKey) as? Bool == false)
    }

    @Test func preservesCustomAndMalformedValuesByteForByte() throws {
        let chosen = KeyboardShortcuts.Shortcut(.v, modifiers: [.control, .option])
        let encoded = String(decoding: try JSONEncoder().encode(chosen), as: UTF8.self)
        for raw in [encoded, "not-valid-json", ""] {
            let defaults = testDefaults(initialValues: [
                GlobalShortcutMigration.shortcutKey: raw, SettingsSchema.versionKey: 12,
            ])
            GlobalShortcutMigration.prepare(in: defaults)
            #expect(defaults.string(forKey: GlobalShortcutMigration.shortcutKey) == raw)
        }
    }

    @Test func unrelatedSystemPreferencesDoNotMakeAnInstallationLegacy() {
        let defaults = testDefaults(initialValues: [
            "AppleLanguages": ["es"], "AppleAccentColor": 3,
        ])
        GlobalShortcutMigration.prepare(in: defaults)
        #expect(defaults.object(forKey: GlobalShortcutMigration.shortcutKey) == nil)
    }

    @Test func completedOrFuturePolicyNeverReenablesAMissingShortcut() {
        for version in [1, 2, 99] {
            let defaults = testDefaults(initialValues: [
                GlobalShortcutMigration.policyKey: version, SettingsSchema.versionKey: 12,
            ])
            GlobalShortcutMigration.prepare(in: defaults)
            #expect(defaults.object(forKey: GlobalShortcutMigration.shortcutKey) == nil)
            #expect(defaults.integer(forKey: GlobalShortcutMigration.policyKey) == version)
        }
    }

    @Test func migratedEncodingIsReadByThePinnedLibraryWithoutRegisteringAHotkey() throws {
        let defaults = testDefaults(initialValues: [SettingsSchema.versionKey: 12])
        GlobalShortcutMigration.prepare(in: defaults)
        let raw = try #require(defaults.string(forKey: GlobalShortcutMigration.shortcutKey))
        let name = KeyboardShortcuts.Name("migration-test.\(UUID().uuidString)")
        let key = "KeyboardShortcuts_\(name.rawValue)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        // No event subscription or setShortcut: this only reads an isolated key.
        UserDefaults.standard.set(raw, forKey: key)
        #expect(
            KeyboardShortcuts.getShortcut(for: name)
                == KeyboardShortcuts.Shortcut(.s, modifiers: [.command, .shift]))
    }
}
