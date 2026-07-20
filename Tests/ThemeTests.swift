import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Vitrine

// — custom themes: the documented file schema, its validation, the store's
// fallback/immutability guarantees, and a sample custom theme render.
//
// The documented behaviors this file pins:
//   • users can import a theme file from a documented schema;
//   • a bad color or a missing required key fails with a clear validation error;
//   • built-in themes remain immutable (a custom theme can never shadow, rename, or
//     delete a built-in);
//   • an invalid or corrupt store/file degrades to the built-ins instead of crashing;
//   • exported screenshots are deterministic across custom themes.

// MARK: - Fixtures

/// An isolated defaults suite so a store test never touches the real app container
/// or another test's state, mirroring `PresetStoreTests`.
private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "VitrineThemeTests-\(UUID().uuidString)")!
}

/// A complete, legible dark palette used as the canonical sample custom theme.
private func samplePalette() -> ThemePalette {
    ThemePalette(
        background: HexColor("#1E1E1E")!,
        foreground: HexColor("#D4D4D4")!,
        keyword: HexColor("#C586C0")!,
        string: HexColor("#CE9178")!,
        comment: HexColor("#6A9955")!,
        number: HexColor("#B5CEA8")!,
        type: HexColor("#4EC9B0")!,
        function: HexColor("#DCDCAA")!,
        variable: HexColor("#9CDCFE")!,
        attribute: HexColor("#569CD6")!)
}

/// The documented theme-file JSON for one custom theme. Built by encoding a real
/// `CustomThemeDocument` so the fixture cannot drift from the schema the app writes.
private func sampleThemeFileData(name: String = "Midnight Sample") throws -> Data {
    let theme = Theme(id: "custom.sample", displayName: name, palette: samplePalette())
    return try CustomThemeDocument(themes: [theme]).jsonData()
}

/// A short Swift snippet that tokenizes into several scope colors under any real
/// theme (a keyword, a string, a number, and a comment).
private let sampleCode =
    "let count = 42 // total\nfunc greet(_ name: String) { print(\"Hi \\(name)\") }"

// MARK: - HexColor strict parsing

@Suite("HexColor strict parsing")
struct HexColorTests {
    @Test func parsesAllSupportedLengths() {
        #expect(HexColor("#FFFFFF")?.hexString == "#FFFFFF")
        #expect(HexColor("000000")?.hexString == "#000000")
        #expect(HexColor("#FFF")?.hexString == "#FFFFFF")
        #expect(HexColor("#000")?.hexString == "#000000")
    }

    @Test func parsesAlphaAndShorthandAlpha() {
        // Full opacity drops the alpha suffix; partial opacity keeps it.
        #expect(HexColor("#112233FF")?.hexString == "#112233")
        #expect(HexColor("#11223380")?.hexString == "#112233" + "80")
        // RGBA shorthand doubles each nibble (8 → 88).
        let shorthand = HexColor("#1234")
        #expect(shorthand?.hexString == "#112233" + "44")
    }

    @Test func roundTripsThroughCanonicalUppercaseString() {
        let original = "#1e1e1e"
        let color = try! #require(HexColor(original))
        // Re-parsing the canonical string yields the same value: deterministic.
        let reparsed = try! #require(HexColor(color.hexString))
        #expect(color == reparsed)
        #expect(color.hexString == "#1E1E1E")
    }

    @Test func rejectsMalformedInput() {
        #expect(HexColor("") == nil)
        #expect(HexColor("#GGG") == nil)
        #expect(HexColor("#12") == nil)  // unsupported length
        #expect(HexColor("#1234567") == nil)  // 7 digits
        #expect(HexColor("rgb(1,2,3)") == nil)
        #expect(HexColor("not a color") == nil)
        // Fullwidth digits satisfy `isHexDigit` but stop the scanner mid-string;
        // they must be rejected, not decoded into a wrong-but-accepted color.
        #expect(HexColor("FFFFF\u{FF10}") == nil)  // trailing fullwidth ０
    }

