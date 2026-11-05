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

    /// The rendered card's fill, read beside the text, so a wrong palette can't pass.
    private func cardFill(_ config: SnapshotConfig) throws -> NSColor {
        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        // Drawn into an sRGB context so the bytes compare directly with the palette's hex.
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            let x = image.width - Int(config.padding) - 12
            context.draw(
                image,
                in: CGRect(x: -x, y: -(image.height / 2), width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return NSColor(
            srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }

    private func expectColor(
        _ color: NSColor, _ hex: Int, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let channels = [color.redComponent, color.greenComponent, color.blueComponent]
        let expected = [hex >> 16, (hex >> 8) & 0xFF, hex & 0xFF].map { CGFloat($0) / 255 }
        for (actual, wanted) in zip(channels, expected) {
            #expect(abs(actual - wanted) < 0.02, sourceLocation: sourceLocation)
        }
    }

    /// What each theme rendered before this control existed.
    @Test(arguments: [
        (Theme.oneDark, 0x1E2227, 0xE06C75), (Theme.dracula, 0x282A36, 0xFF5555),
        (Theme.github, 0xFFFFFF, 0xCF222E),
    ])
    func themeModeRendersEachThemesOwnColors(_ theme: Theme, _ fill: Int, _ red: Int) throws {
        var config = capture()
        config.theme = theme
        expectColor(try cardFill(config), fill)
        let text = RichPasteboard.highlightedCode(for: config)
        let color = try color(of: "red", in: text)
        expectColor(try #require(color.usingColorSpace(.sRGB)), red)
    }

    @Test(arguments: [(Theme.oneDark, 0x000000), (Theme.github, 0xFFFFFF)])
    func rawRendersACardOnTheThemesSide(_ theme: Theme, _ fill: Int) throws {
        var config = capture(.raw)
        config.theme = theme
        expectColor(try cardFill(config), fill)
    }

    private func contrast(_ first: NSColor, _ second: NSColor) throws -> CGFloat {
        func luminance(_ color: NSColor) throws -> CGFloat {
            let color = try #require(color.usingColorSpace(.sRGB))
            func linear(_ value: CGFloat) -> CGFloat {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
                + 0.0722 * linear(color.blueComponent)
        }
        let (a, b) = (try luminance(first), try luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    @Test(arguments: [Theme.oneDark, Theme.github])
    func everyRawBaseColorReadsOnItsCard(_ theme: Theme) throws {
        let palette = ANSIPalette.resolved(for: theme, mode: .raw)
        #expect(palette.base.count == 16)
        for color in palette.base {
            #expect(try contrast(color, palette.defaultBackground) >= 2.95)
        }
    }

    /// Raw stays raw: a color that already reads keeps its exact xterm value.
    @Test func rawLiftsOnlyTheColorsThatWouldVanish() {
        let light = ANSIPalette.resolved(for: .github, mode: .raw)
        let dark = ANSIPalette.resolved(for: .oneDark, mode: .raw)
        expectColor(light.base[1], 0xCD0000)
        expectColor(light.base[9], 0xFF0000)
        expectColor(dark.base[1], 0xCD0000)
        expectColor(dark.base[15], 0xFFFFFF)
        #expect(light.base[15] != dark.base[15])
    }

    @Test func rawColorsIgnoreTheTheme() {
        let dracula = ANSIPalette.resolved(for: .dracula, mode: .raw)
        let dark = ANSIPalette.resolved(for: .oneDark, mode: .raw)
        #expect(dracula.base == dark.base)
        #expect(dracula.base != ANSIPalette.forTheme(.dracula).base)
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

    @Test func aNonTerminalDocumentCannotCarryRawIntoAPreset() {
        var swift = capture(.raw)
        swift.language = .swift
        #expect(StyleSnapshot(capturing: swift).terminalPalette == nil)
        #expect(StyleSnapshot(capturing: capture(.raw)).terminalPalette == .raw)
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

    // MARK: Header chips

    private func header(
        filename: String? = "project · main", title: String? = "$ git commit -m secret",
        altText: String? = nil, windowTitle: String = ""
    ) throws -> SnapshotConfig {
        var config = SnapshotConfig(code: "", language: .terminal)
        config.metadata.filename = filename
        config.metadata.title = title
        config.altText = try SnapshotAltText.normalized(altText)
        config.windowTitle = windowTitle
        return config
    }

    @Test func removingArgumentsAlsoLeavesADraftedDescription() throws {
        var config = try header(
            altText: "Terminal output, 3 lines, project · main: $ git commit -m secret")
        var edited = TerminalHeaderContext(
            filename: config.metadata.filename, title: config.metadata.title)
        edited.removeArguments()
        config.applyTerminalHeader(edited)
        #expect(config.metadata.title == "$ git")
        #expect(config.altText?.text == "Terminal output, 3 lines, project · main: $ git")
    }

    @Test func removingTheTitleTakesItsCopiesAndTheirSeparator() throws {
        var config = try header(
            altText: "Terminal output, 3 lines: $ git commit -m secret",
            windowTitle: "git commit -m secret")
        var edited = TerminalHeaderContext(
            filename: config.metadata.filename, title: config.metadata.title)
        edited.removeTitle()
        config.applyTerminalHeader(edited)
        #expect(config.altText?.text == "Terminal output, 3 lines")
        #expect(config.windowTitle.isEmpty)
    }

    @Test func removingAFilenameLabelRewritesTheWindowTitle() throws {
        var config = try header(windowTitle: "project · main")
        var edited = TerminalHeaderContext(
            filename: config.metadata.filename, title: config.metadata.title)
        edited.labels.remove(at: 1)
        config.applyTerminalHeader(edited)
        #expect(config.metadata.filename == "project")
        #expect(config.windowTitle == "project")
    }

    @Test func wordsThatOnlyContainTheCommandSurvive() throws {
        var config = try header(title: "$ git", altText: "A digital record of git")
        var edited = TerminalHeaderContext(filename: nil, title: "$ git")
        edited.labels = ["project", "main"]
        edited.removeTitle()
        config.applyTerminalHeader(edited)
        #expect(config.altText?.text == "A digital record of")
    }

    @Test func changingOnlyThePromptKeepsTheCommandInACopy() throws {
        var config = try header(title: "$ htop", altText: "Output of htop")
        var edited = TerminalHeaderContext(filename: "project · main", title: "$ htop")
        edited.prompt = .none
        config.applyTerminalHeader(edited)
        #expect(config.metadata.title == "htop")
        #expect(config.altText?.text == "Output of htop")
    }

    @Test func aChipRemovalUndoesEveryFieldItChanged() throws {
        let settings = AppSettings(defaults: testDefaults())
        settings.config = try header(
            altText: "Output: $ git commit -m secret", windowTitle: "git commit -m secret")
        let before = settings.style
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        var edited = TerminalHeaderContext(
            filename: before.metadata.filename, title: before.metadata.title)
        edited.removeArguments()
        TerminalContextChips.apply(
            edited, to: settings, undoName: "Remove Arguments", undoManager: undo)
        undo.endUndoGrouping()
        #expect(settings.style.metadata.title == "$ git")
        #expect(settings.style.windowTitle == "git")
        #expect(undo.undoActionName == "Remove Arguments")

        undo.undo()
        #expect(settings.style.metadata == before.metadata)
        #expect(settings.style.altText == before.altText)
        #expect(settings.style.windowTitle == before.windowTitle)
    }
}
