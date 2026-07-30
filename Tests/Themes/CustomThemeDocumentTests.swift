import Foundation
import Testing

@testable import Vitrine

@Suite("Custom theme file schema")
struct CustomThemeDocumentTests {
    @Test func storedRecordNormalizesMissingIdentityWithoutTheStore() {
        let record = StoredCustomTheme(
            id: "", name: " \n ", palette: ThemeTestFixtures.samplePalette())

        let theme = record.theme
        #expect(theme.id.hasPrefix("custom."))
        #expect(theme.displayName == "Custom Theme")
        #expect(theme.palette == ThemeTestFixtures.samplePalette())
    }

    @Test func exportThenImportRoundTripsThePalette() throws {
        let theme = Theme(
            id: "custom.x", displayName: "Round Trip", palette: ThemeTestFixtures.samplePalette())
        let data = try CustomThemeDocument(themes: [theme]).jsonData()

        let imported = try CustomThemeDocument.themes(from: data)
        #expect(imported.count == 1)
        #expect(imported[0].displayName == "Round Trip")
        #expect(imported[0].palette == ThemeTestFixtures.samplePalette())
    }

    @Test func exportedFileCarriesTheFormatMarkerAndSchemaVersion() throws {
        let data = try ThemeTestFixtures.sampleThemeFileData()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["format"] as? String == CustomThemeDocument.formatMarker)
        #expect(object?["schemaVersion"] as? Int == CustomThemeDocument.currentSchemaVersion)
        #expect((object?["themes"] as? [Any])?.count == 1)
    }

    @Test func nonJSONDataIsRejectedAsNotAThemeFile() {
        #expect(throws: CustomThemeDocument.ImportError.notAThemeFile) {
            try CustomThemeDocument.themes(from: Data("this is not json".utf8))
        }
    }

    @Test func unrelatedJSONIsRejectedAsNotAThemeFile() {
        // Valid JSON, but not a theme document: the strict `themes` decode fails and
        // it is reported as "not a theme file", never crashing.
        #expect(throws: CustomThemeDocument.ImportError.notAThemeFile) {
            try CustomThemeDocument.themes(from: Data(#"{ "hello": "world" }"#.utf8))
        }
    }

    @Test func wrongFormatMarkerIsRejected() throws {
        // Correct shape, wrong marker (e.g. a different app's export).
        let json = """
            { "format": "some.other.app", "schemaVersion": 1,
              "themes": [{ "id": "a", "name": "A",
                "palette": { "background": "#1E1E1E", "foreground": "#D4D4D4" } }] }
            """
        #expect(throws: CustomThemeDocument.ImportError.notAThemeFile) {
            try CustomThemeDocument.themes(from: Data(json.utf8))
        }
    }

    @Test func futureSchemaVersionIsRejectedAsUnsupported() throws {
        let future = CustomThemeDocument.currentSchemaVersion + 1
        let json = """
            { "format": "\(CustomThemeDocument.formatMarker)", "schemaVersion": \(future),
              "themes": [{ "id": "a", "name": "A",
                "palette": { "background": "#1E1E1E", "foreground": "#D4D4D4" } }] }
            """
        #expect(throws: CustomThemeDocument.ImportError.unsupportedSchemaVersion(future)) {
            try CustomThemeDocument.themes(from: Data(json.utf8))
        }
    }

    @Test func emptyThemeArrayIsRejected() throws {
        let json = """
            { "format": "\(CustomThemeDocument.formatMarker)", "schemaVersion": 1, "themes": [] }
            """
        #expect(throws: CustomThemeDocument.ImportError.empty) {
            try CustomThemeDocument.themes(from: Data(json.utf8))
        }
    }

    @Test func badColorInsideAThemeSurfacesAsInvalidPalette() throws {
        let json = """
            { "format": "\(CustomThemeDocument.formatMarker)", "schemaVersion": 1,
              "themes": [{ "id": "a", "name": "A",
                "palette": { "background": "totally-bad", "foreground": "#D4D4D4" } }] }
            """
        #expect(
            throws: CustomThemeDocument.ImportError.invalidPalette(
                .invalidColor(key: "background", value: "totally-bad"))
        ) {
            try CustomThemeDocument.themes(from: Data(json.utf8))
        }
    }

    @Test func missingColorInsideAThemeSurfacesAsInvalidPalette() throws {
        let json = """
            { "format": "\(CustomThemeDocument.formatMarker)", "schemaVersion": 1,
              "themes": [{ "id": "a", "name": "A",
                "palette": { "foreground": "#D4D4D4" } }] }
            """
        #expect(
            throws: CustomThemeDocument.ImportError.invalidPalette(.missingKey("background"))
        ) {
            try CustomThemeDocument.themes(from: Data(json.utf8))
        }
    }

    @Test func importErrorMessagesAreUserFacing() {
        #expect(
            CustomThemeDocument.ImportError.notAThemeFile.message
                == "This file is not a Vitrine theme file.")
        #expect(
            CustomThemeDocument.ImportError.empty.message
                == "This theme file does not contain any themes.")
        #expect(
            CustomThemeDocument.ImportError.unsupportedSchemaVersion(9).message.contains(
                "version 9"))
        // A nested palette error carries the precise color message up to the user.
        let nested = CustomThemeDocument.ImportError.invalidPalette(
            .invalidColor(key: "string", value: "qq"))
        #expect(nested.message.contains("\"string\""))
    }
}
