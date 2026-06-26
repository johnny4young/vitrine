import Foundation

/// The number of terminal columns a Unicode scalar occupies when drawn in a monospaced
/// cell: `0` for a combining / zero-width mark (it rides the preceding cell), `2` for an
/// East Asian wide / fullwidth character or an emoji, and `1` otherwise.
///
/// Swift's stdlib surfaces combining-mark and emoji properties but **not** the Unicode
/// East Asian Width property, so the wide set is a compact, sorted, hardcoded table — the
/// long-standing `wcwidth` ranges (Markus Kuhn). This drives the grid emulator's cursor
/// advance (``TerminalScreen``) so a CJK / emoji TUI reconstructs without column drift; it
/// is not exhaustive to the latest Unicode revision, just the common scripts and symbols.
enum CharacterWidth {
    /// The display width of `scalar` in columns: 0, 1, or 2. Control bytes are filtered by
    /// the emulator before drawing, so they don't reach here.
    static func displayWidth(_ scalar: Unicode.Scalar) -> Int {
        if isZeroWidth(scalar) { return 0 }
        if scalar.properties.isEmojiPresentation || isWide(scalar.value) { return 2 }
        return 1
    }

    /// Combining marks (which stack on the previous glyph) and the explicit zero-width
    /// format scalars (ZWSP/ZWNJ/ZWJ and the byte-order mark / zero-width no-break space).
    private static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200B, 0x200C, 0x200D, 0xFEFF: return true
        default: break
        }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark: return true
        default: return false
        }
    }

    /// East Asian Wide (W) and Fullwidth (F) ranges, sorted and non-overlapping for the
    /// binary search below. Covers Hangul, CJK ideographs and radicals, kana, fullwidth
    /// forms, and the main emoji blocks.
    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F,  // Hangul Jamo
        0x2329...0x232A,  // angle brackets
        0x2E80...0x303E,  // CJK radicals … Kangxi … ideographic space
        0x3041...0x33FF,  // Hiragana … CJK symbols
        0x3400...0x4DBF,  // CJK Unified Ext A
        0x4E00...0x9FFF,  // CJK Unified Ideographs
        0xA000...0xA4CF,  // Yi
        0xA960...0xA97F,  // Hangul Jamo Extended-A
        0xAC00...0xD7A3,  // Hangul Syllables
        0xF900...0xFAFF,  // CJK Compatibility Ideographs
        0xFE10...0xFE19,  // Vertical forms
        0xFE30...0xFE6F,  // CJK Compatibility / Small forms
        0xFF00...0xFF60,  // Fullwidth Forms
        0xFFE0...0xFFE6,  // Fullwidth signs
        0x1F300...0x1F64F,  // Misc symbols, pictographs, emoticons
        0x1F900...0x1F9FF,  // Supplemental symbols & pictographs
        0x20000...0x3FFFD,  // CJK Ext B and beyond (planes 2–3)
    ]

    private static func isWide(_ value: UInt32) -> Bool {
        var low = 0
        var high = wideRanges.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let range = wideRanges[mid]
            if value < range.lowerBound {
                high = mid - 1
            } else if value > range.upperBound {
                low = mid + 1
            } else {
                return true
            }
        }
        return false
    }
}
