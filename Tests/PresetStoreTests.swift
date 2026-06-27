import Foundation
import Testing

@testable import Vitrine

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "VitrinePresetStoreTests-\(UUID().uuidString)")!
}

/// A style snapshot exercising several presentation fields, used as a fixture.
private func sampleStyle() -> StyleSnapshot {
    StyleSnapshot(
        themeID: Theme.dracula.id,
        fontName: "Fira Code",
        fontSize: 16,
        fontLigatures: true,
        padding: 48,
        cornerRadius: 20,
        showChrome: false,
        showShadow: false,
        showLineNumbers: true,
        background: .gradient(.sunset))
}

// MARK: - StyleSnapshot capture / apply

@Suite("StyleSnapshot capture and apply")
struct StyleSnapshotTests {
    @Test func captureRecordsPresentationButNeverCodeOrLanguage() {
        var config = SnapshotConfig()
        config.code = "let secret = 42"
        config.language = .python
        config.theme = .monokai
        config.fontName = "Hack"
        config.padding = 40
        config.showChrome = false

        let snapshot = StyleSnapshot(capturing: config)

        // Presentation is captured…
        #expect(snapshot.themeID == "monokai")
        #expect(snapshot.fontName == "Hack")
        #expect(snapshot.padding == 40)
        #expect(snapshot.showChrome == false)
        // …and applying it back reproduces the style without ever touching source.
        var target = SnapshotConfig()
        target.code = "print('keep me')"
        target.language = .swift
        let originalCode = target.code
        let originalLanguage = target.language
        snapshot.apply(to: &target)
        #expect(target.code == originalCode)
        #expect(target.language == originalLanguage)
        #expect(target.theme.id == "monokai")
        #expect(target.fontName == "Hack")
        #expect(target.padding == 40)
        #expect(target.showChrome == false)
    }

    @Test func captureDropsNonPortableImageBackgroundToGradient() {
        var config = SnapshotConfig()
        config.background = .image(ImageBackground(reference: ImageReference(fileName: "x.png")))
        let snapshot = StyleSnapshot(capturing: config)
        // An image references a container file that won't travel with the preset,
        // so it degrades to the signature gradient.
        #expect(snapshot.background == .gradient(.aurora))
    }

    @Test func applyResolvesUnknownThemeAndFontToDefaults() {
        let snapshot = StyleSnapshot(
            themeID: "no-such-theme", fontName: "Comic Sans", background: .gradient(.ocean))
        var config = SnapshotConfig()
        snapshot.apply(to: &config)
        #expect(config.theme.id == Theme.oneDark.id)
        #expect(config.fontName == CodeFont.default)
        // A valid background still applies.
        #expect(config.background == .gradient(.ocean))
    }

    @Test func initClampsOutOfRangeNumbers() {
        let snapshot = StyleSnapshot(
            themeID: Theme.oneDark.id, fontSize: 999, padding: 999, cornerRadius: 999,
            wrapColumns: 999,
            background: .gradient(.aurora))
        #expect(snapshot.fontSize == SettingsDefaults.fontSizeRange.upperBound)
        #expect(snapshot.padding == SettingsDefaults.paddingRange.upperBound)
        #expect(snapshot.cornerRadius == SettingsDefaults.cornerRadiusRange.upperBound)
        #expect(snapshot.wrapColumns == SettingsDefaults.wrapColumnsRange.upperBound)
    }

    @Test func fullInitAlsoDropsNonPortableImageBackground() {
        // The non-`capturing` initializer (used by built-ins and shared files) runs
        // the same portability rule, so a snapshot can never be constructed carrying
        // a container-local image reference.
        let snapshot = StyleSnapshot(
            themeID: Theme.oneDark.id,
            background: .image(ImageBackground(reference: ImageReference(fileName: "x.png"))))
        #expect(snapshot.background == .gradient(.aurora))
    }
}

// MARK: - Codable round-trip

