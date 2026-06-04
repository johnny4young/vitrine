import Foundation

/// Monospaced fonts offered for the code (CS-006). Bundled families are registered
/// at launch via `ATSApplicationFontsPath` (see Info.plist + Resources/Fonts);
/// system families always exist. Stored as the family name used by `NSFont(name:)`.
enum CodeFont {
    /// Fonts bundled with the app.
    static let bundled: [String] = [
        "JetBrains Mono", "Fira Code", "Hack", "IBM Plex Mono",
        "Roboto Mono", "Space Mono", "Ubuntu Mono", "Geist Mono",
    ]

    /// System monospaced fonts that ship with macOS.
    static let system: [String] = ["SF Mono", "Menlo", "Monaco"]

    /// All selectable fonts, bundled first.
    static let all: [String] = bundled + system

    static let `default` = "JetBrains Mono"
}
