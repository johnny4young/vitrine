import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("PresetStore import")
struct PresetStoreImportTests {
    @Test func importAddsPresetsFromAValidFile() throws {
        let defaults = PresetTestFixtures.freshDefaults()
        let store = PresetStore(defaults: defaults)
        let document = StylePresetDocument(presets: [
            StylePreset(name: "Imported A", style: PresetTestFixtures.sampleStyle()),
            StylePreset(
                name: "Imported B", style: .init(themeID: Theme.nord.id, background: .transparent)),
        ])
        let data = try document.jsonData()

        let added = try store.importPresets(from: data)
        #expect(added.count == 2)
        #expect(store.userPresets.count == 2)
        #expect(store.userPresets.map(\.name) == ["Imported A", "Imported B"])
    }

    @Test func importIsAdditiveAndReKeysIDs() throws {
        let defaults = PresetTestFixtures.freshDefaults()
        let store = PresetStore(defaults: defaults)
        let existing = store.savePreset(named: "Existing", from: SnapshotConfig())

        // A file reusing the existing id must not overwrite it; the import re-keys.
        let document = StylePresetDocument(presets: [
            StylePreset(id: existing.id, name: "Imported", style: PresetTestFixtures.sampleStyle())
        ])
        let added = try store.importPresets(from: try document.jsonData())

        #expect(store.userPresets.count == 2)  // additive, not a replace
        #expect(added.first?.id != existing.id)  // re-keyed
        #expect(store.preset(withID: existing.id)?.name == "Existing")  // original intact
    }

    @Test func importingTheSameFileTwiceAddsBothTimes() throws {
        let defaults = PresetTestFixtures.freshDefaults()
        let store = PresetStore(defaults: defaults)
        let data = try StylePresetDocument(presets: [
            StylePreset(name: "Dup", style: PresetTestFixtures.sampleStyle())
        ]).jsonData()

        try store.importPresets(from: data)
        try store.importPresets(from: data)
        #expect(store.userPresets.count == 2)
        // The names are disambiguated so the picker stays unambiguous.
        #expect(Set(store.userPresets.map(\.name)) == ["Dup", "Dup 2"])
    }

    @Test func importOfInvalidFileThrowsAndLeavesStateUntouched() throws {
        let defaults = PresetTestFixtures.freshDefaults()
        let store = PresetStore(defaults: defaults)
        store.savePreset(named: "Keep", from: SnapshotConfig())

        #expect(throws: StylePresetDocument.ImportError.notAPresetFile) {
            _ = try store.importPresets(from: Data("garbage".utf8))
        }
        // A failed import does not disturb the existing presets.
        #expect(store.userPresets.count == 1)
        #expect(store.userPresets.first?.name == "Keep")
    }

    @Test func exportedDataIsARecognizablePresetEnvelope() throws {
        // The store exports a full preset *document* (format marker + schema), not a
        // bare preset array, so the bytes are independently recognizable as a Vitrine
        // preset file and re-importable through the envelope validator.
        let store = PresetStore(defaults: PresetTestFixtures.freshDefaults())
        store.savePreset(named: "Envelope", from: SnapshotConfig())
        let data = try store.exportJSONData()

        let envelope = try JSONDecoder().decode(StylePresetDocument.self, from: data)
        #expect(envelope.format == StylePresetDocument.formatMarker)
        #expect(envelope.schemaVersion == StylePresetDocument.currentSchemaVersion)
        // The same bytes parse through the strict envelope validator.
        let parsed = try StylePresetDocument.presets(from: data)
        #expect(parsed.map(\.name) == ["Envelope"])
    }

    @Test func exportThenImportRoundTripsThroughData() throws {
        let source = PresetStore(defaults: PresetTestFixtures.freshDefaults())
        source.savePreset(
            named: "Round Trip",
            from: {
                var config = SnapshotConfig()
                config.theme = .gruvbox
                config.background = .gradient(.forest)
                return config
            }())
        let data = try source.exportJSONData()

        let destination = PresetStore(defaults: PresetTestFixtures.freshDefaults())
        try destination.importPresets(from: data)
        #expect(destination.userPresets.count == 1)
        let imported = try #require(destination.userPresets.first)
        #expect(imported.name == "Round Trip")
        #expect(imported.style.themeID == "gruvbox")
        #expect(imported.style.background == .gradient(.forest))
    }
}
