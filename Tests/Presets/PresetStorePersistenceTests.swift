import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("PresetStore persistence")
struct PresetStorePersistenceTests {
    @Test func userPresetsPersistAcrossInstances() {
        let defaults = PresetTestFixtures.freshDefaults()
        let first = PresetStore(defaults: defaults)
        first.savePreset(named: "Persisted", from: SnapshotConfig())

        let second = PresetStore(defaults: defaults)
        #expect(second.userPresets.count == 1)
        #expect(second.userPresets.first?.name == "Persisted")
    }

    @Test func deletePersists() {
        let defaults = PresetTestFixtures.freshDefaults()
        let first = PresetStore(defaults: defaults)
        let saved = first.savePreset(named: "Temp", from: SnapshotConfig())
        first.delete(id: saved.id)

        let second = PresetStore(defaults: defaults)
        #expect(second.userPresets.isEmpty)
    }

    @Test func corruptStoredBlobYieldsEmptyUserListWithoutCrashing() {
        let defaults = PresetTestFixtures.freshDefaults()
        defaults.set(Data("not a preset array".utf8), forKey: PresetStore.storageKey)
        let store = PresetStore(defaults: defaults)
        #expect(store.userPresets.isEmpty)
        // Built-ins remain usable.
        #expect(store.allPresets.count == StylePreset.builtIns.count)
    }

    @Test func corruptElementInStoredBlobDropsOnlyThatElement() throws {
        let defaults = PresetTestFixtures.freshDefaults()
        // A stored array whose second element is garbage must not wipe the first: one
        // corrupt preset drops itself, the valid one survives the next launch (B9).
        let valid = StylePreset(name: "Persisted", style: PresetTestFixtures.sampleStyle())
        var array = try #require(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode([valid])) as? [Any])
        array.append(42)
        let spliced = try JSONSerialization.data(withJSONObject: array)
        defaults.set(spliced, forKey: PresetStore.storageKey)

        let store = PresetStore(defaults: defaults)
        #expect(store.userPresets.count == 1)
        #expect(store.userPresets.first?.name == "Persisted")
    }

    @Test func reloadReflectsClearedStore() {
        let defaults = PresetTestFixtures.freshDefaults()
        let store = PresetStore(defaults: defaults)
        store.savePreset(named: "Gone soon", from: SnapshotConfig())
        #expect(store.userPresets.count == 1)

        // Simulate a global reset clearing the key, then reload.
        defaults.removeObject(forKey: PresetStore.storageKey)
        store.reload()
        #expect(store.userPresets.isEmpty)
    }
}
