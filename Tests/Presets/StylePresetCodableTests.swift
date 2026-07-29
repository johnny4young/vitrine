import Foundation
import Testing

@testable import Vitrine

// MARK: - Codable round-trip

@Suite("StylePreset Codable round-trip")
struct StylePresetCodableTests {
    @Test func snapshotRoundTripsThroughJSON() throws {
        let original = PresetTestFixtures.sampleStyle()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StyleSnapshot.self, from: data)
        #expect(decoded == original)
    }

    @Test func presetRoundTripsThroughJSON() throws {
        let original = StylePreset(name: "My Brand", style: PresetTestFixtures.sampleStyle())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StylePreset.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.style == original.style)
    }

    @Test func everyBackgroundKindRoundTrips() throws {
        let backgrounds: [BackgroundStyle] = [
            .solid(RGBAColor(.black)), .gradient(.night), .transparent,
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
        let user = StylePreset(name: "Mine", style: PresetTestFixtures.sampleStyle())
        #expect(user.isBuiltIn == false)
        let asBuiltInID = StylePreset(
            id: "builtin.aurora", name: "Spoof", style: PresetTestFixtures.sampleStyle())
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
        // image reference.
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
