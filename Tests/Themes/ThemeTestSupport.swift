import Foundation

@testable import Vitrine

enum ThemeTestFixtures {
    /// An isolated defaults suite so a store test never touches the real app container
    /// or another test's state, mirroring the preset test fixtures.
    static func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "VitrineThemeTests-\(UUID().uuidString)")!
    }

    /// A complete, legible dark palette used as the canonical sample custom theme.
    static func samplePalette() -> ThemePalette {
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
    static func sampleThemeFileData(name: String = "Midnight Sample") throws -> Data {
        let theme = Theme(id: "custom.sample", displayName: name, palette: samplePalette())
        return try CustomThemeDocument(themes: [theme]).jsonData()
    }

    /// A short Swift snippet that tokenizes into several scope colors under any real
    /// theme (a keyword, a string, a number, and a comment).
    static let sampleCode =
        "let count = 42 // total\nfunc greet(_ name: String) { print(\"Hi \\(name)\") }"
}
