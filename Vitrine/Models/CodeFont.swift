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

    // MARK: - Glyph metrics

    /// The horizontal advance of `character` in `font`, read straight from the font's
    /// metrics table via Core Text.
    ///
    /// Used instead of `NSString.size(withAttributes:)` deliberately: that path runs full
    /// `NSAttributedString` text layout, which on a degraded headless text subsystem (a CI
    /// runner with a broken font/render stack) raises an uncatchable Objective-C
    /// `NSException` from inside UIFoundation and aborts the *entire* test process. Reading
    /// the glyph advance only touches the font's metrics — no layout, no rasterization — so
    /// it can't trip that path. For a monospaced font this equals the cell advance, so it is
    /// a drop-in replacement for measuring a digit or space column.
    static func advance(of character: Character, in font: NSFont) -> CGFloat {
        let ctFont = font as CTFont
        var unichars = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: unichars.count)
        guard CTFontGetGlyphsForCharacters(ctFont, &unichars, &glyphs, unichars.count),
            let first = glyphs.first
        else {
            return font.maximumAdvancement.width  // unmapped character — a safe upper bound
        }
        var glyph = first
        return CGFloat(CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, nil, 1))
    }

    // MARK: - Nerd Font glyph cascade (terminal)

    /// Nerd Font families probed for the terminal glyph cascade, in preference
    /// order. The symbols-only families come first: they carry *only* the icon
    /// glyphs (Powerline separators, devicons, the `eza --icons` / `starship` set)
    /// and never override the base font's letterforms, so the rendered text keeps
    /// the chosen code font and only the missing Private-Use-Area glyphs fall back.
    ///
    /// We **bundle nothing** — the cascade rides a Nerd Font the user already
    /// installed (the norm for anyone using Powerline/`starship`/`eza`). That keeps
    /// the app free of a multi-megabyte font asset and of any redistribution /
    /// attribution obligation; a user without a Nerd Font sees the same
    /// missing-glyph boxes as before, never a worse result.
    static let nerdFontCandidates: [String] = [
        "Symbols Nerd Font Mono",
        "Symbols Nerd Font",
        "JetBrainsMono Nerd Font Mono",
        "JetBrainsMono Nerd Font",
        "Hack Nerd Font Mono",
        "Hack Nerd Font",
        "FiraCode Nerd Font Mono",
        "FiraCode Nerd Font",
        "MesloLGS Nerd Font Mono",
        "MesloLGS NF",
        "CaskaydiaCove Nerd Font Mono",
    ]

    /// The `nerdFontCandidates` actually present in `availableFamilies`, preserving
    /// preference order. Pure (the family set is injected) so the resolution is
    /// testable without depending on what fonts the host happens to have.
    static func installedNerdFonts(
        among candidates: [String] = nerdFontCandidates,
        availableFamilies: Set<String>
    ) -> [String] {
        candidates.filter { availableFamilies.contains($0) }
    }

    /// Cascade descriptors for the installed Nerd Fonts, built once from the host's
    /// font list (it does not change within a session). Empty when no Nerd Font is
    /// installed — in which case `applyingNerdCascade` is a no-op.
    private static let nerdCascadeDescriptors: [NSFontDescriptor] = {
        let families = Set(NSFontManager.shared.availableFontFamilies)
        return installedNerdFonts(availableFamilies: families).map {
            NSFontDescriptor(fontAttributes: [.family: $0])
        }
    }()

    /// Returns `font` with a Nerd Font fallback cascade appended, so glyphs the base
    /// font lacks (the Private-Use-Area icons modern prompts emit) render from an
    /// installed Nerd Font instead of as missing-glyph boxes. Used for terminal
    /// output only.
    ///
    /// When no Nerd Font is installed the font is returned **unchanged** — byte-for-
    /// byte identical rendering — so a host without one (e.g. CI) never drifts.
    static func applyingNerdCascade(to font: NSFont) -> NSFont {
        applying(cascade: nerdCascadeDescriptors, to: font)
    }

    /// Appends `cascade` to `font`'s descriptor as its fallback list. Factored out
    /// (and `cascade` injected) so the cascade wiring is testable with a known
    /// font; an empty list returns `font` untouched.
    ///
    /// Any cascade list already on the base font is **preserved** — the new
    /// descriptors are appended after it, not substituted — so a font that arrives
    /// with its own fallbacks keeps them ahead of the Nerd Font.
    static func applying(cascade descriptors: [NSFontDescriptor], to font: NSFont) -> NSFont {
        guard !descriptors.isEmpty else { return font }
        let existing = font.fontDescriptor.fontAttributes[.cascadeList] as? [NSFontDescriptor] ?? []
        let descriptor = font.fontDescriptor.addingAttributes([.cascadeList: existing + descriptors]
        )
        return NSFont(descriptor: descriptor, size: 0) ?? font
    }
}
