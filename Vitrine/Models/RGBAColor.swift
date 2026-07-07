import Foundation

/// A `Codable`, UI-free sRGB color: four straight (non-premultiplied) components in
/// `0...1`, resolved through a fixed color space so the value is display-independent
/// (CS-050/CS-051). This is the model layer's color representation — it carries no
/// `SwiftUI`/`AppKit` dependency, so the models that store colors stay UI-free (the
/// prerequisite for a `VitrineCore` package). The `SwiftUI.Color` bridging lives in
/// `Color+Hex.swift` in the UI layer.
///
/// Decoding clamps each component, so a hand-edited or corrupt store can never produce
/// an out-of-range color.
struct RGBAColor: Equatable, Hashable, Codable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.opacity = Self.clamp(opacity)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.red = Self.clamp(try container.decode(Double.self, forKey: .red))
        self.green = Self.clamp(try container.decode(Double.self, forKey: .green))
        self.blue = Self.clamp(try container.decode(Double.self, forKey: .blue))
        // Default a missing alpha to fully opaque so an older or partial record decodes
        // to a visible color rather than a transparent one.
        self.opacity = Self.clamp((try? container.decode(Double.self, forKey: .opacity)) ?? 1)
    }

    /// Opaque black — the documented fallback for a malformed color.
    static let fallbackBlack = RGBAColor(red: 0, green: 0, blue: 0, opacity: 1)

    /// Parses a hex string such as `"#282C34"`, `"282C34"`, `"#282C34FF"` (RGBA), or the
    /// `"#FFF"` / `"#FFFF"` shorthands into components, or `nil` on malformed input
    /// (non-hex characters or an unsupported length). Pure and UI-free; the
    /// `Color(hex:)` initializer and `HexColor` build on it and add the SwiftUI bridge
    /// and the DEBUG typo assertions.
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        // `scanHexInt64` succeeds on any leading hex digits, so also require the scanner
        // to have consumed the whole string — otherwise mixed input of a valid length
        // ("12GG34") would silently decode the partial value into a wrong color.
        let scanner = Scanner(string: cleaned)
        guard scanner.scanHexInt64(&value), scanner.isAtEnd else { return nil }

        let r: Double
        let g: Double
        let b: Double
        let a: Double
        switch cleaned.count {
        case 8:  // RRGGBBAA
            r = Double((value & 0xFF00_0000) >> 24) / 255
            g = Double((value & 0x00FF_0000) >> 16) / 255
            b = Double((value & 0x0000_FF00) >> 8) / 255
            a = Double(value & 0x0000_00FF) / 255
        case 6:  // RRGGBB
            r = Double((value & 0xFF_0000) >> 16) / 255
            g = Double((value & 0x00_FF00) >> 8) / 255
            b = Double(value & 0x00_00FF) / 255
            a = 1
        case 4:  // RGBA shorthand → each nibble doubled (e.g. F → FF)
            r = Double((value & 0xF000) >> 12) / 15
            g = Double((value & 0x0F00) >> 8) / 15
            b = Double((value & 0x00F0) >> 4) / 15
            a = Double(value & 0x000F) / 15
        case 3:  // RGB shorthand
            r = Double((value & 0xF00) >> 8) / 15
            g = Double((value & 0x0F0) >> 4) / 15
            b = Double(value & 0x00F) / 15
            a = 1
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }

    /// The canonical `#RRGGBBAA` hex string for these components.
    var hexString: String {
        String(
            format: "#%02X%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded()),
            Int((opacity * 255).rounded()))
    }

    /// Clamps to `0...1`, replaces non-finite input with `0`, and **quantizes** to a
    /// fixed precision.
    ///
    /// Quantizing matters for equality: capturing the same visible color from different
    /// `Color` representations (a named color, a `Color(hex:)`, a persisted-then-restored
    /// color) can drift by sub-`1e-6` amounts through the sRGB color-space conversion.
    /// Rounding to four decimals — finer than the 8-bit precision the PNG ultimately
    /// carries — collapses that noise so a color equals its own round-trip exactly, and so
    /// the encoded JSON is deterministic.
    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let clamped = min(max(value, 0), 1)
        return (clamped * 10_000).rounded() / 10_000
    }
}
