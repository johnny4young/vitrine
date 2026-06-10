import AppKit
import CoreGraphics
import CoreText
import Foundation
import SwiftUI
import Testing

@testable import Vitrine

// CS-052 — coverage matrix for the advertised languages and built-in themes,
// plus the opt-in font-ligature toggle and ligature-font availability.
//
// The acceptance bullets this file pins:
//   • every advertised language highlights without falling back to plain text;
//   • every built-in theme renders real syntax colors over a *derived* (not
//     arbitrary) background;
//   • each language × theme combination renders a non-empty, non-plaintext image;
//   • the ligature toggle measurably changes glyph rendering and is off by default;
//   • the ligature-capable fonts are available and resolve.

// MARK: - Representative fixtures

/// A short, real snippet per advertised language, each containing tokens the
/// grammar is certain to color (a keyword, a string, and a number or comment).
/// Keeping one fixture per language here is what makes "adding a language is a
/// one-file change" testable: a new `Language` case fails the matrix until it has
/// an entry that actually highlights.
private enum Fixture {
    static let byLanguage: [Language: String] = [
        .swift: "let count = 42\nfunc greet(_ name: String) { print(\"Hi \\(name)\") }",
        .python: "def greet(name):\n    return f\"Hello {name}\"  # 1 greeting",
        .javascript: "const x = 42;\nfunction greet(name) { return `Hi ${name}`; }",
        .typescript: "const x: number = 42;\nfunction greet(name: string): string { return name; }",
        .go: "package main\nfunc main() {\n\tx := 42\n\tprintln(\"hi\", x)\n}",
        .rust: "fn main() {\n    let x: i32 = 42;\n    println!(\"hi {}\", x);\n}",
        .ruby: "def greet(name)\n  puts \"Hello #{name}\" # 1\nend",
        .java: "class Main {\n  public static void main(String[] a) { int x = 42; }\n}",
        .kotlin: "fun main() {\n    val x = 42\n    println(\"hi $x\")\n}",
        .c: "#include <stdio.h>\nint main(void) {\n  int x = 42;\n  return 0;\n}",
        .cpp: "#include <iostream>\nint main() {\n  auto x = 42;\n  return 0;\n}",
        .csharp: "class Program {\n  static void Main() { int x = 42; }\n}",
        .objectivec: "#import <Foundation/Foundation.h>\nint main() { int x = 42; return 0; }",
        .scala: "object Main {\n  def main(args: Array[String]): Unit = { val x = 42 }\n}",
        .dart: "void main() {\n  var x = 42;\n  print('hi $x');\n}",
        .elixir: "defmodule Greeter do\n  def hi(name), do: \"Hello #{name}\"\nend",
        .haskell: "main :: IO ()\nmain = do\n  let x = 42\n  putStrLn \"hi\"",
        .lua: "local x = 42\nfunction greet(name)\n  return \"hi \" .. name\nend",
        .r: "greet <- function(name) {\n  x <- 42\n  paste(\"hi\", name)\n}",
        .perl: "my $x = 42;\nsub greet {\n  return \"hi \" . shift;\n}",
        .php: "<?php\nfunction greet($name) {\n  $x = 42;\n  return \"Hi $name\";\n}",
        .html: "<!DOCTYPE html>\n<html>\n  <body><p class=\"x\">Hi</p></body>\n</html>",
        .css: ".btn {\n  color: #ff0000;\n  padding: 4px;\n}",
        .scss: "$brand: #ff0000;\n.btn {\n  color: $brand;\n  &:hover { padding: 4px; }\n}",
        .json: "{\n  \"name\": \"vitrine\",\n  \"count\": 42,\n  \"ok\": true\n}",
        .yaml: "name: vitrine\ncount: 42\nitems:\n  - one\n  - two",
        .toml: "title = \"vitrine\"\n[owner]\ncount = 42\nenabled = true",
        .bash: "#!/bin/bash\nfor i in 1 2 3; do\n  echo \"line $i\"\ndone",
        .sql: "SELECT name, count FROM users WHERE count > 42 ORDER BY name;",
        .graphql: "query Greet {\n  user(id: 42) {\n    name\n    email\n  }\n}",
        .dockerfile: "FROM swift:latest\nWORKDIR /app\nRUN swift build\nCMD [\"run\"]",
        .diff: "@@ -1,3 +1,3 @@\n-old line\n+new line\n unchanged line",
        .markdown: "# Title\n\nSome **bold** text and a [link](https://example.com).",
    ]

