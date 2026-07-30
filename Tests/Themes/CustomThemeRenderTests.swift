import AppKit
import Foundation
import Testing

@testable import Vitrine

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
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        let added = try store.importThemes(from: ThemeTestFixtures.sampleThemeFileData())
        let theme = try #require(added.first)

        var config = SnapshotConfig()
        config.code = ThemeTestFixtures.sampleCode
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
        let theme = Theme(
            id: "custom.render", displayName: "Render", palette: ThemeTestFixtures.samplePalette())
        #expect(distinctColors(ThemeTestFixtures.sampleCode, theme: theme).count >= 2)
    }

    @Test func aCustomThemeUsesItsOwnPaletteBackground() {
        let theme = Theme(
            id: "custom.bg", displayName: "BG", palette: ThemeTestFixtures.samplePalette())
        let background = RGBAColor(HighlightManager.shared.backgroundColor(for: theme))
        // The card background is exactly the palette's own background color.
        #expect(background == RGBAColor(ThemeTestFixtures.samplePalette().background.color))
    }

    @Test func aCustomThemeRenderIsDeterministicAcrossRenders() throws {
        // Behavior: "exported screenshots are deterministic across custom
        // themes." Rendering the same custom-theme config twice yields byte-identical
        // PNG output, because the palette is captured in fixed sRGB.
        let theme = Theme(
            id: "custom.det", displayName: "Deterministic",
            palette: ThemeTestFixtures.samplePalette())
        var config = SnapshotConfig()
        config.code = ThemeTestFixtures.sampleCode
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
            id: "custom.dark", displayName: "Dark", palette: ThemeTestFixtures.samplePalette())
        let lightPalette = ThemePalette(
            background: HexColor("#FFFFFF")!, foreground: HexColor("#1A1A1A")!,
            keyword: HexColor("#AF00DB")!, string: HexColor("#A31515")!)
        let lightTheme = Theme(
            id: "custom.light", displayName: "Light", palette: lightPalette)

        var darkConfig = SnapshotConfig()
        darkConfig.code = ThemeTestFixtures.sampleCode
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
        let theme = Theme(
            id: "custom.cache", displayName: "Cache", palette: ThemeTestFixtures.samplePalette())
        let first = highlight(ThemeTestFixtures.sampleCode, theme: theme)
        let second = highlight(ThemeTestFixtures.sampleCode, theme: theme)
        #expect(first.isEqual(to: second))
        #expect(first.string == ThemeTestFixtures.sampleCode)
    }

    /// The critical invariant that lets a custom theme be cached at all: a palette that
    /// changes under a **stable theme id** must not serve the previous palette's colors.
    /// The cache keys on the palette itself, so this is a fresh render, not a stale hit —
    /// exactly the case the built-in `themeID`-keyed cache had to exclude.
    @Test func changingThePaletteUnderAStableIDReflowsTheColors() {
        let warm = Theme(
            id: "custom.mutable", displayName: "Mutable", palette: ThemeTestFixtures.samplePalette()
        )
        _ = highlight(ThemeTestFixtures.sampleCode, theme: warm)  // prime the cache under this id

        let differentPalette = ThemePalette(
            background: HexColor("#FFFFFF")!, foreground: HexColor("#111111")!,
            keyword: HexColor("#FF0000")!, string: HexColor("#00AA00")!)
        let mutated = Theme(
            id: "custom.mutable", displayName: "Mutable", palette: differentPalette)

        let keywordColor = RGBAColor(differentPalette.keyword.color)
        let rendered = highlight(ThemeTestFixtures.sampleCode, theme: mutated)
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