@Suite("StylePreset Codable round-trip")
struct StylePresetCodableTests {
    @Test func snapshotRoundTripsThroughJSON() throws {
        let original = sampleStyle()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StyleSnapshot.self, from: data)
        #expect(decoded == original)
    }

    @Test func presetRoundTripsThroughJSON() throws {
        let original = StylePreset(name: "My Brand", style: sampleStyle())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StylePreset.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.style == original.style)
    }

    @Test func everyBackgroundKindRoundTrips() throws {
        let backgrounds: [BackgroundStyle] = [
            .solid(.black), .gradient(.night), .transparent,
            .customGradient(.default),
        ]
        for background in backgrounds {
            let snapshot = StyleSnapshot(themeID: Theme.oneDark.id, background: background)
            let data = try JSONEncoder().encode(snapshot)
            let decoded = try JSONDecoder().decode(StyleSnapshot.self, from: data)
            #expect(decoded.background == background)
        }
    }

    @Test func builtInFlagIsDerivedNotDecoded() throws {
        // A hand-edited file cannot fake a built-in: a user preset whose JSON omits
        // any origin marker stays a user preset, and a file claiming a built-in id
        // is recognized as built-in purely from the id.
        let user = StylePreset(name: "Mine", style: sampleStyle())
        #expect(user.isBuiltIn == false)
        let asBuiltInID = StylePreset(id: "builtin.aurora", name: "Spoof", style: sampleStyle())
        #expect(asBuiltInID.isBuiltIn == true)
    }

    @Test func decodingToleratesMissingAndCorruptFields() throws {
        // A partial/garbage object self-heals each field rather than failing.
        let json = """
            { "style": { "themeID": "dracula", "fontSize": "not-a-number" } }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(StylePreset.self, from: data)
        #expect(!decoded.id.isEmpty)  // a fresh id is minted
        #expect(decoded.name == "Untitled Preset")  // missing name → friendly default
        #expect(decoded.style.themeID == "dracula")
        #expect(decoded.style.fontSize == SettingsDefaults.fontSize)  // bad number → default
        #expect(decoded.style.background == .gradient(.aurora))  // missing → signature
    }

    @Test func decodingSelfHealsANonPortableImageBackground() throws {
        // A hand-edited file that smuggles in an image background (which references a
        // container-local file that won't exist on import) self-heals to the
        // signature gradient on decode, so the renderer never receives a dangling
        // image reference (CS-030 "invalid preset files do not crash").
        let withImage = StyleSnapshot(themeID: Theme.dracula.id, background: .transparent)
        var json = try #require(
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(withImage)) as? [String: Any])
        json["background"] = ["kind": "image", "image": ["reference": ["fileName": "secret.png"]]]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(StyleSnapshot.self, from: data)
        #expect(decoded.background == .gradient(.aurora))
        #expect(decoded.themeID == "dracula")  // the rest of the snapshot is preserved
    }
}

// MARK: - Document envelope validation

@Suite("StylePresetDocument validation")
struct StylePresetDocumentTests {
    @Test func documentRoundTripsAndYieldsPresets() throws {
        let presets = [
            StylePreset(name: "One", style: sampleStyle()),
            StylePreset(
                name: "Two", style: .init(themeID: Theme.nord.id, background: .transparent)),
        ]
        let data = try StylePresetDocument(presets: presets).jsonData()
        let parsed = try StylePresetDocument.presets(from: data)
        #expect(parsed.count == 2)
        #expect(parsed.map(\.name) == ["One", "Two"])
    }

    @Test func exportedDocumentStampsFormatAndCurrentSchema() throws {
        let document = StylePresetDocument(presets: [StylePreset(name: "X", style: sampleStyle())])
        #expect(document.format == StylePresetDocument.formatMarker)
        #expect(document.schemaVersion == StylePresetDocument.currentSchemaVersion)
    }

    @Test func documentEnvelopeRoundTripsThroughItsOwnCodable() throws {
        // The whole envelope (format marker + schema version + presets), not just the
        // extracted presets, survives an encode → decode unchanged.
        let document = StylePresetDocument(presets: [
            StylePreset(id: "fixed-id", name: "Brand", style: sampleStyle())
        ])
        let decoded = try JSONDecoder().decode(
            StylePresetDocument.self, from: try document.jsonData())
        #expect(decoded == document)
        #expect(decoded.format == StylePresetDocument.formatMarker)
        #expect(decoded.schemaVersion == StylePresetDocument.currentSchemaVersion)
    }

    @Test func malformedJSONIsRejectedAsNotAPresetFile() {
        let data = Data("this is not json".utf8)
        #expect(throws: StylePresetDocument.ImportError.notAPresetFile) {
            _ = try StylePresetDocument.presets(from: data)
        }
    }

    @Test func wrongFormatMarkerIsRejected() throws {
        let json = """
            { "format": "some.other.app", "schemaVersion": 1, "presets": [] }
            """
        #expect(throws: StylePresetDocument.ImportError.notAPresetFile) {
            _ = try StylePresetDocument.presets(from: Data(json.utf8))
        }
    }

    @Test func newerSchemaVersionIsRejectedWithItsNumber() throws {
        let future = StylePresetDocument.currentSchemaVersion + 1
        let json = """
            { "format": "\(StylePresetDocument.formatMarker)", "schemaVersion": \(future),
              "presets": [] }
            """
        #expect(throws: StylePresetDocument.ImportError.unsupportedSchemaVersion(future)) {
            _ = try StylePresetDocument.presets(from: Data(json.utf8))
        }
    }

    @Test func zeroOrMissingSchemaVersionIsRejected() throws {
        // A preset file must declare a schema version of at least 1; a missing one
        // decodes to 0 and is treated as an unsupported version, not silently read.
        let json = """
            { "format": "\(StylePresetDocument.formatMarker)", "presets": [] }
            """
        #expect(throws: StylePresetDocument.ImportError.unsupportedSchemaVersion(0)) {
            _ = try StylePresetDocument.presets(from: Data(json.utf8))
        }
    }

    @Test func validEnvelopeWithNoPresetsIsRejectedAsEmpty() throws {
        let json = """
            { "format": "\(StylePresetDocument.formatMarker)", "schemaVersion": 1, "presets": [] }
            """
        #expect(throws: StylePresetDocument.ImportError.empty) {
            _ = try StylePresetDocument.presets(from: Data(json.utf8))
        }
    }

    @Test func importErrorsCarryUserFacingMessages() {
        #expect(!StylePresetDocument.ImportError.notAPresetFile.message.isEmpty)
        #expect(!StylePresetDocument.ImportError.unsupportedSchemaVersion(9).message.isEmpty)
        #expect(!StylePresetDocument.ImportError.empty.message.isEmpty)
    }
}

// MARK: - PresetStore behavior

@MainActor
@Suite("PresetStore save and catalog")
struct PresetStoreCatalogTests {
    @Test func builtInsAreAlwaysPresentAndLeadTheCatalog() {
        let store = PresetStore(defaults: freshDefaults())
        #expect(store.userPresets.isEmpty)
        // The built-in catalog leads, in declared order.
        let leadingIDs = store.allPresets.prefix(StylePreset.builtIns.count).map(\.id)
        #expect(leadingIDs == StylePreset.builtIns.map(\.id))
    }

    @Test func saveCapturesCurrentStyleAsNamedUserPreset() {
        let store = PresetStore(defaults: freshDefaults())
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
        let store = PresetStore(defaults: freshDefaults())
        let saved = store.savePreset(named: "   ", from: SnapshotConfig())
        #expect(saved.name == "Untitled Preset")
    }

    @Test func duplicateNamesAreDisambiguated() {
        let store = PresetStore(defaults: freshDefaults())
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
        let store = PresetStore(defaults: freshDefaults())
        let didDelete = store.delete(id: StylePreset.aurora.id)
        #expect(didDelete == false)
        #expect(store.allPresets.contains { $0.id == StylePreset.aurora.id })
    }

    @Test func builtInCannotBeRenamed() {
        let store = PresetStore(defaults: freshDefaults())
        let didRename = store.rename(id: StylePreset.aurora.id, to: "Hacked")
        #expect(didRename == false)
        #expect(store.preset(withID: StylePreset.aurora.id)?.name == StylePreset.aurora.name)
    }

    @Test func duplicatingABuiltInCreatesAnEditableUserCopy() {
        let store = PresetStore(defaults: freshDefaults())
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
        let defaults = freshDefaults()
        // A hand-edited store cannot "overwrite" a built-in by reusing its reserved
        // id: such an entry is filtered out on load.
        let spoof = StylePreset(id: "builtin.aurora", name: "Evil", style: sampleStyle())
        let data = try! JSONEncoder().encode([spoof])
        defaults.set(data, forKey: PresetStore.storageKey)

        let store = PresetStore(defaults: defaults)
        #expect(store.userPresets.isEmpty)
        // The real built-in is intact.
        #expect(store.preset(withID: "builtin.aurora")?.name == StylePreset.aurora.name)
    }
}

@MainActor
@Suite("PresetStore persistence")
struct PresetStorePersistenceTests {
    @Test func userPresetsPersistAcrossInstances() {
        let defaults = freshDefaults()
        let first = PresetStore(defaults: defaults)
        first.savePreset(named: "Persisted", from: SnapshotConfig())

        let second = PresetStore(defaults: defaults)
        #expect(second.userPresets.count == 1)
        #expect(second.userPresets.first?.name == "Persisted")
    }

    @Test func deletePersists() {
        let defaults = freshDefaults()
        let first = PresetStore(defaults: defaults)
        let saved = first.savePreset(named: "Temp", from: SnapshotConfig())
        first.delete(id: saved.id)

        let second = PresetStore(defaults: defaults)
        #expect(second.userPresets.isEmpty)
    }

    @Test func corruptStoredBlobYieldsEmptyUserListWithoutCrashing() {
        let defaults = freshDefaults()
        defaults.set(Data("not a preset array".utf8), forKey: PresetStore.storageKey)
        let store = PresetStore(defaults: defaults)
        #expect(store.userPresets.isEmpty)
        // Built-ins remain usable.
        #expect(store.allPresets.count == StylePreset.builtIns.count)
    }

    @Test func reloadReflectsClearedStore() {
        let defaults = freshDefaults()
        let store = PresetStore(defaults: defaults)
        store.savePreset(named: "Gone soon", from: SnapshotConfig())
        #expect(store.userPresets.count == 1)

        // Simulate a global reset clearing the key, then reload.
        defaults.removeObject(forKey: PresetStore.storageKey)
        store.reload()
        #expect(store.userPresets.isEmpty)
    }
}

@MainActor
@Suite("PresetStore import")
struct PresetStoreImportTests {
    @Test func importAddsPresetsFromAValidFile() throws {
        let defaults = freshDefaults()
        let store = PresetStore(defaults: defaults)
        let document = StylePresetDocument(presets: [
            StylePreset(name: "Imported A", style: sampleStyle()),
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
        let defaults = freshDefaults()
        let store = PresetStore(defaults: defaults)
        let existing = store.savePreset(named: "Existing", from: SnapshotConfig())

        // A file reusing the existing id must not overwrite it; the import re-keys.
        let document = StylePresetDocument(presets: [
            StylePreset(id: existing.id, name: "Imported", style: sampleStyle())
        ])
        let added = try store.importPresets(from: try document.jsonData())

        #expect(store.userPresets.count == 2)  // additive, not a replace
        #expect(added.first?.id != existing.id)  // re-keyed
        #expect(store.preset(withID: existing.id)?.name == "Existing")  // original intact
    }

    @Test func importingTheSameFileTwiceAddsBothTimes() throws {
        let defaults = freshDefaults()
        let store = PresetStore(defaults: defaults)
        let data = try StylePresetDocument(presets: [
            StylePreset(name: "Dup", style: sampleStyle())
        ]).jsonData()

        try store.importPresets(from: data)
        try store.importPresets(from: data)
        #expect(store.userPresets.count == 2)
        // The names are disambiguated so the picker stays unambiguous.
        #expect(Set(store.userPresets.map(\.name)) == ["Dup", "Dup 2"])
    }

    @Test func importOfInvalidFileThrowsAndLeavesStateUntouched() throws {
        let defaults = freshDefaults()
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
        let store = PresetStore(defaults: freshDefaults())
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
        let source = PresetStore(defaults: freshDefaults())
        source.savePreset(
            named: "Round Trip",
            from: {
                var config = SnapshotConfig()
                config.theme = .gruvbox
                config.background = .gradient(.forest)
                return config
            }())
        let data = try source.exportJSONData()

        let destination = PresetStore(defaults: freshDefaults())
        try destination.importPresets(from: data)
        #expect(destination.userPresets.count == 1)
        let imported = try #require(destination.userPresets.first)
        #expect(imported.name == "Round Trip")
        #expect(imported.style.themeID == "gruvbox")
        #expect(imported.style.background == .gradient(.forest))
    }
}

// MARK: - Applying a preset through AppSettings

@MainActor
@Suite("AppSettings style preset application")
struct AppSettingsStylePresetTests {
    @Test func applyStylePresetWritesPresentationOnlyNeverCode() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.config.code = "let mySecret = 1"
        settings.config.language = .python
        let originalCode = settings.config.code
        let originalLanguage = settings.config.language

        settings.applyStylePreset(.midnight)

        #expect(settings.config.code == originalCode)
        #expect(settings.config.language == originalLanguage)
        #expect(settings.config.theme.id == StylePreset.midnight.style.themeID)
        #expect(settings.config.background == StylePreset.midnight.style.background)
    }

    @Test func stylePresetCapturesAndAppliesWrapColumns() {
        var source = SnapshotConfig()
        source.wrapColumns = 96
        let preset = StylePreset.capturing(source, name: "Wrapped")

        var target = SnapshotConfig()
        target.wrapColumns = nil
        preset.style.apply(to: &target)

        #expect(preset.style.wrapColumns == 96)
        #expect(target.wrapColumns == 96)
    }

    @Test func appliedStyleDivergesFromAndDropsADestinationPreset() {
        // A style preset is independent of a destination preset (CS-020); applying
        // one that changes a presentation field naturally drops the destination
        // selection to "Custom" through the existing divergence check.
        let settings = AppSettings(defaults: freshDefaults())
        settings.selectPreset(.openGraph)  // padding 56, aurora
        #expect(settings.selectedPresetID == "opengraph")

        settings.applyStylePreset(.minimal)  // padding 32, solid white, no shadow

        #expect(settings.selectedPresetID == nil)
        #expect(settings.config.background == .solid(.white))
    }
}