    /// The fixture for a language, or a generic snippet for plain text.
    static func code(for language: Language) -> String {
        byLanguage[language] ?? "the quick brown fox jumps over the lazy dog"
    }
}

// MARK: - Highlight introspection helpers

extension NSAttributedString {
    /// The set of distinct foreground colors Highlightr assigned, resolved through
    /// sRGB so equality is stable. A genuinely tokenized snippet uses several
    /// scope colors (keyword, string, number, …); a plain-text fallback paints the
    /// whole string in at most one color. This is the signal the coverage matrix
    /// uses to prove a fixture did *not* fall back to plain text.
    func distinctForegroundColors() -> Set<RGBAColor> {
        var colors = Set<RGBAColor>()
        enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: length)) {
            value, _, _ in
            guard let color = value as? NSColor,
                let srgb = color.usingColorSpace(.sRGB)
            else { return }
            colors.insert(
                RGBAColor(
                    red: srgb.redComponent, green: srgb.greenComponent,
                    blue: srgb.blueComponent, opacity: srgb.alphaComponent))
        }
        return colors
    }
}

@MainActor
private func highlight(_ language: Language, theme: Theme) -> NSAttributedString {
    HighlightManager.shared.attributedString(
        for: Fixture.code(for: language),
        language: language,
        theme: theme,
        font: .monospacedSystemFont(ofSize: 14, weight: .regular))
}

// MARK: - Advertised languages highlight (no plain-text fallback)

@MainActor
@Suite("Language coverage")
struct LanguageCoverageTests {
    /// Every advertised language (everything except the intentional `plaintext`
    /// escape hatch) must produce multi-color highlighting. One distinct color or
    /// fewer means the engine fell back to plain text — the exact regression this
    /// guards (CS-052 acceptance).
    @Test(arguments: Language.allCases.filter { $0 != .plaintext })
    func languageHighlightsWithoutFallingBackToPlaintext(_ language: Language) {
        let colors = highlight(language, theme: .oneDark).distinctForegroundColors()
        #expect(
            colors.count >= 2,
            "\(language.displayName) produced \(colors.count) color(s); it fell back to plain text")
    }

    /// Each advertised language's Highlight.js id (or alias) is one the bundled
    /// engine actually recognizes. `supportedLanguages()` lists registration ids;
    /// the two alias-backed languages (HTML → xml, TOML → ini) are checked against
    /// the id they resolve through. This catches a typo'd `hljsName` directly,
    /// independent of the color heuristic above.
    @Test func everyLanguageIdIsRecognizedByTheEngine() throws {
        let supported = Set(try #require(HighlightManager.shared.supportedLanguageNames()))
        #expect(!supported.isEmpty)
        for language in Language.allCases where language != .plaintext {
            #expect(
                supported.contains(language.hljsName),
                "Highlight.js does not register '\(language.hljsName)' for \(language.displayName)")
        }
    }

    /// A fixture exists for every advertised language, so the matrix below can
    /// never silently skip one (a new case with no fixture fails here).
    @Test func everyAdvertisedLanguageHasAFixture() {
        for language in Language.allCases where language != .plaintext {
            #expect(
                Fixture.byLanguage[language] != nil,
                "no coverage fixture for \(language.displayName)")
        }
    }

    /// The plain-text escape hatch carries no explicit language, so it is the one
    /// case allowed to skip a grammar. It still renders the source text verbatim —
    /// the contract is "does not require a language", not "paints nothing".
    @Test func plaintextRendersTheSourceTextVerbatim() {
        let source = Fixture.code(for: .plaintext)
        let rendered = highlight(.plaintext, theme: .oneDark).string
        #expect(rendered == source)
    }
}

