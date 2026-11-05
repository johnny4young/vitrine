import AppKit
import Foundation
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

/// The palette control across every surface that draws or carries it.
@Suite("Terminal palette", .serialized)
@MainActor
struct TerminalPaletteTests {
    private let stream = "\u{1B}[31mred\u{1B}[0m\nplain"
    private let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    private func capture(_ palette: TerminalPaletteMode = .theme) -> SnapshotConfig {
        var config = SnapshotConfig(code: stream, language: .terminal)
        config.terminalPalette = palette
        return config
    }

    private func png(_ config: SnapshotConfig) throws -> Data {
        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        return try #require(ExportManager.pngData(from: image))
    }

    private func color(of text: String, in string: NSAttributedString) throws -> NSColor {
        let range = (string.string as NSString).range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(
            string.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)
    }

    @Test func themeModeIsTheExistingPaletteForEveryThemeKind() {
        for theme in [Theme.oneDark, Theme.dracula, Theme.github] {
            let resolved = ANSIPalette.resolved(for: theme, mode: .theme)
            #expect(resolved.base == ANSIPalette.forTheme(theme).base)
            #expect(resolved.defaultBackground == ANSIPalette.forTheme(theme).defaultBackground)
        }
    }

    @Test func rawColorsIgnoreTheTheme() {
        let dracula = ANSIPalette.resolved(for: .dracula, mode: .raw)
        let dark = ANSIPalette.resolved(for: .oneDark, mode: .raw)
        #expect(dracula.base == dark.base)
        #expect(dracula.base != ANSIPalette.forTheme(.dracula).base)
    }

    /// The header takes its color from the theme, so the card must stay on the theme's side.
    @Test func rawCardStaysOnTheThemesSide() {
        func isLight(_ theme: Theme) -> Bool {
            let color = ANSIPalette.resolved(for: theme, mode: .raw).defaultBackground
            return (color.usingColorSpace(.sRGB)?.brightnessComponent ?? 0) > 0.5
        }
        #expect(isLight(.github))
        #expect(isLight(.oneDark) == false)
    }

    @Test func imageAndRichTextBothFollowThePalette() throws {
        #expect(try png(capture(.raw)) != png(capture()))

        let theme = RichPasteboard.highlightedCode(for: capture())
        let raw = RichPasteboard.highlightedCode(for: capture(.raw))
        #expect(try color(of: "red", in: theme) != color(of: "red", in: raw))
    }

    @Test func plainTextIgnoresThePalette() {
        #expect(capture(.raw).sidecarText == capture().sidecarText)
    }

    /// Redaction replaces the row whatever colors it would have had.
    @Test func rawModeKeepsARedactedRowOutOfEveryExport() throws {
        let secret = "SYNTHETIC_SECRET_123456789"
        var config = SnapshotConfig(code: "safe\nAPI_KEY=\(secret)", language: .terminal)
        config.terminalPalette = .raw
        config.redactedLineRanges = [2...2]
        #expect(RichPasteboard.highlightedCode(for: config).string.contains(secret) == false)

        var substitute = config
        substitute.code = "safe\nAPI_KEY=" + String(repeating: "X", count: secret.count)
        #expect(try png(config) == png(substitute))
    }

    @Test func theCacheDoesNotServeAStaleVariant() {
        let manager = HighlightManager.shared
        func string(_ palette: TerminalPaletteMode) -> AttributedString {
            manager.terminalAttributedString(
                for: stream, theme: .oneDark, font: font, columns: nil, palette: palette)
        }
        func rows(_ palette: TerminalPaletteMode) -> [AttributedString] {
            manager.terminalAttributedLines(
                for: stream, theme: .oneDark, font: font, columns: nil, palette: palette)
        }
        #expect(string(.theme) != string(.raw))
        #expect(rows(.theme) != rows(.raw))
    }

    // MARK: Persistence

    @Test func theDefaultLeavesEncodedStylesUnchanged() throws {
        let json = try String(
            decoding: JSONEncoder().encode(StyleSnapshot(capturing: capture())), as: UTF8.self)
        #expect(json.contains("terminalPalette") == false)
    }

    @Test func aStyleWithoutTheFieldDecodesToTheDefault() throws {
        let style = try JSONDecoder().decode(
            StyleSnapshot.self, from: Data(#"{"themeID":"dracula"}"#.utf8))
        var config = capture(.raw)
        style.apply(to: &config)
        #expect(config.terminalPalette == .theme)
    }

    @Test func anUnknownValueFallsBackInAPresetButFailsARecipe() throws {
        let json = #"{"themeID":"dracula","terminalPalette":"neon"}"#
        let style = try JSONDecoder().decode(StyleSnapshot.self, from: Data(json.utf8))
        #expect(style.terminalPalette == nil)

        let decoder = JSONDecoder()
        decoder.userInfo[StyleSnapshot.strictDecodingKey] = true
        #expect(throws: DecodingError.self) {
            try decoder.decode(StyleSnapshot.self, from: Data(json.utf8))
        }
    }

    @Test func aRecipeCarriesThePalette() throws {
        let recipe = WorkspaceRecipe(
            name: "Terminal", style: StyleSnapshot(capturing: capture(.raw)))
        let data = try WorkspaceRecipeDocument(recipe: recipe).jsonData()
        #expect(try WorkspaceRecipeDocument.recipe(from: data).style.terminalPalette == .raw)
    }

    @Test func aRestoredWindowKeepsThePaletteAndToleratesOlderArchives() throws {
        let themes = CustomThemeStore(defaults: testDefaults())
        let archived = try #require(EditorWindowState(config: capture(.raw)).encoded())
        let restored = try #require(EditorWindowState.decoded(from: archived))
        #expect(restored.config(themes: themes).terminalPalette == .raw)

        let older = try #require(EditorWindowState.decoded(from: Data("{}".utf8)))
        #expect(older.config(themes: themes).terminalPalette == .theme)
    }

    @Test func aGarbageStoredPreferenceReadsAsTheDefault() {
        let defaults = testDefaults()
        defaults.set("neon", forKey: SettingsCodec.Keys.terminalPalette)
        #expect(SettingsCodec.readConfig(from: defaults).terminalPalette == .theme)
    }

    @Test func aShareLinkCarriesThePalette() throws {
        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: capture(.raw)))
        var restored = SnapshotConfig()
        try SnapshotShareLink.snapshot(from: url).apply(to: &restored)
        #expect(restored.terminalPalette == .raw)
    }
}
