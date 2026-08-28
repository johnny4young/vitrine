import Foundation
import Testing

@testable import Vitrine

// MARK: - Document envelope validation

@Suite("StylePresetDocument validation")
struct StylePresetDocumentTests {
    @Test func documentRoundTripsAndYieldsPresets() throws {
        let presets = [
            StylePreset(name: "One", style: PresetTestFixtures.sampleStyle()),
            StylePreset(
                name: "Two", style: .init(themeID: Theme.nord.id, background: .transparent)),
        ]
        let data = try StylePresetDocument(presets: presets).jsonData()
        let parsed = try StylePresetDocument.presets(from: data)
        #expect(parsed.count == 2)
        #expect(parsed.map(\.name) == ["One", "Two"])
    }

    @Test func exportedDocumentStampsFormatAndCurrentSchema() throws {
        let document = StylePresetDocument(presets: [
            StylePreset(name: "X", style: PresetTestFixtures.sampleStyle())
        ])
        #expect(document.format == StylePresetDocument.formatMarker)
        #expect(document.schemaVersion == StylePresetDocument.currentSchemaVersion)
    }

    @Test func documentEnvelopeRoundTripsThroughItsOwnCodable() throws {
        // The whole envelope (format marker + schema version + presets), not just the
        // extracted presets, survives an encode → decode unchanged.
        let document = StylePresetDocument(presets: [
            StylePreset(id: "fixed-id", name: "Brand", style: PresetTestFixtures.sampleStyle())
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
        #expect(StylePresetDocument.ImportError.fileTooLarge.message.contains("1 MB"))
        #expect(StylePresetDocument.ImportError.tooManyPresets.message.contains("1,000"))
    }

    @Test func oneMalformedPresetIsDroppedNotTheWholeFile() throws {
        // Build a valid one-preset document, then splice a garbage element into its
        // presets array — a corrupt entry must drop itself, not collapse the import.
        let valid = StylePresetDocument(presets: [
            StylePreset(name: "Keep", style: PresetTestFixtures.sampleStyle())
        ])
        var object = try #require(
            JSONSerialization.jsonObject(with: try valid.jsonData()) as? [String: Any])
        var presets = try #require(object["presets"] as? [Any])
        presets.append(42)  // not a preset object
        object["presets"] = presets
        let spliced = try JSONSerialization.data(withJSONObject: object)

        let parsed = try StylePresetDocument.presets(from: spliced)
        #expect(parsed.count == 1)
        #expect(parsed.first?.name == "Keep")
    }

    @Test func allPresetsMalformedStillReportsEmpty() {
        // When every element is garbage, the file has no usable presets — still the
        // `.empty` error, so the import UI's copy stays correct.
        let json = """
            { "format": "\(StylePresetDocument.formatMarker)", "schemaVersion": 1, \
            "presets": [42, "nope", {"name": "no style"}] }
            """
        #expect(throws: StylePresetDocument.ImportError.empty) {
            _ = try StylePresetDocument.presets(from: Data(json.utf8))
        }
    }
}
