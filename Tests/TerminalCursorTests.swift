import AppKit
import Foundation
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

/// The cursor control across every surface that draws or carries it.
@Suite("Terminal cursor rendering", .serialized)
@MainActor
struct TerminalCursorRenderingTests {
    private let stream = "\u{1B}[31mred\u{1B}[0m\nplain"
    private let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    /// A screen-addressed capture whose cursor ends on the "r" of "row text".
    private let grid = "\u{1B}[2J\u{1B}[1;1Hfirst\u{1B}[2;1Hsecond row text\u{1B}[2;8H"

    private func capture(
        _ cursor: TerminalCursorStyle = .hidden, code: String? = nil
    ) -> SnapshotConfig {
        var config = SnapshotConfig(code: code ?? stream, language: .terminal)
        config.terminalCursor = cursor
        return config
    }

    private func png(_ config: SnapshotConfig) throws -> Data {
        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        return try #require(ExportManager.pngData(from: image))
    }

    private func pixels(
        _ config: SnapshotConfig
    ) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let image = try #require(ExportManager.renderCGImage(config, scale: 2))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return (bytes, image.width, image.height)
    }

    /// The horizontal span of the pixels that visibly differ between two same-size renders.
    /// Text antialiasing and the card's shadow vary by a level or two across a render.
    private func changedColumns(
        _ first: SnapshotConfig, _ second: SnapshotConfig
    ) throws
        -> ClosedRange<Int>?
    {
        let (a, b) = (try pixels(first), try pixels(second))
        try #require(a.width == b.width && a.height == b.height)
        var columns: ClosedRange<Int>?
        for index in stride(from: 0, to: a.bytes.count, by: 4) {
            let delta = (0..<3).map { abs(Int(a.bytes[index + $0]) - Int(b.bytes[index + $0])) }
            guard delta.contains(where: { $0 > 8 }) else { continue }
            let column = (index / 4) % a.width
            columns =
                columns.map { min($0.lowerBound, column)...max($0.upperBound, column) }
                ?? column...column
        }
        return columns
    }

    @Test func aHiddenCursorRendersLikeNoCursorControlAtAll() throws {
        let explicit = ANSIRenderer.attributedString(stream, font: font, cursor: .hidden)
        #expect(explicit == ANSIRenderer.attributedString(stream, font: font))
        #expect(try png(capture(.hidden)) == png(SnapshotConfig(code: stream, language: .terminal)))
    }

    @Test(arguments: [TerminalCursorStyle.block, .bar])
    func theCursorReachesImageAndRichTextButNeverPlainText(_ cursor: TerminalCursorStyle) throws {
        let config = capture(cursor)
        #expect(try png(config) != png(capture()))
        #expect(
            RichPasteboard.highlightedCode(for: config)
                != RichPasteboard.highlightedCode(for: capture()))
        #expect(config.sidecarText == capture().sidecarText)
        #expect(config.richClipboardText == capture().richClipboardText)
    }

    /// Roboto Mono has no glyph for the bar, so it comes from a fallback font.
    @Test(arguments: ["Menlo", "SF Mono", "JetBrains Mono", "Roboto Mono"])
    func aBarOverACellOnlyChangesThatCellsColumn(_ family: String) throws {
        var hidden = capture(code: grid)
        hidden.fontName = family
        var bar = hidden
        bar.terminalCursor = .bar
        let columns = try #require(try changedColumns(hidden, bar))
        // Rendered at 2x. Anything wider means the rest of the row moved.
        let advance = CodeFont.advance(
            of: "0",
            in: CodeFont.resolved(family: family, size: hidden.fontSize, ligatures: false))
        #expect(CGFloat(columns.count) <= advance * 2)
    }

    @Test func aBarDoesNotWidenARowInRichText() {
        let plain = ANSIRenderer.attributedString(grid, font: font).size().width
        let bar = ANSIRenderer.attributedString(grid, font: font, cursor: .bar).size().width
        #expect(abs(plain - bar) < 0.5)
    }

    @Test func aParsedCursorGlyphTakesItsUsualWidth() {
        let string = ANSIRenderer.attributedString("\u{258F}", font: font)
        #expect(string.attribute(.kern, at: 0, effectiveRange: nil) == nil)
    }

    /// A cell's background covers a glyph drawn before it, so the bar must not rely on one.
    @Test func aBarOnAColoredCellIsVisibleInTheImage() throws {
        let colored = "\u{1B}[2J\u{1B}[1;1H\u{1B}[41m colored \u{1B}[0m\u{1B}[1;3H"
        #expect(try png(capture(.bar, code: colored)) == png(capture(.block, code: colored)))
        #expect(try png(capture(.bar, code: colored)) != png(capture(.hidden, code: colored)))
    }

    @Test func anEmptyCaptureDrawsNoCursorOnThePlaceholder() throws {
        #expect(try png(capture(.block, code: "")) == png(capture(.hidden, code: "")))
        #expect(RichPasteboard.highlightedCode(for: capture(.bar, code: "")).length == 0)
    }

    @Test(arguments: [TerminalCursorStyle.block, .bar])
    func aRedactedRowKeepsNoCursorAndNoContent(_ cursor: TerminalCursorStyle) {
        let secret = "SYNTHETIC_SECRET_123456789"
        let string = ANSIRenderer.attributedString(
            "safe\nAPI_KEY=\(secret)", font: font, redacting: [2...2], cursor: cursor)
        #expect(string.string == "safe\n\(SnapshotConfig.redactedLinePlaceholder)")
        string.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: string.length))
        { value, _, _ in
            #expect(value == nil)
        }
    }

    /// A mask's length follows its row, so a cursor must change neither it nor reveal a column.
    @Test(
        arguments: [TerminalCursorStyle.block, .bar],
        ["ab", "abcdef", "abcdefghijklmnopqrstuvwxyz"])
    func aCursorOnARedactedRowLeavesTheMaskAsItWas(
        _ cursor: TerminalCursorStyle, _ secret: String
    ) throws {
        let codes = [
            "safe\nAPI_KEY=\(secret)",  // line mode: at the end of the row
            "\u{1B}[2J\u{1B}[1;1Hsafe\u{1B}[2;1HAPI_KEY=\(secret)\u{1B}[2;3H",  // on a cell
            "\u{1B}[2J\u{1B}[1;1Hsafe\u{1B}[2;1HAPI_KEY=\(secret)\u{1B}[2;70H",  // padded out
        ]
        for code in codes {
            var hidden = capture(.hidden, code: code)
            hidden.redactedLineRanges = [2...2]
            var drawn = hidden
            drawn.terminalCursor = cursor
            #expect(try png(drawn) == png(hidden))
        }
    }

    @Test func theCacheDoesNotServeAStaleVariant() {
        let manager = HighlightManager.shared
        func string(_ cursor: TerminalCursorStyle) -> AttributedString {
            manager.terminalAttributedString(
                for: stream, theme: .oneDark, font: font, columns: nil, cursor: cursor)
        }
        func rows(_ cursor: TerminalCursorStyle) -> [AttributedString] {
            manager.terminalAttributedLines(
                for: stream, theme: .oneDark, font: font, columns: nil, cursor: cursor)
        }
        #expect(string(.hidden) != string(.block))
        #expect(string(.block) != string(.bar))
        #expect(rows(.hidden) != rows(.block))
        #expect(rows(.block) != rows(.bar))
    }

    // MARK: Persistence

    @Test func theDefaultLeavesEncodedStylesUnchanged() throws {
        let json = try String(
            decoding: JSONEncoder().encode(StyleSnapshot(capturing: capture())), as: UTF8.self)
        #expect(json.contains("terminalCursor") == false)
    }

    @Test func aStyleWithoutTheFieldDecodesToTheDefault() throws {
        let style = try JSONDecoder().decode(
            StyleSnapshot.self, from: Data(#"{"themeID":"dracula"}"#.utf8))
        var config = capture(.bar)
        style.apply(to: &config)
        #expect(config.terminalCursor == .hidden)
    }

    @Test func anUnknownValueFallsBackInAPresetButFailsARecipe() throws {
        let json = #"{"themeID":"dracula","terminalCursor":"beam"}"#
        let style = try JSONDecoder().decode(StyleSnapshot.self, from: Data(json.utf8))
        #expect(style.terminalCursor == nil)

        let decoder = JSONDecoder()
        decoder.userInfo[StyleSnapshot.strictDecodingKey] = true
        #expect(throws: DecodingError.self) {
            try decoder.decode(StyleSnapshot.self, from: Data(json.utf8))
        }
    }

    @Test func aNonTerminalDocumentCannotCarryACursorIntoAPreset() {
        var config = capture(.bar)
        config.language = .swift
        #expect(StyleSnapshot(capturing: config).terminalCursor == nil)
    }

    @Test func aRecipeCarriesTheCursor() throws {
        let recipe = WorkspaceRecipe(
            name: "Terminal", style: StyleSnapshot(capturing: capture(.bar)))
        let data = try WorkspaceRecipeDocument(recipe: recipe).jsonData()
        #expect(try WorkspaceRecipeDocument.recipe(from: data).style.terminalCursor == .bar)
    }

    @Test func aRestoredWindowKeepsTheCursorAndToleratesOlderArchives() throws {
        let themes = CustomThemeStore(defaults: testDefaults())
        let archived = try #require(EditorWindowState(config: capture(.block)).encoded())
        let restored = try #require(EditorWindowState.decoded(from: archived))
        #expect(restored.config(themes: themes).terminalCursor == .block)

        let older = try #require(EditorWindowState.decoded(from: Data("{}".utf8)))
        #expect(older.config(themes: themes).terminalCursor == .hidden)
    }

    @Test func aGarbageStoredPreferenceReadsAsTheDefault() {
        let defaults = testDefaults()
        defaults.set("beam", forKey: SettingsCodec.Keys.terminalCursor)
        #expect(SettingsCodec.readConfig(from: defaults).terminalCursor == .hidden)
    }

    @Test func aShareLinkCarriesTheCursor() throws {
        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: capture(.bar)))
        var restored = SnapshotConfig()
        try SnapshotShareLink.snapshot(from: url).apply(to: &restored)
        #expect(restored.terminalCursor == .bar)
    }

    /// A redacted link holds only the final screen, so the cursor's place is unknown.
    @Test func aRedactedShareLinkDropsTheCursor() throws {
        var config = capture(.bar)
        config.redactedLineRanges = [1...1]
        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: config))
        var restored = SnapshotConfig()
        try SnapshotShareLink.snapshot(from: url).apply(to: &restored)
        #expect(restored.terminalCursor == .hidden)
    }
}
