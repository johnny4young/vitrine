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

    /// A light terminal palette (GitHub family) for light syntax themes, so terminal
    /// output reads on a light card — the right look for light blogs, docs, and slides.
    static let terminalLight = ANSIPalette(
        base: [
            rgb(0x24, 0x29, 0x2E), rgb(0xCF, 0x22, 0x2E), rgb(0x11, 0x63, 0x29),
            rgb(0x4D, 0x2D, 0x00), rgb(0x09, 0x69, 0xDA), rgb(0x82, 0x50, 0xDF),
            rgb(0x1B, 0x7C, 0x83), rgb(0x6E, 0x77, 0x81),
            rgb(0x57, 0x60, 0x6A), rgb(0xA4, 0x0E, 0x26), rgb(0x1A, 0x7F, 0x37),
            rgb(0x63, 0x3C, 0x01), rgb(0x21, 0x8B, 0xFF), rgb(0xA4, 0x75, 0xF9),
            rgb(0x31, 0x92, 0xAA), rgb(0x24, 0x29, 0x2E),
        ],
        defaultForeground: rgb(0x24, 0x29, 0x2E),
        defaultBackground: rgb(0xFF, 0xFF, 0xFF))

    /// Dracula's official ANSI palette.
    static let dracula = ANSIPalette(
        base: [
            rgb(0x21, 0x22, 0x2C), rgb(0xFF, 0x55, 0x55), rgb(0x50, 0xFA, 0x7B),
            rgb(0xF1, 0xFA, 0x8C), rgb(0xBD, 0x93, 0xF9), rgb(0xFF, 0x79, 0xC6),
            rgb(0x8B, 0xE9, 0xFD), rgb(0xF8, 0xF8, 0xF2),
            rgb(0x62, 0x72, 0xA4), rgb(0xFF, 0x6E, 0x6E), rgb(0x69, 0xFF, 0x94),
            rgb(0xFF, 0xFF, 0xA5), rgb(0xD6, 0xAC, 0xFF), rgb(0xFF, 0x92, 0xDF),
            rgb(0xA4, 0xFF, 0xFF), rgb(0xFF, 0xFF, 0xFF),
        ],
        defaultForeground: rgb(0xF8, 0xF8, 0xF2),
        defaultBackground: rgb(0x28, 0x2A, 0x36))

    /// Nord's official ANSI palette.
    static let nord = ANSIPalette(
        base: [
            rgb(0x3B, 0x42, 0x52), rgb(0xBF, 0x61, 0x6A), rgb(0xA3, 0xBE, 0x8C),
            rgb(0xEB, 0xCB, 0x8B), rgb(0x81, 0xA1, 0xC1), rgb(0xB4, 0x8E, 0xAD),
            rgb(0x88, 0xC0, 0xD0), rgb(0xE5, 0xE9, 0xF0),
            rgb(0x4C, 0x56, 0x6A), rgb(0xBF, 0x61, 0x6A), rgb(0xA3, 0xBE, 0x8C),
            rgb(0xEB, 0xCB, 0x8B), rgb(0x81, 0xA1, 0xC1), rgb(0xB4, 0x8E, 0xAD),
            rgb(0x8F, 0xBC, 0xBB), rgb(0xEC, 0xEF, 0xF4),
        ],
        defaultForeground: rgb(0xD8, 0xDE, 0xE9),
        defaultBackground: rgb(0x2E, 0x34, 0x40))

    /// The terminal palette to use for a syntax theme: a signature palette for the
    /// themes that have one, otherwise a light or dark default matching the theme's
    /// appearance — so the Style theme picker also drives the terminal look (and a
    /// light theme yields a light terminal, for light contexts).
    static func forTheme(_ theme: Theme) -> ANSIPalette {
        switch theme.id {
        case "dracula": .dracula
        case "nord": .nord
        default: theme.appearance == .light ? .terminalLight : .terminal
        }
    }

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

    /// The visible text of terminal output with every escape sequence removed and line
    /// redraws/backspaces resolved — the plain text a reader would copy, matching what
    /// the rendered image shows. Used for the copyable-text sidecar so the shared image
    /// ships with selectable, accessible output rather than only pixels.
    static func plainText(_ text: String) -> String {
        ANSIParser.parse(normalize(text)).map(\.text).joined()
    }

    /// Cleans control bytes a pseudo-terminal capture leaves behind so the static
    /// image shows clean lines. A terminal turns `\\n` into `\\r\\n` on output, a lone
    /// `\\r` redraws the current line (progress bars/spinners), and `\\b` backs up one
    /// visible character. `script` can also leave stray bytes like `^D` (EOT) or BEL.
    /// Keep tab, newline, and ESC — the parser itself consumes ESC as SGR/other
    /// sequences — while dropping the remaining C0 controls.
    static func normalize(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var output: [Unicode.Scalar] = []
        output.reserveCapacity(scalars.count)
        var lineStart = 0
        var changed = false
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            switch scalar {
            case "\r":
                changed = true
                if index + 1 < scalars.count, scalars[index + 1] == "\n" {
                    output.append("\n")
                    lineStart = output.count
                    index += 2
                } else {
                    output.removeSubrange(lineStart..<output.count)
                    index += 1
                }
            case "\n":
                output.append(scalar)
                lineStart = output.count
                index += 1
            case "\u{08}":
                changed = true
                if output.count > lineStart { output.removeLast() }
                index += 1
            case "\u{1B}":
                // Preserve an OSC sequence intact so the stray-control stripping below
                // never eats its BEL/ST terminator — without this, an OSC 8 hyperlink
                // (and the rest of its line) is swallowed as an unterminated OSC, since
                // BEL is otherwise dropped as a `^G`. CSI needs no special case: its
                // bytes are all ≥ 0x20 and already pass through.
                output.append(scalar)  // ESC
                index += 1
                guard index < scalars.count, scalars[index] == "]" else { break }
                output.append(scalars[index])  // ]
                index += 1
                while index < scalars.count {
                    let byte = scalars[index]
                    output.append(byte)
                    index += 1
                    if byte == "\u{07}" { break }  // BEL terminator
                    if byte == "\u{1B}", index < scalars.count, scalars[index] == "\\" {
                        output.append(scalars[index])  // ST terminator's trailing `\`
                        index += 1
                        break
                    }
                }
            default:
                if scalar.value < 0x20, scalar != "\t" {
                    changed = true
                } else {
                    output.append(scalar)
                }
                index += 1
            }
        }

        guard changed else { return text }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: output)
        return String(view)
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
        if style.strikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        // OSC 8 hyperlink: underline it and tint default-colored link text the palette's
        // blue so it reads as a link in the static image (a program that already colored
        // the link keeps its color). Deliberately *not* the `.link` attribute: SwiftUI's
        // `Text` drops a linked run (and the rest of its line) when the canvas is
        // rasterized through `ImageRenderer`, so the URL is styled here, never attached —
        // which also matches the terminal, where the URL itself stays hidden.
        if style.hyperlink != nil {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            if style.foreground == .default, !style.inverse {
                attributes[.foregroundColor] = palette.base[4]
            }
        }
        return attributes
    }

    /// Derives the bold / italic variant of the monospaced base font, keeping its
    /// size (falling back to the base font when a trait is unavailable), then appends
    /// the Nerd Font glyph cascade so Powerline / devicon / `eza` icons render when a
    /// Nerd Font is installed. The cascade is applied to every run — plain ones too,
    /// not just bold/italic — and is a no-op when no Nerd Font is present.
    private static func styledFont(_ font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        let base = traits.isEmpty ? font : NSFontManager.shared.convert(font, toHaveTrait: traits)
        return CodeFont.applyingNerdCascade(to: base)
    }
}