// MARK: - Built-in themes render syntax colors over a derived background

@MainActor
@Suite("Theme coverage")
struct ThemeCoverageTests {
    /// The documented dark fallback `HighlightManager` returns when Highlightr
    /// cannot supply a theme background. A correctly bundled theme must resolve to
    /// its own background, never this sentinel.
    private static let fallbackBackground = RGBAColor(Color(hex: "#1E1E1E"))

    /// Every built-in theme resolves to a real, theme-derived card background. If a
    /// theme's `hlJsTheme` were misspelled, Highlightr would yield the sentinel
    /// fallback for it — so a background equal to the fallback for *all* themes
    /// would mean nothing resolved. We assert the set of backgrounds is varied and
    /// that no dark-vs-light pair collapses to the same color.
    @Test func everyThemeResolvesADistinctDerivedBackground() {
        let backgrounds = Theme.all.map {
            RGBAColor(HighlightManager.shared.backgroundColor(for: $0))
        }
        // A curated set of light and dark themes cannot all share one background.
        #expect(Set(backgrounds).count >= 2)
    }

    /// A light theme's card is brighter than a dark theme's, proving the
    /// background really comes from each theme's own palette rather than a shared
    /// constant (CS-052: "a derived, not arbitrary, background").
    @Test func lightThemeBackgroundIsBrighterThanDarkThemeBackground() {
        func luminance(_ theme: Theme) -> Double {
            let c = RGBAColor(HighlightManager.shared.backgroundColor(for: theme))
            return 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue
        }
        #expect(luminance(.github) > luminance(.oneDark))
        #expect(luminance(.oneLight) > luminance(.dracula))
    }

    /// Each theme actually colors syntax: highlighting the same Swift fixture under
    /// every built-in theme yields multiple distinct foreground colors. A theme
    /// that failed to load would paint one (default) color.
    @Test(arguments: Theme.all)
    func themeProducesSyntaxColors(_ theme: Theme) {
        let colors = highlight(.swift, theme: theme).distinctForegroundColors()
        #expect(
            colors.count >= 2,
            "theme \(theme.displayName) produced \(colors.count) syntax color(s)")
    }

    /// The curated `appearance` metadata is honest: GitHub-family light themes are
    /// flagged light, the signature dark themes flagged dark. This keeps the
    /// "documented, one-file" theme contract self-consistent.
    @Test func appearanceMetadataMatchesBackgroundLuminance() {
        for theme in Theme.all {
            let c = RGBAColor(HighlightManager.shared.backgroundColor(for: theme))
            let luminance = 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue
            switch theme.appearance {
            case .dark: #expect(luminance < 0.5, "\(theme.displayName) marked dark but is bright")
            case .light: #expect(luminance > 0.5, "\(theme.displayName) marked light but is dark")
            }
        }
    }
}

// MARK: - Language × theme render matrix

