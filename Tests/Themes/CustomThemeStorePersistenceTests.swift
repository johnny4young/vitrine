import Foundation
import Testing

@testable import Vitrine

@Suite("Custom theme store fallback behavior")
struct CustomThemeStoreFallbackTests {
    @Test func corruptBlobYieldsAnEmptyListNotACrash() {
        let defaults = ThemeTestFixtures.freshDefaults()
        defaults.set(Data("not json at all".utf8), forKey: CustomThemeStore.storageKey)
        let store = CustomThemeStore(defaults: defaults)
        #expect(store.customThemes.isEmpty)
        // The built-ins are still fully available.
        #expect(store.allThemes.count == Theme.builtIns.count)
    }

    @Test func missingBlobYieldsAnEmptyList() {
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        #expect(store.customThemes.isEmpty)
    }

    @Test func aStoredThemeWithABadColorIsDroppedOnLoad() throws {
        let defaults = ThemeTestFixtures.freshDefaults()
        // A hand-edited store where one record carries an invalid color: the strict
        // palette decoder fails that record, so the whole (single-record) blob is
        // dropped rather than feeding a broken color into the renderer.
        let blob = """
            [{ "id": "custom.bad", "name": "Bad",
               "palette": { "background": "#1E1E1E", "foreground": "oops" } }]
            """
        defaults.set(Data(blob.utf8), forKey: CustomThemeStore.storageKey)
        let store = CustomThemeStore(defaults: defaults)
        #expect(store.customThemes.isEmpty)
    }

    @Test func aStoredThemeReusingABuiltInIDIsDroppedSoItCannotShadowABuiltIn() throws {
        let defaults = ThemeTestFixtures.freshDefaults()
        // A hand-edited store that tries to claim a built-in id is filtered out on
        // load, so the built-in can never be shadowed or "overwritten".
        let blob = """
            [{ "id": "\(Theme.oneDark.id)", "name": "Imposter",
               "palette": { "background": "#FF0000", "foreground": "#00FF00" } }]
            """
        defaults.set(Data(blob.utf8), forKey: CustomThemeStore.storageKey)
        let store = CustomThemeStore(defaults: defaults)
        #expect(store.customThemes.isEmpty)
        // The real built-in still resolves to its bundled identity.
        let resolved = store.theme(withID: Theme.oneDark.id)
        #expect(resolved.isBuiltIn)
        #expect(resolved.displayName == "One Dark")
    }

    @Test func reloadReflectsAClearedStore() {
        let defaults = ThemeTestFixtures.freshDefaults()
        let store = CustomThemeStore(defaults: defaults)
        store.addTheme(named: "Temp", palette: ThemeTestFixtures.samplePalette())
        #expect(!store.customThemes.isEmpty)

        // Simulate a global "reset all settings" clearing the persisted blob, then
        // reload: the in-memory copy reflects the cleared state.
        defaults.removeObject(forKey: CustomThemeStore.storageKey)
        store.reload()
        #expect(store.customThemes.isEmpty)
        #expect(defaults.data(forKey: CustomThemeStore.storageKey) == nil)
    }
}
