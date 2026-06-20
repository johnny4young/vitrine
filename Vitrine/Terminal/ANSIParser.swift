import Foundation

/// A color named by an ANSI SGR sequence, resolved to a concrete color later by
/// `ANSIPalette`. Keeping the name (not the color) here lets the parser stay a
/// pure, AppKit-free value transform that is fully unit-testable.
enum ANSIColor: Equatable {
    /// The terminal's default foreground or background.
    case `default`
    /// A palette index: 0–7 standard, 8–15 bright, 16–231 the 6×6×6 cube,
    /// 232–255 the grayscale ramp.
    case indexed(Int)
    /// A 24-bit truecolor (`38;2;r;g;b` / `48;2;r;g;b`).
    case rgb(UInt8, UInt8, UInt8)
}

/// The visual style carried by a run of terminal text, accumulated from SGR codes.
struct ANSIStyle: Equatable {
    var foreground: ANSIColor = .default
    var background: ANSIColor = .default
    var bold = false
    var dim = false
    var italic = false
    var underline = false
    var strikethrough = false
    /// Swap foreground and background (SGR 7); applied by `ANSIPalette` at render time.
    var inverse = false
}

/// A maximal run of text that shares one style.
struct ANSIRun: Equatable {
    var text: String
    var style: ANSIStyle
}

/// Parses terminal output containing ANSI escape sequences into styled text runs.
///
/// Pure and AppKit-free: it resolves *which* style applies to each run from the SGR
/// (Select Graphic Rendition) codes, but not the concrete colors — `ANSIPalette`
/// maps `ANSIColor` to real colors at render time. Non-SGR control sequences (cursor
/// moves, screen clears, OSC window titles) are stripped so pasted output renders as
/// plain styled text, and malformed or truncated escapes are dropped without
/// corrupting the surrounding characters.
enum ANSIParser {
    /// Whether `text` carries an ESC control byte — the cheap signal that it is
    /// terminal output (ANSI) rather than plain source code.
    static func containsANSI(_ text: String) -> Bool {
        text.unicodeScalars.contains("\u{1B}")
    }

    /// Splits `text` into styled runs, applying SGR codes and stripping every other
    /// escape sequence. The runs concatenated back together equal the input with all
    /// escape sequences removed.
    static func parse(_ text: String) -> [ANSIRun] {
        let scalars = Array(text.unicodeScalars)
        var runs: [ANSIRun] = []
        var style = ANSIStyle()
        var current = String.UnicodeScalarView()
        var index = 0

        func flush() {
            guard !current.isEmpty else { return }
            runs.append(ANSIRun(text: String(current), style: style))
            current = String.UnicodeScalarView()
        }

        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == "\u{1B}" else {
                current.append(scalar)
                index += 1
                continue
            }
            // An escape: classify the sequence and consume it.
            guard index + 1 < scalars.count else { break }  // lone trailing ESC → drop
            let next = scalars[index + 1]
            switch next {
            case "[":  // CSI — control sequence (SGR is the only one with a text effect)
                let (params, finalByte, end) = Self.scanCSI(scalars, from: index + 2)
                if finalByte == "m" {
                    flush()
                    style = Self.applySGR(params, to: style)
                }
                index = end
            case "]":  // OSC — strip up to BEL or ST (`ESC \`)
                index = Self.skipOSC(scalars, from: index + 2)
            default:  // a two-byte escape (`ESC <byte>`) or unknown — drop both bytes
                index += 2
            }
        }
        flush()
        return runs
    }

    // MARK: - Sequence scanning

    /// Scans a CSI body starting at `start` (just past `ESC[`): parameter/intermediate
    /// bytes (0x20–0x3F) up to the final byte (0x40–0x7E). Returns the parameter
    /// string, the final byte (or `nil` if the input ran out), and the index just
    /// past the sequence.
    private static func scanCSI(
        _ scalars: [Unicode.Scalar], from start: Int
    )
        -> (params: String, finalByte: Unicode.Scalar?, end: Int)
    {
        var params = String.UnicodeScalarView()
        var cursor = start
        while cursor < scalars.count {
            let value = scalars[cursor].value
            if value >= 0x40 && value <= 0x7E {  // final byte
                return (String(params), scalars[cursor], cursor + 1)
            }
            params.append(scalars[cursor])
            cursor += 1
        }
        return (String(params), nil, cursor)  // truncated — consume to end
    }

    /// Skips an OSC sequence's body, terminated by BEL (`\u{7}`) or ST (`ESC \`).
    /// Returns the index just past the terminator (or end of input).
    private static func skipOSC(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
        var cursor = start
        while cursor < scalars.count {
            if scalars[cursor] == "\u{07}" { return cursor + 1 }
            if scalars[cursor] == "\u{1B}", cursor + 1 < scalars.count, scalars[cursor + 1] == "\\"
            {
                return cursor + 2
            }
            cursor += 1
        }
        return cursor
    }

    // MARK: - SGR application

    /// Applies one SGR sequence's parameters to `style`. An empty parameter string is
    /// `ESC[m`, equivalent to `ESC[0m` (full reset).
    static func applySGR(_ params: String, to style: ANSIStyle) -> ANSIStyle {
        var style = style
        let codes =
            params.isEmpty
            ? [0]
            : params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0: style = ANSIStyle()
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 9: style.strikethrough = true
            case 22:
                style.bold = false
                style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 29: style.strikethrough = false
            case 30...37: style.foreground = .indexed(code - 30)
            case 39: style.foreground = .default
            case 40...47: style.background = .indexed(code - 40)
            case 49: style.background = .default
            case 90...97: style.foreground = .indexed(code - 90 + 8)
            case 100...107: style.background = .indexed(code - 100 + 8)
            case 38, 48:
                // Extended color: `38;5;n` (indexed) or `38;2;r;g;b` (truecolor); 48 = bg.
                let setForeground = code == 38
                guard index + 1 < codes.count else {
                    index += 1
                    continue
                }
                let mode = codes[index + 1]
                if mode == 5, index + 2 < codes.count {
                    let resolved = ANSIColor.indexed(max(0, min(255, codes[index + 2])))
                    if setForeground {
                        style.foreground = resolved
                    } else {
                        style.background = resolved
                    }
                    index += 2
                } else if mode == 2, index + 4 < codes.count {
                    let resolved = ANSIColor.rgb(
                        UInt8(clamping: codes[index + 2]),
                        UInt8(clamping: codes[index + 3]),
                        UInt8(clamping: codes[index + 4]))
                    if setForeground {
                        style.foreground = resolved
                    } else {
                        style.background = resolved
                    }
                    index += 4
                }
            default:
                break  // unsupported SGR (blink, conceal, framed, …) — ignored for now
            }
            index += 1
        }
        return style
    }
}
