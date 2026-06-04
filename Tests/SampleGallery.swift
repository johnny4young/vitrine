import AppKit
import SwiftUI
import Testing

@testable import Vitrine

/// Not a pass/fail unit test in spirit — it renders a gallery of real code
/// screenshots (the actual `SnapshotCanvas` → `ImageRenderer` pipeline) across
/// themes / gradients / languages / layout options, plus a clipboard round-trip,
/// writing PNGs to a temp dir for visual inspection. It also asserts every render
/// succeeds, so it doubles as an end-to-end rendering regression test.
@MainActor
@Suite("Sample gallery")
struct SampleGalleryTests {
    static let outDir: URL = {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vitrine-samples", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        print("GALLERY_DIR \(dir.path)")
        return dir
    }()

    static let swiftSample = """
        import SwiftUI

        struct CounterView: View {
            @State private var count = 0

            var body: some View {
                Button("Tapped \\(count) times") {
                    count += 1
                }
                .buttonStyle(.borderedProminent)
            }
        }
        """

    @discardableResult
    private func write(_ config: SnapshotConfig, _ name: String, scale: CGFloat = 2) -> Bool {
        guard let cgImage = ExportManager.renderCGImage(config, scale: scale),
            let png = ExportManager.pngData(from: cgImage)
        else {
            Issue.record("render failed for \(name)")
            return false
        }
        let url = Self.outDir.appendingPathComponent("\(name).png")
        try? png.write(to: url)
        print("SAMPLE \(name) \(cgImage.width)x\(cgImage.height) \(url.path)")
        return true
    }

    @Test func themesSameInput() {
        for theme in Theme.all {
            var config = SnapshotConfig()
            config.code = Self.swiftSample
            config.theme = theme
            #expect(write(config, "theme-\(theme.id)"))
        }
    }

    @Test func gradientsSameInput() {
        for preset in GradientPreset.allCases {
            var config = SnapshotConfig()
            config.code = Self.swiftSample
            config.background = .gradient(preset)
            #expect(write(config, "gradient-\(preset.rawValue.lowercased())"))
        }
    }

    @Test func layoutVariations() {
        var noChrome = SnapshotConfig()
        noChrome.code = Self.swiftSample
        noChrome.showChrome = false
        write(noChrome, "layout-no-chrome")

        var noShadow = SnapshotConfig()
        noShadow.code = Self.swiftSample
        noShadow.showShadow = false
        write(noShadow, "layout-no-shadow")

        var tight = SnapshotConfig()
        tight.code = Self.swiftSample
        tight.padding = 16
        write(tight, "layout-padding-16")

        var roomy = SnapshotConfig()
        roomy.code = Self.swiftSample
        roomy.padding = 64
        write(roomy, "layout-padding-64")

        var transparent = SnapshotConfig()
        transparent.code = Self.swiftSample
        transparent.background = .transparent
        write(transparent, "layout-transparent")
    }

    @Test func differentLanguages() {
        var python = SnapshotConfig()
        python.code = "def greet(name: str) -> str:\n    return f\"Hello, {name}!\""
        python.language = .python
        python.theme = .dracula
        write(python, "lang-python")

        var typescript = SnapshotConfig()
        typescript.code = "const add = (a: number, b: number): number => a + b;"
        typescript.language = .typescript
        typescript.background = .gradient(.night)
        write(typescript, "lang-typescript")

        var go = SnapshotConfig()
        go.code = "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"hi\")\n}"
        go.language = .go
        go.theme = .nightOwl
        write(go, "lang-go")

        var sql = SnapshotConfig()
        sql.code = "SELECT id, name\nFROM users\nWHERE active = true\nORDER BY name;"
        sql.language = .sql
        sql.background = .gradient(.forest)
        write(sql, "lang-sql")
    }

    @Test func clipboardRoundTrip() throws {
        var config = SnapshotConfig()
        config.code = Self.swiftSample
        #expect(ExportManager.copyToPasteboard(config, scale: 2))

        let pasteboard = NSPasteboard.general
        let data = try #require(pasteboard.data(forType: .png), "no PNG on the pasteboard")
        // PNG magic number proves it is a valid image on the clipboard.
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])

        let url = Self.outDir.appendingPathComponent("_clipboard-readback.png")
        try data.write(to: url)
        print("CLIPBOARD \(data.count) bytes \(url.path)")
    }

    @Test func fontVariations() {
        let fonts = [
            "JetBrains Mono", "Fira Code", "IBM Plex Mono", "Hack", "Geist Mono", "Space Mono",
        ]
        for font in fonts {
            var config = SnapshotConfig()
            config.code = Self.swiftSample
            config.fontName = font
            let safe = font.lowercased().replacingOccurrences(of: " ", with: "-")
            #expect(write(config, "font-\(safe)"))
        }
    }
}
