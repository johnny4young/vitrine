import Foundation
import Testing

@testable import Vitrine

@Suite("ThemePalette schema validation")
struct ThemePaletteValidationTests {
    private func decode(_ json: String) throws -> ThemePalette {
        try JSONDecoder().decode(ThemePalette.self, from: Data(json.utf8))
    }

    @Test func decodesAFullPalette() throws {
        let json = """
            {
              "background": "#1E1E1E", "foreground": "#D4D4D4",
              "keyword": "#C586C0", "string": "#CE9178", "comment": "#6A9955",
              "number": "#B5CEA8", "type": "#4EC9B0", "function": "#DCDCAA",
              "variable": "#9CDCFE", "attribute": "#569CD6"
            }
            """
        let palette = try decode(json)
        #expect(palette.background == HexColor("#1E1E1E"))
        #expect(palette.keyword == HexColor("#C586C0"))
        #expect(palette.attribute == HexColor("#569CD6"))
    }

    @Test func minimalTwoColorPaletteIsValidAndTokensDefaultToForeground() throws {
        // A minimal file with only the two required colors is accepted; every
        // optional token color falls back to `foreground`.
        let palette = try decode(##"{ "background": "#101010", "foreground": "#E0E0E0" }"##)
        #expect(palette.foreground == HexColor("#E0E0E0"))
        #expect(palette.keyword == palette.foreground)
        #expect(palette.string == palette.foreground)
        #expect(palette.comment == palette.foreground)
        #expect(palette.number == palette.foreground)
        #expect(palette.type == palette.foreground)
        #expect(palette.function == palette.foreground)
        #expect(palette.variable == palette.foreground)
        #expect(palette.attribute == palette.foreground)
    }

    @Test func missingRequiredBackgroundThrowsAClearError() {
        #expect(throws: ThemePalette.ValidationError.missingKey("background")) {
            try decode(##"{ "foreground": "#D4D4D4" }"##)
        }
    }

    @Test func missingRequiredForegroundThrowsAClearError() {
        #expect(throws: ThemePalette.ValidationError.missingKey("foreground")) {
            try decode(##"{ "background": "#1E1E1E" }"##)
        }
    }

    @Test func invalidRequiredColorThrowsAClearError() {
        #expect(
            throws: ThemePalette.ValidationError.invalidColor(
                key: "background", value: "nope")
        ) {
            try decode(##"{ "background": "nope", "foreground": "#D4D4D4" }"##)
        }
    }

    @Test func presentButInvalidOptionalColorIsRejectedNotSilentlyDropped() {
        // A typo in an *optional* token color still surfaces rather than degrading.
        #expect(
            throws: ThemePalette.ValidationError.invalidColor(
                key: "keyword", value: "#ZZZ")
        ) {
            try decode(
                ##"{ "background": "#1E1E1E", "foreground": "#D4D4D4", "keyword": "#ZZZ" }"##)
        }
    }

    @Test func validationErrorMessagesAreUserFacing() {
        #expect(
            ThemePalette.ValidationError.missingKey("background").message
                == "The theme is missing the required \"background\" color.")
        let invalid = ThemePalette.ValidationError.invalidColor(key: "keyword", value: "xyz")
        #expect(invalid.message.contains("\"keyword\""))
        #expect(invalid.message.contains("xyz"))
        #expect(invalid.message.contains("#1E1E1E"))  // example hint
    }

    @Test func paletteCodableRoundTripIsStable() throws {
        // Use sorted keys so the on-disk bytes are deterministic (the order plain
        // `JSONEncoder` emits dictionary keys in is not stable run to run).
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let palette = ThemeTestFixtures.samplePalette()
        let data = try encoder.encode(palette)
        let decoded = try JSONDecoder().decode(ThemePalette.self, from: data)
        #expect(decoded == palette)
        // Re-encoding the decoded value yields byte-identical JSON: a palette
        // round-trips deterministically, which is what keeps a shared theme file
        // and its render stable on any Mac.
        #expect(try encoder.encode(decoded) == data)
    }
}