    @Test func relativeLuminanceSeparatesDarkFromLight() {
        let black = try! #require(HexColor("#000000"))
        let white = try! #require(HexColor("#FFFFFF"))
        #expect(black.relativeLuminance < 0.5)
        #expect(white.relativeLuminance > 0.5)
    }

    @Test func colorIsReconstructedInSRGB() {
        // A captured hex color round-trips back to the same hex via the sRGB-pinned
        // `Color`, proving the value is display-independent (deterministic sizing).
        let color = try! #require(HexColor("#3A7BD5"))
        #expect(color.color.hexColor == color)
    }
}

// MARK: - ThemePalette schema validation

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

        let palette = samplePalette()
        let data = try encoder.encode(palette)
        let decoded = try JSONDecoder().decode(ThemePalette.self, from: data)
        #expect(decoded == palette)
        // Re-encoding the decoded value yields byte-identical JSON: a palette
        // round-trips deterministically, which is what keeps a shared theme file
        // and its render stable on any Mac.
        #expect(try encoder.encode(decoded) == data)
    }
}

// MARK: - CustomThemeDocument envelope (the documented file schema)

@Suite("Custom theme file schema")
struct CustomThemeDocumentTests {
    @Test func exportThenImportRoundTripsThePalette() throws {
        let theme = Theme(id: "custom.x", displayName: "Round Trip", palette: samplePalette())
        let data = try CustomThemeDocument(themes: [theme]).jsonData()

        let imported = try CustomThemeDocument.themes(from: data)
        #expect(imported.count == 1)
        #expect(imported[0].displayName == "Round Trip")
        #expect(imported[0].palette == samplePalette())
    }