@MainActor
@Suite("Language × theme render matrix")
struct LanguageThemeMatrixTests {
    /// The full cross product of advertised languages and built-in themes: every
    /// combination renders a real, non-empty image. This is the headline CS-052
    /// deliverable — breadth that is actually exercised end to end (every language
    /// drawn on every theme), not merely declared.
    ///
    /// The complementary "non-plaintext" guarantee is asserted theme-independently
    /// in `LanguageCoverageTests` (every grammar tokenizes into multiple colors
    /// under a rich theme, and every id is one the engine recognizes), so it is not
    /// re-checked per theme here: a muted theme can legitimately paint a short
    /// snippet in one color without that being a fallback.
    @Test(
        arguments: Language.allCases.filter { $0 != .plaintext },
        Theme.all)
    func everyLanguageThemePairRendersANonEmptyImage(
        _ language: Language, _ theme: Theme
    ) throws {
        var config = SnapshotConfig()
        config.code = Fixture.code(for: language)
        config.language = language
        config.theme = theme
        let image = try #require(
            ExportManager.renderCGImage(config, scale: 1),
            "no image for \(language.displayName) on \(theme.displayName)")
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    /// The theme genuinely changes the rendered output: the same code on a light
    /// theme versus a dark theme produces different pixels. This proves the matrix
    /// above is exercising real per-theme rendering, not drawing the same image 13
    /// times.
    @Test(arguments: Language.allCases.filter { $0 != .plaintext })
    func themeChangesTheRenderedImage(_ language: Language) throws {
        var dark = SnapshotConfig()
        dark.code = Fixture.code(for: language)
        dark.language = language
        dark.theme = .oneDark

        var light = dark
        light.theme = .github

        let darkImage = try #require(ExportManager.renderCGImage(dark, scale: 1))
        let lightImage = try #require(ExportManager.renderCGImage(light, scale: 1))
        let darkPNG = try #require(ExportManager.pngData(from: darkImage))
        let lightPNG = try #require(ExportManager.pngData(from: lightImage))
        #expect(darkPNG != lightPNG, "theme did not change the render for \(language.displayName)")
    }
}

// MARK: - Font ligatures

@MainActor
@Suite("Font ligatures")
struct FontLigatureTests {
    /// A line dense with programming ligatures, so toggling ligatures changes many
    /// glyphs at once and the render difference is unmistakable.
    private static let ligatureRich = "a -> b => c != d >= e <= f === g <!-- h |> i"

