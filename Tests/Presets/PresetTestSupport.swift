import Foundation

@testable import Vitrine

/// Fixtures shared by the reusable-style preset suites.
enum PresetTestFixtures {
    static func freshDefaults() -> UserDefaults {
        testDefaults()
    }

    /// A style snapshot exercising several presentation fields.
    static func sampleStyle() -> StyleSnapshot {
        StyleSnapshot(
            themeID: Theme.dracula.id,
            fontName: "Fira Code",
            fontSize: 16,
            fontLigatures: true,
            padding: 48,
            cornerRadius: 20,
            showChrome: false,
            showShadow: false,
            showLineNumbers: true,
            background: .gradient(.sunset))
    }
}