    @Test func exportedFileCarriesTheFormatMarkerAndSchemaVersion() throws {
        let data = try sampleThemeFileData()
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

// MARK: - CustomThemeStore: catalog, immutability, fallback

@MainActor
@Suite("Custom theme store")
struct CustomThemeStoreTests {
    @Test func newStoreHasNoCustomThemesButOffersTheBuiltIns() {
        let store = CustomThemeStore(defaults: freshDefaults())
        #expect(store.customThemes.isEmpty)
        // The catalog always leads with the immutable built-ins.
        #expect(store.allThemes.prefix(Theme.builtIns.count).map(\.id) == Theme.builtIns.map(\.id))
    }

    @Test func addedThemeGetsAFreshNonBuiltInIDAndPersists() {
        let defaults = freshDefaults()
        let store = CustomThemeStore(defaults: defaults)
        let added = store.addTheme(named: "Mine", palette: samplePalette())

        #expect(added.id.hasPrefix("custom."))
        #expect(!Theme.builtInIDs.contains(added.id))
        #expect(store.customThemes.map(\.id) == [added.id])

        // A second store over the same defaults restores the persisted theme.
        let reopened = CustomThemeStore(defaults: defaults)
        #expect(reopened.customThemes.count == 1)
        #expect(reopened.customThemes.first?.displayName == "Mine")
        #expect(reopened.customThemes.first?.palette == samplePalette())
    }

    @Test func duplicateNamesAreDisambiguated() {
        let store = CustomThemeStore(defaults: freshDefaults())
        let first = store.addTheme(named: "Twin", palette: samplePalette())
        let second = store.addTheme(named: "Twin", palette: samplePalette())
        #expect(first.displayName == "Twin")
        #expect(second.displayName == "Twin 2")
    }

    @Test func emptyNameCollapsesToAFriendlyDefault() {
        let store = CustomThemeStore(defaults: freshDefaults())
        let added = store.addTheme(named: "   ", palette: samplePalette())
        #expect(added.displayName == "Custom Theme")
    }

    @Test func builtInIDsAlwaysResolveToTheBuiltInTheme() {
        let store = CustomThemeStore(defaults: freshDefaults())
        for builtIn in Theme.builtIns {
            let resolved = store.theme(withID: builtIn.id)
            #expect(resolved.id == builtIn.id)
            #expect(resolved.isBuiltIn)
            #expect(resolved.palette == nil)  // a built-in carries no custom palette
        }
    }

    @Test func unknownIDFallsBackToOneDark() {
        let store = CustomThemeStore(defaults: freshDefaults())
        #expect(store.theme(withID: "does-not-exist").id == Theme.oneDark.id)
    }

    @Test func customThemeResolvesByItsOwnID() {
        let store = CustomThemeStore(defaults: freshDefaults())
        let added = store.addTheme(named: "Resolvable", palette: samplePalette())
        let resolved = store.theme(withID: added.id)
        #expect(resolved.id == added.id)
        #expect(resolved.palette == samplePalette())
        #expect(!resolved.isBuiltIn)
    }

    @Test func renamingOrDeletingABuiltInIDIsANoOp() {
        let store = CustomThemeStore(defaults: freshDefaults())
        #expect(store.rename(id: Theme.oneDark.id, to: "Hacked") == false)
        #expect(store.delete(id: Theme.oneDark.id) == false)
        #expect(store.isBuiltIn(id: Theme.oneDark.id))
        // The built-in catalog is untouched and still resolves to its real name.
        #expect(store.theme(withID: Theme.oneDark.id).displayName == "One Dark")
    }

    @Test func renameAndDeleteAffectOnlyCustomThemes() {
        let store = CustomThemeStore(defaults: freshDefaults())
        let added = store.addTheme(named: "Before", palette: samplePalette())

        #expect(store.rename(id: added.id, to: "After") == true)
        #expect(store.theme(withID: added.id).displayName == "After")

        #expect(store.delete(id: added.id) == true)
        #expect(store.customThemes.isEmpty)
        // After deletion the id falls back to the built-in default.
        #expect(store.theme(withID: added.id).id == Theme.oneDark.id)
    }

    @Test func importIsPurelyAdditiveAndRekeysIDs() throws {
        let store = CustomThemeStore(defaults: freshDefaults())
        let data = try sampleThemeFileData(name: "Imported")

        let firstAdded = try store.importThemes(from: data)
        #expect(firstAdded.count == 1)
        #expect(store.customThemes.count == 1)

        // Importing the same file again adds a second, distinctly-keyed copy rather
        // than overwriting the first ("an import only ever adds").
        let secondAdded = try store.importThemes(from: data)
        #expect(secondAdded.count == 1)
        #expect(store.customThemes.count == 2)
        #expect(secondAdded[0].id != firstAdded[0].id)
        #expect(secondAdded[0].displayName == "Imported 2")  // de-duplicated name
    }

    @Test func importingABadFileLeavesTheLiveStateUntouched() {
        let store = CustomThemeStore(defaults: freshDefaults())
        store.addTheme(named: "Keep Me", palette: samplePalette())
        let before = store.customThemes

        #expect(throws: CustomThemeDocument.ImportError.self) {
            try store.importThemes(from: Data("garbage".utf8))
        }
        // A failed import is atomic: nothing was added or removed.
        #expect(store.customThemes == before)
    }
}

// MARK: - Store persistence fallbacks (defensive behavior)

@MainActor
@Suite("Custom theme store fallback behavior")
struct CustomThemeStoreFallbackTests {
    @Test func corruptBlobYieldsAnEmptyListNotACrash() {
        let defaults = freshDefaults()
        defaults.set(Data("not json at all".utf8), forKey: CustomThemeStore.storageKey)
        let store = CustomThemeStore(defaults: defaults)
        #expect(store.customThemes.isEmpty)
        // The built-ins are still fully available.
        #expect(store.allThemes.count == Theme.builtIns.count)
    }

    @Test func missingBlobYieldsAnEmptyList() {
        let store = CustomThemeStore(defaults: freshDefaults())
        #expect(store.customThemes.isEmpty)
    }

