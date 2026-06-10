import AppKit
import CoreText

/// Monospaced fonts offered for the code (CS-006/052). Bundled families are
/// registered at launch via `ATSApplicationFontsPath` (see Info.plist +
/// Resources/Fonts); system families always exist. Stored as the family name
/// used by `NSFont(name:)`.
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

    /// Families that ship programming ligatures (e.g. `->`, `=>`, `!=`, `>=`),
    /// for which the opt-in ligature toggle has a visible effect (CS-052).
    ///
    /// Membership is keyed off the family name regardless of whether the family is
    /// currently installed: Cascadia Code is a well-known ligature font a user may
    /// have added, while Fira Code and JetBrains Mono are bundled. Names are
    /// matched case-insensitively so "Fira Code" and "FiraCode" both qualify.
    static let ligatureCapable: Set<String> = ["Fira Code", "JetBrains Mono", "Cascadia Code"]

    /// Whether `family` is a known ligature-capable programming font.
    static func hasLigatures(_ family: String) -> Bool {
        let normalized = family.replacingOccurrences(of: " ", with: "").lowercased()
        return ligatureCapable.contains {
            $0.replacingOccurrences(of: " ", with: "").lowercased() == normalized
        }
    }

    /// Resolves the code font for `family` at `size`, enabling or disabling
    /// programming ligatures (CS-052).
    ///
    /// Ligatures are controlled through the font descriptor's `kLigaturesType`
    /// feature so the choice rides on the font itself and is honored everywhere the
    /// font is drawn — the live editor and the exported canvas alike. When
    /// `ligatures` is false (the default), common ligatures are explicitly turned
    /// **off** so a ligature font renders discrete glyphs; when true, they are
    /// turned on. Non-ligature fonts are unaffected either way. Falls back to the
    /// system monospaced font when `family` is unavailable. OpenType feature
    /// overrides are applied only to known ligature-capable programming fonts; plain
    /// monospaced fonts such as Menlo stay byte-for-byte stable whether the setting is
    /// on or off.
    static func resolved(family: String, size: CGFloat, ligatures: Bool) -> NSFont {
        let requested = NSFont(name: family, size: size)
        let base = requested ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        let resolvedFamily = requested?.familyName ?? family
        guard hasLigatures(resolvedFamily) else { return base }
        return applyingLigatures(ligatures, to: base)
    }

    /// Returns `font` with programming ligatures forced on or off via the
    /// OpenType `liga` (standard ligatures) and `calt` (contextual alternates)
    /// feature tags. The base advance widths are untouched — a monospace ligature
    /// font keeps each ligature the width of the glyphs it replaces — so toggling
    /// is purely a glyph-level swap that never reflows the code (CS-052).
    ///
    /// OpenType feature *tags* are used deliberately over the legacy AAT
    /// `kLigaturesType` selectors: fonts like Fira Code drive their ligatures
    /// through `calt`, which the AAT ligature selectors do not control, so only the
    /// tag-based toggle actually changes the rendered glyphs. A non-ligature font
    /// has no `liga`/`calt` substitutions, so the setting is a harmless no-op there.
    static func applyingLigatures(_ enabled: Bool, to font: NSFont) -> NSFont {
        let value = enabled ? 1 : 0
        let settings: [[NSFontDescriptor.FeatureKey: Any]] = [
            featureSetting(tag: "liga", value: value),
            featureSetting(tag: "calt", value: value),
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: settings])
        // `NSFont(descriptor:size:)` keeps the descriptor's size; pass 0 to honor it.
        return NSFont(descriptor: descriptor, size: 0) ?? font
    }

    /// One OpenType feature override (`tag` → `value`) in the shape
    /// `NSFontDescriptor` expects.
    private static func featureSetting(
        tag: String, value: Int
    )
        -> [NSFontDescriptor.FeatureKey: Any]
    {
        [
            .init(rawValue: kCTFontOpenTypeFeatureTag as String): tag,
            .init(rawValue: kCTFontOpenTypeFeatureValue as String): value,
        ]
    }
}
