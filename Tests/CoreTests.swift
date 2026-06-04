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
    }

    @Test func themeLookupFallsBackToOneDark() {
        #expect(Theme.all.count == 6)
        #expect(Theme.theme(withID: "dracula").id == "dracula")
        #expect(Theme.theme(withID: "does-not-exist").id == Theme.oneDark.id)
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

    @Test func malformedHexFallsBackToBlack() throws {
        let ns = try #require(NSColor(Color(hex: "nonsense")).usingColorSpace(.sRGB))
        #expect(ns.redComponent == 0)
        #expect(ns.greenComponent == 0)
        #expect(ns.blueComponent == 0)
    }
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
}