    @Test func aStoredThemeWithABadColorIsDroppedOnLoad() throws {
        let defaults = freshDefaults()
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
        let defaults = freshDefaults()
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
        let defaults = freshDefaults()
        let store = CustomThemeStore(defaults: defaults)
        store.addTheme(named: "Temp", palette: samplePalette())
        #expect(!store.customThemes.isEmpty)

        // Simulate a global "reset all settings" clearing the persisted blob, then
        // reload: the in-memory copy reflects the cleared state.
        defaults.removeObject(forKey: CustomThemeStore.storageKey)
        store.reload()
        #expect(store.customThemes.isEmpty)
    }
}

// MARK: - Sample custom theme render

@MainActor
@Suite("Sample custom theme render")
struct CustomThemeRenderTests {
    /// Highlights `code` under `theme`, returning the distinct foreground colors —
    /// the same signal the coverage matrix uses to prove real tokenization.
    private func distinctColors(_ code: String, theme: Theme) -> Set<RGBAColor> {
        let attributed = HighlightManager.shared.attributedString(
            for: code, language: .swift, theme: theme,
            font: .monospacedSystemFont(ofSize: 14, weight: .regular))
        var colors = Set<RGBAColor>()
        attributed.enumerateAttribute(
            .foregroundColor, in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            guard let color = value as? NSColor, let srgb = color.usingColorSpace(.sRGB) else {
                return
            }
            colors.insert(
                RGBAColor(
                    red: srgb.redComponent, green: srgb.greenComponent,
                    blue: srgb.blueComponent, opacity: srgb.alphaComponent))
        }
        return colors
    }

