import AppKit
import VitrineDomain

/// Resolves the symbolic colors named by `ANSIParser` into concrete `NSColor`s: the
/// 16 base colors, the 256-color cube + grayscale ramp, and 24-bit truecolor. One
/// shared default palette (`.terminal`) gives pasted terminal output a clean,
/// readable look on Vitrine's terminal background; `default` foreground/background
/// fall back to the palette's own pair.
public struct ANSIPalette {
    public init(
        base: [NSColor], defaultForeground: NSColor, defaultBackground: NSColor
    ) {
        self.base = base
        self.defaultForeground = defaultForeground
        self.defaultBackground = defaultBackground
    }

    /// The 16 base colors, indexed 0–7 (standard) then 8–15 (bright).
    public let base: [NSColor]
    /// The color for `ANSIColor.default` foreground (plain text).
    public let defaultForeground: NSColor
    /// The terminal background, used as the canvas fill and as the default
    /// background for inverse text.
    public let defaultBackground: NSColor

    /// Resolves an `ANSIColor`, using `fallback` for `.default` (the caller passes
    /// the default foreground or background depending on the role).
    public func color(_ ansi: ANSIColor, fallback: NSColor) -> NSColor {
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
    public func indexedColor(_ index: Int) -> NSColor {
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
    public static let terminal = ANSIPalette(
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
    public static let terminalLight = ANSIPalette(
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
    public static let dracula = ANSIPalette(
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
    public static let nord = ANSIPalette(
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
    public static func forTheme(_ theme: Theme) -> ANSIPalette {
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
public enum ANSIRenderer {
    /// Parses `text` and lays it out in `font` with `palette`. A run's default
    /// background is left unset so the canvas's terminal fill shows through; an
    /// explicit or inverse background is painted per run.
    public static func attributedString(
        _ text: String, font: NSFont, palette: ANSIPalette = .terminal, columns: Int? = nil,
        redacting rows: [ClosedRange<Int>] = []
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in exportRuns(text, columns: columns, redacting: rows) {
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
    public static func plainText(
        _ text: String, columns: Int? = nil, redacting rows: [ClosedRange<Int>] = []
    ) -> String {
        exportRuns(text, columns: columns, redacting: rows).map(\.text).joined()
    }

    /// Redactions address the final screen, never physical lines in the ANSI transcript.
    /// Text and attributed exports share this transform so styles and row numbers cannot
    /// diverge. A replacement gets a fresh style, not attributes from hidden content.
    private static func exportRuns(
        _ text: String, columns: Int?, redacting rows: [ClosedRange<Int>]
    ) -> [ANSIRun] {
        let runs = styledRuns(text, columns: columns)
        let redactions = LineHighlight.normalize(rows)
        guard !redactions.isEmpty else { return runs }
        var result: [ANSIRun] = []
        var row = 1
        var replacedRow = false
        for run in runs.isEmpty ? [ANSIRun(text: "", style: ANSIStyle())] : runs {
            for (index, fragment) in run.text.components(separatedBy: "\n").enumerated() {
                if index > 0 {
                    result.append(ANSIRun(text: "\n", style: ANSIStyle()))
                    row += 1
                    replacedRow = false
                }
                if LineHighlight.contains(redactions, line: row) {
                    if !replacedRow {
                        result.append(
                            ANSIRun(
                                text: SnapshotConfig.redactedLinePlaceholder, style: ANSIStyle()))
                        replacedRow = true
                    }
                } else if !fragment.isEmpty {
                    result.append(ANSIRun(text: fragment, style: run.style))
                }
            }
        }
        return result
    }

    /// The styled runs for terminal `text`, choosing the renderer by content: when the
    /// stream addresses the screen with cursor positioning (a full-screen TUI like
    /// `htop`/`vim`), the cell-buffer emulator (``TerminalScreen``) reconstructs the
    /// final frame; otherwise the line-oriented parse of the normalized text. Both yield
    /// `[ANSIRun]`, so a grid capture and a scrolling capture render identically.
    ///
    /// Grid mode skips ``normalize(_:)`` on purpose: that collapses the `\r`/`\b` redraws
    /// the emulator interprets itself as cursor motion, and keeps the cursor escapes it
    /// needs intact.
    private static func styledRuns(_ text: String, columns: Int? = nil) -> [ANSIRun] {
        if TerminalScreen.usesScreenAddressing(text) {
            // `columns` pins the reconstruction width (`--terminal-width`); `nil` lets the
            // emulator infer it. Line mode reflows to the image, so the width is moot there.
            return TerminalScreen.runs(text, columns: columns)
        }
        return ANSIParser.parse(normalize(text))
    }

    /// What a redraw escape does to the lines ``normalize(_:)`` has emitted. The line
    /// renderer tracks lines, not a cursor column, so only whole-line edits are
    /// expressible — and they are the only ones the progress-bar and clear idioms need.
    private enum LineEdit {
        /// Erase the current line. `EL 1` erases start-to-cursor and `EL 2` the whole
        /// line; with no column model both discard the line.
        case eraseLine
        /// `EL 0` erases from the cursor forward. It only matters when the cursor went
        /// back to the line start; otherwise it sits at the end of the emitted text.
        case eraseForward
        /// Return to the line start (`CHA` to column 1, like `\r`).
        case returnToLineStart
        /// Move to the line `n` rows up (`CUU`/`CPL`) or down (`CUD`/`CNL`).
        case moveLines(Int)
        /// Discard everything emitted so far — the `clear && <command>` idiom. A lone
        /// display erase no longer routes the stream to the grid (see
        /// `TerminalScreen.usesScreenAddressing`), so the reset it implies is applied
        /// here: what follows the clear is what the user saw.
        case clearTranscript
    }

    /// Maps a CSI to its effect on the emitted lines, or `nil` to leave the sequence for
    /// the parser.
    ///
    /// `CHA` to any column other than 1 is left alone: without a real cursor the honest
    /// options are to pad or to truncate, and truncating would delete text a program had
    /// aligned rather than merely fail to align it.
    private static func lineEdit(finalByte: Unicode.Scalar, params: String) -> LineEdit? {
        switch finalByte {
        case "K":  // EL — erase in line
            switch params {
            case "1", "2": return .eraseLine
            case "", "0": return .eraseForward
            default: return nil
            }
        case "G":  // CHA — cursor to an absolute column (empty parameter means column 1)
            return params.isEmpty || params == "1" ? .returnToLineStart : nil
        case "A", "F", "B", "E":  // CUU / CPL up, CUD / CNL down
            guard params.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) else {
                return nil
            }
            let count = max(1, min(Int(params) ?? 1, 100_000))
            return .moveLines(finalByte == "A" || finalByte == "F" ? -count : count)
        case "J":  // ED — erase display
            // Only `2` (erase the whole screen) discards the transcript. `3` erases
            // *saved scrollback*, not the visible screen — a standalone `CSI 3 J` must
            // not delete text emitted before it, and the Linux `clear` it usually
            // follows already carries the `2` that does the reset. `0`/`1` erase
            // forward/backward of a cursor this model does not track; with everything
            // emitted sitting "above" the cursor, `0` is a no-op and `1` is left to the
            // parser like any other decoration.
            return params == "2" ? .clearTranscript : nil
        default:
            return nil
        }
    }

    /// One line of ``normalize(_:)`` output. Escape sequences ride between the visible
    /// scalars, and an erase keeps the ones that carry pen state (SGR, OSC), so text
    /// drawn after a redraw keeps the color a terminal would show.
    private struct NormalizedLine {
        enum Piece {
            case text(Unicode.Scalar)
            case escape([Unicode.Scalar], keepsState: Bool)
        }

        /// State-carrying escapes from erased content, always before `live`.
        private(set) var kept: [[Unicode.Scalar]] = []
        private(set) var live: [Piece] = []

        mutating func append(_ piece: Piece) { live.append(piece) }

        mutating func erase() {
            for case .escape(let bytes, true) in live { kept.append(bytes) }
            live.removeAll(keepingCapacity: true)
        }

        /// Deletes the last visible scalar, never an escape sequence's bytes.
        mutating func deleteLastVisible() {
            guard
                let index = live.lastIndex(where: {
                    if case .text = $0 { return true }
                    return false
                })
            else { return }
            live.remove(at: index)
        }

        var stateEscapes: [[Unicode.Scalar]] {
            var result = kept
            for case .escape(let bytes, true) in live { result.append(bytes) }
            return result
        }

        func write(to output: inout String.UnicodeScalarView) {
            for bytes in kept { output.append(contentsOf: bytes) }
            for piece in live {
                switch piece {
                case .text(let scalar): output.append(scalar)
                case .escape(let bytes, _): output.append(contentsOf: bytes)
                }
            }
        }
    }

    /// Cleans control bytes a pseudo-terminal capture leaves behind so the static
    /// image shows clean lines. A terminal turns `\\n` into `\\r\\n` on output, a lone
    /// `\\r` redraws the current line (progress bars/spinners), `\\b` backs up one
    /// visible character, and cursor-up/down redraws a multi-line block in place.
    /// `script` can also leave stray bytes like `^D` (EOT) or BEL. Keep tab, newline,
    /// and ESC — the parser itself consumes ESC as SGR/other sequences — while dropping
    /// the remaining C0 controls.
    ///
    /// A return to the line start (`\\r`, `CHA 1`, or a cursor move onto another line)
    /// erases that line only once something is drawn or erased there, so `\\r\\r\\n`
    /// and a bare trailing `\\r` keep the line, as a terminal does.
    public static func normalize(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var lines = [NormalizedLine()]
        var current = 0
        var atLineStart = false
        var changed = false
        var index = 0

        func draw(_ piece: NormalizedLine.Piece) {
            if atLineStart {
                lines[current].erase()
                atLineStart = false
            }
            lines[current].append(piece)
        }
        func appendEscape(_ bytes: ArraySlice<Unicode.Scalar>, keepsState: Bool = false) {
            lines[current].append(.escape(Array(bytes), keepsState: keepsState))
        }

        while index < scalars.count {
            let scalar = scalars[index]
            switch scalar {
            case "\r":
                changed = true
                atLineStart = true
                index += 1
            case "\n":
                current += 1
                if current == lines.count {
                    lines.append(NormalizedLine())
                    atLineStart = false
                } else {
                    atLineStart = true  // back on a line a cursor-up revisited
                }
                index += 1
            case "\u{08}":
                changed = true
                if !atLineStart { lines[current].deleteLastVisible() }
                index += 1
            case "\u{1B}":
                guard index + 1 < scalars.count else {
                    appendEscape(scalars[index...])
                    index += 1
                    break
                }
                let next = scalars[index + 1]
                if next == "[" {
                    // A progress bar redraws its line with `EL`/`CHA` at least as often
                    // as with `\r` (npm, ora, and anything built on gauge emit
                    // `ESC[2K ESC[1G`), and multi-line renderers (log-update, listr2,
                    // buildkit) step back up with `CUU`. Left to the parser they are
                    // stripped as decoration, which keeps every recorded frame.
                    let (params, finalByte, end) = ANSIParser.scanCSI(scalars, from: index + 2)
                    if let finalByte, let edit = Self.lineEdit(finalByte: finalByte, params: params)
                    {
                        switch edit {
                        case .eraseLine:
                            changed = true
                            lines[current].erase()
                            atLineStart = false
                        case .eraseForward:
                            guard atLineStart else {
                                appendEscape(scalars[index..<end])  // nothing to erase
                                index = end
                                continue
                            }
                            changed = true
                            lines[current].erase()
                            atLineStart = false
                        case .returnToLineStart:
                            changed = true
                            atLineStart = true
                        case .moveLines(let delta):
                            changed = true
                            current = min(max(0, current + delta), lines.count - 1)
                            atLineStart = true
                        case .clearTranscript:
                            changed = true
                            var reset = NormalizedLine()
                            for line in lines {
                                for bytes in line.stateEscapes {
                                    reset.append(.escape(bytes, keepsState: true))
                                }
                            }
                            lines = [reset]
                            current = 0
                            atLineStart = false
                        }
                        index = end
                        continue
                    }
                    // Every other CSI (SGR above all) stays for the parser.
                    appendEscape(scalars[index..<end], keepsState: finalByte == "m")
                    index = end
                    continue
                }
                if next == "]" || ANSIParser.isStringSequenceIntroducer(next) {
                    // Copy an OSC or DCS/SOS/PM/APC intact so the stray-control stripping
                    // never eats its BEL/ST terminator. BEL ends an OSC (the xterm
                    // extension OSC 8 relies on) but is payload inside a string sequence.
                    let belTerminates = next == "]"
                    var cursor = index + 2
                    var terminated = false
                    while cursor < scalars.count {
                        let byte = scalars[cursor]
                        cursor += 1
                        if belTerminates, byte == "\u{07}" {
                            terminated = true
                            break
                        }
                        if byte == "\u{1B}", cursor < scalars.count, scalars[cursor] == "\\" {
                            cursor += 1
                            terminated = true
                            break
                        }
                    }
                    appendEscape(scalars[index..<cursor], keepsState: belTerminates && terminated)
                    index = cursor
                    continue
                }
                // Charset designation (`ESC (B`) and other two-byte escapes form one
                // piece so an erase never splits them. A control byte after ESC is left
                // for the loop, as the parser drops the pair either way.
                var end = index + 1
                if (0x20...0x2F).contains(next.value) {
                    while end < scalars.count, (0x20...0x2F).contains(scalars[end].value) {
                        end += 1
                    }
                    end = min(end + 1, scalars.count)
                } else if next.value >= 0x20 {
                    end += 1
                }
                appendEscape(scalars[index..<end])
                index = end
            default:
                if scalar.value < 0x20, scalar != "\t" {
                    changed = true
                } else {
                    draw(.text(scalar))
                }
                index += 1
            }
        }

        guard changed else { return text }
        var view = String.UnicodeScalarView()
        for (number, line) in lines.enumerated() {
            if number > 0 { view.append("\n") }
            line.write(to: &view)
        }
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

    /// The key into the styled-font memo: the base font (identity + size) and the two
    /// traits that select one of its four variants.
    private struct StyledFontKey: Hashable {
        let font: NSFont
        let bold: Bool
        let italic: Bool
    }

    /// Memoizes styled variants per base font. A colorful terminal frame
    /// (`htop`, `eza`) is hundreds to thousands of styled runs, and each one used to
    /// rebuild its variant through `NSFontManager.convert` plus the Nerd-Font cascade
    /// descriptor — hundreds of font-descriptor allocations per render. There are only
    /// four variants (plain / bold / italic / bold-italic) per base font, so this
    /// collapses repeated work while a bounded FIFO prevents font changes across a long
    /// editing session from retaining every variant forever.
    private static let styledFontCacheLimit = 128
    private static var styledFontCache: [StyledFontKey: NSFont] = [:]
    private static var styledFontOrder: [StyledFontKey] = []

    /// Derives the bold / italic variant of the monospaced base font, keeping its
    /// size (falling back to the base font when a trait is unavailable), then appends
    /// the Nerd Font glyph cascade so Powerline / devicon / `eza` icons render when a
    /// Nerd Font is installed. The cascade is applied to every run — plain ones too,
    /// not just bold/italic — and is a no-op when no Nerd Font is present.
    ///
    /// Memoized per (base font, bold, italic): the same styled variant is reused
    /// across every run that shares those traits instead of re-resolving the font.
    private static func styledFont(_ font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        let key = StyledFontKey(font: font, bold: bold, italic: italic)
        if let cached = styledFontCache[key] { return cached }
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        let base = traits.isEmpty ? font : NSFontManager.shared.convert(font, toHaveTrait: traits)
        let styled = CodeFont.applyingNerdCascade(to: base)
        if styledFontCache[key] == nil {
            styledFontOrder.append(key)
            if styledFontOrder.count > styledFontCacheLimit {
                styledFontCache.removeValue(forKey: styledFontOrder.removeFirst())
            }
        }
        styledFontCache[key] = styled
        return styled
    }
}