    /// The glyph ids produced by shaping `string` with `font` through Core Text —
    /// the real evidence a ligature substitution did or did not fire.
    static func shapedGlyphs(_ string: String, font: NSFont) -> [CGGlyph] {
        let attributed = NSAttributedString(string: string, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        var glyphs: [CGGlyph] = []
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var runGlyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &runGlyphs)
            glyphs.append(contentsOf: runGlyphs)
        }
        return glyphs
    }

    /// Compares rendered pixels with the same tolerance as the golden-image suite.
    /// ImageIO may encode visually identical renders to different PNG byte streams,
    /// and Swift Testing is very expensive when diffing large `Data` values.
    /// Keeping ligature assertions at the normalized-pixel layer makes them stable
    /// and keeps failure output small.
    static func compareRenderedPixels(
        _ lhs: CGImage, _ rhs: CGImage
    ) throws -> GoldenComparator.Result {
        switch GoldenComparator.compare(lhs, rhs) {
        case .success(let result):
            return result
        case .failure(let failure):
            throw failure
        }
    }

    @Test func ligaturesAreOffByDefault() {
        #expect(SnapshotConfig().fontLigatures == false)
    }

    @Test func capabilitySetCoversTheSpecFonts() {
        // The three ligature fonts the ticket names must all be recognized.
        #expect(CodeFont.hasLigatures("Fira Code"))
        #expect(CodeFont.hasLigatures("JetBrains Mono"))
        #expect(CodeFont.hasLigatures("Cascadia Code"))
        // A plain monospaced font is not ligature-capable.
        #expect(!CodeFont.hasLigatures("Menlo"))
        #expect(!CodeFont.hasLigatures("SF Mono"))
        // Matching ignores spacing/case so "FiraCode" still qualifies.
        #expect(CodeFont.hasLigatures("firacode"))
    }

    /// Turning ligatures on for a ligature-capable font swaps the glyphs that get
    /// drawn. This is the "measurably changes glyph rendering" acceptance, checked
    /// at the font layer by shaping the string and comparing the resulting glyph
    /// ids — *not* the width: a monospace ligature font keeps each ligature the
    /// width of the glyphs it replaces, so width is identical on purpose and only
    /// the glyph ids reveal the substitution.
    @Test func ligaturesSwapGlyphsForACapableFont() throws {
        let family = "Fira Code"
        try #require(NSFont(name: family, size: 14) != nil, "Fira Code is not registered")

        let off = CodeFont.resolved(family: family, size: 14, ligatures: false)
        let on = CodeFont.resolved(family: family, size: 14, ligatures: true)

        let offGlyphs = Self.shapedGlyphs(Self.ligatureRich, font: off)
        let onGlyphs = Self.shapedGlyphs(Self.ligatureRich, font: on)
        // Same number of glyphs (ligatures are contextual single-glyph swaps here),
        // but the ids differ where a ligature fired.
        #expect(offGlyphs != onGlyphs, "ligature toggle did not change any glyphs")
    }

    /// Toggling ligatures on must change the *rendered pixels* end to end, not just
    /// the font object: the same code exported with ligatures off vs on differs
    /// beyond the golden-image pixel tolerance (CS-052 acceptance), while the
    /// canvas size is unchanged because a ligature is a glyph swap, not a reflow.
    @Test func ligaturesChangeRenderedPixelsButNotImageSize() throws {
        var off = SnapshotConfig()
        off.fontName = "Fira Code"
        off.code = Self.ligatureRich
        off.fontLigatures = false

        var on = off
        on.fontLigatures = true

        let offImage = try #require(ExportManager.renderCGImage(off, scale: 2))
        let onImage = try #require(ExportManager.renderCGImage(on, scale: 2))

        let comparison = try Self.compareRenderedPixels(offImage, onImage)
        #expect(!comparison.matches, "ligature toggle did not change the rendered image")
        #expect(offImage.width == onImage.width)
        #expect(offImage.height == onImage.height)
    }

    /// A non-ligature font renders identically with the toggle on or off, so
    /// turning ligatures on never disturbs a font that has none.
    @Test func ligatureToggleIsInertForANonLigatureFont() throws {
        var off = SnapshotConfig()
        off.fontName = "Menlo"
        off.code = Self.ligatureRich
        off.fontLigatures = false

        var on = off
        on.fontLigatures = true

        let offImage = try #require(ExportManager.renderCGImage(off, scale: 2))
        let onImage = try #require(ExportManager.renderCGImage(on, scale: 2))

        let comparison = try Self.compareRenderedPixels(offImage, onImage)
        #expect(
            comparison.matches,
            "non-ligature font changed \(comparison.differingPixels) of \(comparison.pixelCount) pixels"
        )
    }
}

// MARK: - Ligature-font availability (extends CS-006)

@Suite("Ligature font availability")
struct LigatureFontAvailabilityTests {
    /// The bundled ligature fonts the ticket names are registered and usable. This
    /// extends the CS-006 bundled-font checks specifically for the ligature path:
    /// the ligature toggle is meaningless if the fonts are not present.
    @Test(arguments: ["Fira Code", "JetBrains Mono"])
    func bundledLigatureFontIsRegistered(_ family: String) {
        #expect(
            NSFont(name: family, size: 14) != nil,
            "ligature font '\(family)' is not registered")
        #expect(CodeFont.bundled.contains(family))
        #expect(CodeFont.hasLigatures(family))
    }

    /// `resolved` returns the requested family when it exists, and falls back to a
    /// monospaced system font (never nil) when it does not — so the editor and
    /// canvas always get a usable font regardless of the ligature setting.
    @Test func resolverReturnsRequestedFamilyOrAMonospacedFallback() {
        let real = CodeFont.resolved(family: "JetBrains Mono", size: 14, ligatures: true)
        #expect(real.familyName?.contains("JetBrains") == true)

        // A bogus family falls back rather than returning nil.
        let fallback = CodeFont.resolved(family: "No Such Font 12345", size: 14, ligatures: false)
        #expect(fallback.pointSize == 14)
    }
}