    @Test func aSampleCustomThemeImportsAndRendersANonEmptyImage() throws {
        let store = CustomThemeStore(defaults: freshDefaults())
        let added = try store.importThemes(from: sampleThemeFileData())
        let theme = try #require(added.first)

        var config = SnapshotConfig()
        config.code = sampleCode
        config.language = .swift
        config.theme = store.theme(withID: theme.id)

        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    @Test func aCustomThemePaintsRealSyntaxColors() throws {
        // The custom palette gives keywords, strings, numbers, comments, etc. their
        // own colors, so a tokenized snippet uses several distinct foreground colors
        // rather than a single flat fallback color.
        let theme = Theme(id: "custom.render", displayName: "Render", palette: samplePalette())
        #expect(distinctColors(sampleCode, theme: theme).count >= 2)
    }

    @Test func aCustomThemeUsesItsOwnPaletteBackground() {
        let theme = Theme(id: "custom.bg", displayName: "BG", palette: samplePalette())
        let background = RGBAColor(HighlightManager.shared.backgroundColor(for: theme))
        // The card background is exactly the palette's own background color.
        #expect(background == RGBAColor(samplePalette().background.color))
    }

    @Test func aCustomThemeRenderIsDeterministicAcrossRenders() throws {
        // Behavior: "exported screenshots are deterministic across custom
        // themes." Rendering the same custom-theme config twice yields byte-identical
        // PNG output, because the palette is captured in fixed sRGB.
        let theme = Theme(id: "custom.det", displayName: "Deterministic", palette: samplePalette())
        var config = SnapshotConfig()
        config.code = sampleCode
        config.language = .swift
        config.theme = theme

        let first = try #require(ExportManager.renderCGImage(config, scale: 2))
        let second = try #require(ExportManager.renderCGImage(config, scale: 2))
        let firstPNG = try #require(ExportManager.pngData(from: first))
        let secondPNG = try #require(ExportManager.pngData(from: second))
        #expect(firstPNG == secondPNG)
    }

    @Test func differentPalettesProduceDifferentRenders() throws {
        // A second palette with a clearly different background and syntax colors
        // renders different pixels than the sample, proving the palette actually
        // drives the output (not a constant).
        let darkTheme = Theme(
            id: "custom.dark", displayName: "Dark", palette: samplePalette())
        let lightPalette = ThemePalette(
            background: HexColor("#FFFFFF")!, foreground: HexColor("#1A1A1A")!,
            keyword: HexColor("#AF00DB")!, string: HexColor("#A31515")!)
        let lightTheme = Theme(
            id: "custom.light", displayName: "Light", palette: lightPalette)

        var darkConfig = SnapshotConfig()
        darkConfig.code = sampleCode
        darkConfig.language = .swift
        darkConfig.theme = darkTheme
        var lightConfig = darkConfig
        lightConfig.theme = lightTheme

        let darkImage = try #require(ExportManager.renderCGImage(darkConfig, scale: 1))
        let lightImage = try #require(ExportManager.renderCGImage(lightConfig, scale: 1))
        let darkPNG = try #require(ExportManager.pngData(from: darkImage))
        let lightPNG = try #require(ExportManager.pngData(from: lightImage))
        #expect(darkPNG != lightPNG)
    }

    // MARK: - Custom-theme highlight cache

    private func highlight(_ code: String, theme: Theme) -> NSAttributedString {
        HighlightManager.shared.attributedString(
            for: code, language: .swift, theme: theme,
            font: .monospacedSystemFont(ofSize: 14, weight: .regular))
    }

    /// A repeated highlight of the same custom theme returns an equal result — the
    /// cache serves the same tokenization, not a re-import that could differ.
    @Test func customThemeHighlightIsStableAcrossCalls() {
        let theme = Theme(id: "custom.cache", displayName: "Cache", palette: samplePalette())
        let first = highlight(sampleCode, theme: theme)
        let second = highlight(sampleCode, theme: theme)
        #expect(first.isEqual(to: second))
        #expect(first.string == sampleCode)
    }

    /// The critical invariant that lets a custom theme be cached at all: a palette that
    /// changes under a **stable theme id** must not serve the previous palette's colors.
    /// The cache keys on the palette itself, so this is a fresh render, not a stale hit —
    /// exactly the case the built-in `themeID`-keyed cache had to exclude.
    @Test func changingThePaletteUnderAStableIDReflowsTheColors() {
        let warm = Theme(id: "custom.mutable", displayName: "Mutable", palette: samplePalette())
        _ = highlight(sampleCode, theme: warm)  // prime the cache under this id

        let differentPalette = ThemePalette(
            background: HexColor("#FFFFFF")!, foreground: HexColor("#111111")!,
            keyword: HexColor("#FF0000")!, string: HexColor("#00AA00")!)
        let mutated = Theme(
            id: "custom.mutable", displayName: "Mutable", palette: differentPalette)

        let keywordColor = RGBAColor(differentPalette.keyword.color)
        let rendered = highlight(sampleCode, theme: mutated)
        var found = Set<RGBAColor>()
        rendered.enumerateAttribute(
            .foregroundColor, in: NSRange(location: 0, length: rendered.length)
        ) { value, _, _ in
            if let color = (value as? NSColor)?.usingColorSpace(.sRGB) {
                found.insert(
                    RGBAColor(
                        red: color.redComponent, green: color.greenComponent,
                        blue: color.blueComponent, opacity: color.alphaComponent))
            }
        }
        #expect(
            found.contains(keywordColor),
            "the new palette's keyword color must appear — the cache must not serve the old palette"
        )
    }
}

// MARK: - Custom theme editor draft (preview before saving)

/// The editor's `CustomThemeDraft` is the editable, `Color`-backed form behind both
/// the live preview and the Save action ("theme preview appears before
/// saving"). The editor builds its preview *and* the saved theme from the same
/// `draft.palette()`, so these tests pin the load-bearing guarantee that what the
/// user previews is exactly the palette that gets saved — and that opening an
/// existing theme for editing seeds the wells without drifting its colors.
@MainActor
@Suite("Custom theme editor draft")
struct CustomThemeDraftTests {
    @Test func aNewDraftResolvesToACompleteValidDarkPalette() {
        // The editor opens a new theme on a sensible, fully-populated starting point
        // (not all-black wells), so the very first preview is legible and complete.
        let palette = CustomThemeDraft().palette()
        #expect(palette.appearance == .dark)
        // Every token color is a real, distinct choice rather than collapsing to the
        // foreground fallback, so the seeded preview shows real syntax coloring.
        let tokens = [
            palette.keyword, palette.string, palette.comment, palette.number,
            palette.type, palette.function, palette.variable, palette.attribute,
        ]
        #expect(Set(tokens).count >= 2)
        #expect(tokens.allSatisfy { $0 != palette.foreground })
    }

