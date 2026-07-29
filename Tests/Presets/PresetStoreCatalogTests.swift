import Foundation
import Testing

@testable import Vitrine

// MARK: - PresetStore behavior

@MainActor
@Suite("PresetStore save and catalog")
struct PresetStoreCatalogTests {
    @Test func builtInsAreAlwaysPresentAndLeadTheCatalog() {
        let store = PresetStore(defaults: PresetTestFixtures.freshDefaults())
        #expect(store.userPresets.isEmpty)
        // The built-in catalog leads, in declared order.
        let leadingIDs = store.allPresets.prefix(StylePreset.builtIns.count).map(\.id)
        #expect(leadingIDs == StylePreset.builtIns.map(\.id))
    }

    @Test func saveCapturesCurrentStyleAsNamedUserPreset() {
        let store = PresetStore(defaults: PresetTestFixtures.freshDefaults())
        var config = SnapshotConfig()
        config.code = "let private = true"
        config.theme = .nord
        config.padding = 40

        let saved = store.savePreset(named: "Work Style", from: config)

        #expect(store.userPresets.count == 1)
        #expect(saved.name == "Work Style")
        #expect(saved.isBuiltIn == false)
        #expect(saved.style.themeID == "nord")
        #expect(saved.style.padding == 40)
    }

    @Test func saveBlankNameGetsFriendlyDefault() {
        let store = PresetStore(defaults: PresetTestFixtures.freshDefaults())
        let saved = store.savePreset(named: "   ", from: SnapshotConfig())
        #expect(saved.name == "Untitled Preset")
    }

    @Test func duplicateNamesAreDisambiguated() {
        let store = PresetStore(defaults: PresetTestFixtures.freshDefaults())
        let first = store.savePreset(named: "Brand", from: SnapshotConfig())
        let second = store.savePreset(named: "Brand", from: SnapshotConfig())
        #expect(first.name == "Brand")
        #expect(second.name == "Brand 2")
    }
}

@MainActor
@Suite("PresetStore built-in immutability")
struct PresetStoreImmutabilityTests {
    @Test func builtInCannotBeDeleted() {
        let store = PresetStore(defaults: PresetTestFixtures.freshDefaults())
        let didDelete = store.delete(id: StylePreset.aurora.id)
        #expect(didDelete == false)
        #expect(store.allPresets.contains { $0.id == StylePreset.aurora.id })
    }

    @Test func builtInCannotBeRenamed() {
        let store = PresetStore(defaults: PresetTestFixtures.freshDefaults())
        let didRename = store.rename(id: StylePreset.aurora.id, to: "Hacked")
        #expect(didRename == false)
        #expect(store.preset(withID: StylePreset.aurora.id)?.name == StylePreset.aurora.name)
    }

    @Test func duplicatingABuiltInCreatesAnEditableUserCopy() {
        let store = PresetStore(defaults: PresetTestFixtures.freshDefaults())
        let copy = store.duplicate(.aurora)
        #expect(copy.isBuiltIn == false)
        #expect(copy.style == StylePreset.aurora.style)
        #expect(copy.name == "Aurora Copy")
        // The copy is editable, unlike its source.
        #expect(store.rename(id: copy.id, to: "Aurora Mine"))
        #expect(store.preset(withID: copy.id)?.name == "Aurora Mine")
        #expect(store.delete(id: copy.id))
    }

    @Test func userPresetWhoseIDCollidesWithABuiltInIsDroppedOnLoad() {
        let defaults = PresetTestFixtures.freshDefaults()
        // A hand-edited store cannot "overwrite" a built-in by reusing its reserved
        // id: such an entry is filtered out on load.
        let spoof = StylePreset(
            id: "builtin.aurora", name: "Evil", style: PresetTestFixtures.sampleStyle())
        let data = try! JSONEncoder().encode([spoof])
        defaults.set(data, forKey: PresetStore.storageKey)

        let store = PresetStore(defaults: defaults)
        #expect(store.userPresets.isEmpty)
        // The real built-in is intact.
        #expect(store.preset(withID: "builtin.aurora")?.name == StylePreset.aurora.name)
    }
}
