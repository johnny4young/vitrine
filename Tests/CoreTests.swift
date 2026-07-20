import SwiftUI
import Testing

@testable import Vitrine

@Suite("Models")
struct ModelTests {
    @Test func languageCatalog() {
        #expect(Language.allCases.contains(.swift))
        #expect(Language.swift.hljsName == "swift")
        #expect(Language.cpp.hljsName == "cpp")
        #expect(Language.csharp.displayName == "C#")
        #expect(Language.swift.id == "swift")
        // The supported language additions, including alias-backed ids.
        #expect(Language.objectivec.displayName == "Objective-C")
        #expect(Language.toml.hljsName == "ini")
        #expect(Language.html.hljsName == "xml")
        #expect(Language.allCases.contains(.graphql))
    }

    @Test func themeLookupFallsBackToOneDark() {
        // The curated built-in set: a coherent spread of dark and light
        // themes, each a verified Highlight.js stylesheet.
        #expect(Theme.all.count == 13)
        #expect(Theme.theme(withID: "dracula").id == "dracula")
        #expect(Theme.theme(withID: "does-not-exist").id == Theme.oneDark.id)
        // Identifiers are unique so the picker and persistence never collide.
        #expect(Set(Theme.all.map(\.id)).count == Theme.all.count)
    }

    @Test func snapshotConfigDefaults() {
        let config = SnapshotConfig()
        #expect(config.theme.id == Theme.oneDark.id)
        #expect(config.fontSize == 14)
        #expect(config.padding == 32)
        #expect(config.showChrome)
    }

    @Test func gradientPresetsHaveTwoStops() {
        for preset in GradientPreset.allCases {
            #expect(preset.colors.count == 2)
        }
    }
}

@Suite("Color+Hex")
struct ColorHexTests {
    @Test func parsesSixDigitHex() throws {
        let color = Color(hex: "#FF8040")
        let ns = try #require(NSColor(color).usingColorSpace(.sRGB))
        #expect(abs(ns.redComponent - 1.0) < 0.01)
        #expect(abs(ns.greenComponent - 0.502) < 0.02)
        #expect(abs(ns.blueComponent - 0.251) < 0.02)
    }

    @Test func parsesThreeDigitShorthand() throws {
        // "#F80" expands to "#FF8800".
        let ns = try #require(NSColor(Color(hex: "#F80")).usingColorSpace(.sRGB))
        #expect(abs(ns.redComponent - 1.0) < 0.01)
        #expect(abs(ns.greenComponent - 0.533) < 0.02)
        #expect(abs(ns.blueComponent - 0.0) < 0.01)
    }

    @Test func parsesEightDigitHexWithAlpha() throws {
        // Half-transparent red.
        let ns = try #require(NSColor(Color(hex: "#FF000080")).usingColorSpace(.sRGB))
        #expect(abs(ns.redComponent - 1.0) < 0.01)
        #expect(abs(ns.alphaComponent - 0.502) < 0.02)
    }

    // Note: malformed input (non-hex characters or an unsupported length) now
    // trips an `assertionFailure` in DEBUG to surface palette typos immediately,
    // so it cannot be exercised here without trapping the test process. The
    // graceful opaque-black fallback remains in release builds.
}

@Suite("LanguageDetector")
struct LanguageDetectorTests {
    @Test func detectsURLs() {
        #expect(LanguageDetector.isURL("https://example.com"))
        #expect(LanguageDetector.isURL("http://localhost:3000/path"))
        #expect(!LanguageDetector.isURL("let x = 1"))
        #expect(!LanguageDetector.isURL("https://example.com\nmore text"))
    }

    @Test(arguments: [
        ("func greet() { print(\"hi\") }", Language.swift),
        ("def greet():\n    pass", Language.python),
        ("package main\nfunc main() { fmt.Println() }", Language.go),
        ("SELECT * FROM users WHERE id = 1", Language.sql),
        ("<!doctype html><html><body></body></html>", Language.html),
        ("", Language.plaintext),
        ("just some words here", Language.plaintext),
    ])
    func detectsLanguages(_ snippet: String, _ expected: Language) {
        #expect(LanguageDetector.detect(snippet) == expected)
    }
}

@Suite("ExportManager")
@MainActor
struct ExportManagerTests {
    @Test func rendersNonEmptyPNG() throws {
        var config = SnapshotConfig()
        config.code = "let answer = 42"
        let cgImage = try #require(ExportManager.renderCGImage(config, scale: 2))
        #expect(cgImage.width > 0)
        let png = try #require(ExportManager.pngData(from: cgImage))
        // PNG magic number: 89 50 4E 47.
        #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test func higherScaleProducesLargerImage() throws {
        var config = SnapshotConfig()
        config.code = "print(1)"
        let small = try #require(ExportManager.renderCGImage(config, scale: 1))
        let large = try #require(ExportManager.renderCGImage(config, scale: 3))
        #expect(large.width > small.width)
    }

    @Test func rendersNSImageForSharing() throws {
        var config = SnapshotConfig()
        config.code = "let x = 1"
        let image = try #require(ExportManager.renderNSImage(config, scale: 2))
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test func rendersPDFData() throws {
        var config = SnapshotConfig()
        config.code = "let x = 1"
        let pdf = try #require(ExportManager.pdfData(config))
        // PDF magic number: "%PDF".
        #expect(Array(pdf.prefix(4)) == [0x25, 0x50, 0x44, 0x46])
    }
}