    @Test func editingDraftRoundTripsAnExistingPaletteWithoutDrift() {
        // Edit seeds each well from `palette.x.color` and `palette()` resolves it back
        // through `Color.hexColor`. This is the documented fixed-sRGB round-trip, so
        // opening a theme and saving it unchanged must yield the identical palette —
        // otherwise Edit would silently corrupt a saved theme's colors.
        let original = samplePalette()
        let draft = CustomThemeDraft(
            editingID: "custom.edit", name: "Editable", palette: original)
        #expect(draft.palette() == original)
    }

    @Test func editingDraftPreservesTheEditingIDAndName() {
        let draft = CustomThemeDraft(
            editingID: "custom.keep", name: "Keep", palette: samplePalette())
        #expect(draft.editingID == "custom.keep")
        #expect(draft.name == "Keep")
    }

    @Test func aNewDraftHasNoEditingID() {
        // A new draft is in "create" mode, so the editor adds rather than rewrites.
        #expect(CustomThemeDraft().editingID == nil)
    }

    @Test func draftResolvesToTheSamePaletteOnEveryCall() {
        // The editor calls `palette()` once for the preview and again to save; both
        // must agree, so "what you preview is what you save" holds exactly.
        let draft = CustomThemeDraft(
            editingID: "custom.stable", name: "Stable", palette: samplePalette())
        #expect(draft.palette() == draft.palette())
    }

    @Test func editingAWellChangesOnlyThatColorInTheResolvedPalette() {
        // Editing a single well in the editor must change exactly that token color and
        // leave the rest of the previewed/saved palette intact.
        let draft = CustomThemeDraft(
            editingID: "custom.edit1", name: "One Edit", palette: samplePalette())
        draft.keyword = HexColor("#FF0000")!.color

        let edited = draft.palette()
        #expect(edited.keyword == HexColor("#FF0000"))
        // Every other token is untouched relative to the seed palette.
        let seed = samplePalette()
        #expect(edited.background == seed.background)
        #expect(edited.foreground == seed.foreground)
        #expect(edited.string == seed.string)
        #expect(edited.comment == seed.comment)
        #expect(edited.number == seed.number)
        #expect(edited.type == seed.type)
        #expect(edited.function == seed.function)
        #expect(edited.variable == seed.variable)
        #expect(edited.attribute == seed.attribute)
    }

    @Test func theDraftPaletteRendersTheSamePreviewTheStoreWouldSave() throws {
        // The preview renders `draft.palette()`; saving stores the same palette. Render
        // both as a theme and assert byte-identical PNGs, proving the preview the user
        // approves is pixel-for-pixel what the saved custom theme produces (
        // "preview before saving" tied to the determinism guarantee).
        let draft = CustomThemeDraft(
            editingID: "custom.preview", name: "Preview", palette: samplePalette())

        var previewConfig = SnapshotConfig()
        previewConfig.code = sampleCode
        previewConfig.language = .swift
        previewConfig.theme = Theme(
            id: "custom.preview", displayName: draft.name, palette: draft.palette())

        // The store re-keys and re-validates on save; the resolved theme must render
        // the same pixels because it carries the same palette value.
        let store = CustomThemeStore(defaults: freshDefaults())
        let saved = store.addTheme(named: draft.name, palette: draft.palette())
        var savedConfig = previewConfig
        savedConfig.theme = store.theme(withID: saved.id)

        let previewImage = try #require(ExportManager.renderCGImage(previewConfig, scale: 1))
        let savedImage = try #require(ExportManager.renderCGImage(savedConfig, scale: 1))
        let previewPNG = try #require(ExportManager.pngData(from: previewImage))
        let savedPNG = try #require(ExportManager.pngData(from: savedImage))
        #expect(previewPNG == savedPNG)
    }
}
