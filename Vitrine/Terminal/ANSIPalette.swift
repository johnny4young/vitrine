import AppKit

/// Resolves the symbolic colors named by `ANSIParser` into concrete `NSColor`s: the
/// 16 base colors, the 256-color cube + grayscale ramp, and 24-bit truecolor. One
/// shared default palette (`.terminal`) gives pasted terminal output a clean,
/// readable look on Vitrine's terminal background; `default` foreground/background
/// fall back to the palette's own pair.
struct ANSIPalette {
    /// The 16 base colors, indexed 0–7 (standard) then 8–15 (bright).
    let base: [NSColor]
    /// The color for `ANSIColor.default` foreground (plain text).
    let defaultForeground: NSColor
    /// The terminal background, used as the canvas fill and as the default
    /// background for inverse text.
    let defaultBackground: NSColor

    /// Resolves an `ANSIColor`, using `fallback` for `.default` (the caller passes
    /// the default foreground or background depending on the role).
    func color(_ ansi: ANSIColor, fallback: NSColor) -> NSColor {
        switch ansi {
        case .default: fallback
        case .indexed(let index): indexedColor(index)
        case .rgb(let r, let g, let b):
            NSColor(
                srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255,
                alpha: 1)
        }
    }

    /// Maps a 0–255 palette index: 0–15 are `base`, 16–231 the 6×6×6 color cube, and
    /// 232–255 the 24-step grayscale ramp (the standard xterm-256 layout).
    func indexedColor(_ index: Int) -> NSColor {
        let index = max(0, min(255, index))
        if index < 16 { return base[index] }
        if index < 232 {
            let value = index - 16
            let r = (value / 36) % 6
            let g = (value / 6) % 6
            let b = value % 6
            func channel(_ step: Int) -> CGFloat { step == 0 ? 0 : CGFloat(55 + step * 40) / 255 }
            return NSColor(srgbRed: channel(r), green: channel(g), blue: channel(b), alpha: 1)
        }
        let gray = CGFloat(8 + (index - 232) * 10) / 255
        return NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1)
    }

    /// The default palette — a balanced, high-legibility set (One-Dark family) on a
    /// soft-black terminal background.
    static let terminal = ANSIPalette(
        base: [
            // Standard 0–7
            rgb(0x3F, 0x44, 0x51),  // black (raised so it reads on the dark bg)
            rgb(0xE0, 0x6C, 0x75),  // red
            rgb(0x98, 0xC3, 0x79),  // green
            rgb(0xE5, 0xC0, 0x7B),  // yellow
            rgb(0x61, 0xAF, 0xEF),  // blue
            rgb(0xC6, 0x78, 0xDD),  // magenta
            rgb(0x56, 0xB6, 0xC2),  // cyan
            rgb(0xD7, 0xDA, 0xE0),  // white
            // Bright 8–15
            rgb(0x5C, 0x63, 0x70),  // bright black
            rgb(0xFF, 0x7B, 0x86),  // bright red
            rgb(0xA5, 0xD6, 0xA7),  // bright green
            rgb(0xFF, 0xD4, 0x79),  // bright yellow
            rgb(0x7C, 0xC4, 0xFF),  // bright blue
            rgb(0xD9, 0x9A, 0xE6),  // bright magenta
            rgb(0x6F, 0xD0, 0xDB),  // bright cyan
            rgb(0xFF, 0xFF, 0xFF),  // bright white
        ],
        defaultForeground: rgb(0xD7, 0xDA, 0xE0),
        defaultBackground: rgb(0x1E, 0x22, 0x27))

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

/// Builds the styled `NSAttributedString` for terminal output, the ANSI counterpart
/// of `HighlightManager.attributedString` — the canvas draws one or the other.
enum ANSIRenderer {
    /// Parses `text` and lays it out in `font` with `palette`. A run's default
    /// background is left unset so the canvas's terminal fill shows through; an
    /// explicit or inverse background is painted per run.
    static func attributedString(
        _ text: String, font: NSFont, palette: ANSIPalette = .terminal
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in ANSIParser.parse(normalize(text)) {
            result.append(
                NSAttributedString(
                    string: run.text,
                    attributes: attributes(run.style, font: font, palette: palette)))
        }
        return result
    }

    /// Cleans control bytes a pseudo-terminal capture leaves behind so the static
    /// image shows clean lines. A terminal turns `\\n` into `\\r\\n` on output and a
    /// lone `\\r` rewrites the line; `script` also leaves stray bytes like `^D` (EOT)
    /// or BEL. Drop every C0 control except tab and newline — and ESC, which the
    /// parser itself consumes as SGR/other sequences.
    static func normalize(_ text: String) -> String {
        let isStray: (Unicode.Scalar) -> Bool = {
            $0.value < 0x20 && $0 != "\t" && $0 != "\n" && $0 != "\u{1B}"
        }
        guard text.unicodeScalars.contains(where: isStray) else { return text }
        var scalars = text.unicodeScalars
        scalars.removeAll(where: isStray)
        return String(scalars)
    }

    private static func attributes(
        _ style: ANSIStyle, font: NSFont, palette: ANSIPalette
    ) -> [NSAttributedString.Key: Any] {
        var foreground = palette.color(style.foreground, fallback: palette.defaultForeground)
        var background = palette.color(style.background, fallback: palette.defaultBackground)
        let hasExplicitBackground = style.background != .default
        if style.inverse { swap(&foreground, &background) }
        if style.dim { foreground = foreground.withAlphaComponent(0.6) }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: styledFont(font, bold: style.bold, italic: style.italic),
            .foregroundColor: foreground,
        ]
        // Paint a background only when the run actually carries one (explicit or
        // inverse); plain runs let the canvas terminal fill show through.
        if hasExplicitBackground || style.inverse {
            attributes[.backgroundColor] = background
        }
        if style.underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    /// Derives the bold / italic variant of the monospaced base font, keeping its
    /// size; falls back to the base font when a trait is unavailable.
    private static func styledFont(_ font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        guard bold || italic else { return font }
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        let converted = NSFontManager.shared.convert(font, toHaveTrait: traits)
        return converted
    }
}
