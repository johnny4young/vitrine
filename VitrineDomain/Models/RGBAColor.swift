import Foundation

/// A `Codable`, UI-free sRGB color: four straight (non-premultiplied) components in
/// `0...1`, resolved through a fixed color space so the value is display-independent.
/// This is the model layer's color representation — it carries no
/// `SwiftUI`/`AppKit` dependency, so the models that store colors stay UI-free (the
/// prerequisite for a `VitrineCore` package). The `SwiftUI.Color` bridging lives in
/// `Color+Hex.swift` in the UI layer.
///
/// Decoding clamps each component, so a hand-edited or corrupt store can never produce
/// an out-of-range color.
public struct RGBAColor: Equatable, Hashable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.opacity = Self.clamp(opacity)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.red = Self.clamp(try container.decode(Double.self, forKey: .red))
        self.green = Self.clamp(try container.decode(Double.self, forKey: .green))
        self.blue = Self.clamp(try container.decode(Double.self, forKey: .blue))
        // Default a missing alpha to fully opaque so an older or partial record decodes
        // to a visible color rather than a transparent one.
        self.opacity = Self.clamp((try? container.decode(Double.self, forKey: .opacity)) ?? 1)
    }

    /// Opaque black — the documented fallback for a malformed color.
    public static let fallbackBlack = RGBAColor(red: 0, green: 0, blue: 0, opacity: 1)

    /// Parses a hex string such as `"#282C34"`, `"282C34"`, `"#282C34FF"` (RGBA), or the
    /// `"#FFF"` / `"#FFFF"` shorthands into components, or `nil` on malformed input
    /// (non-hex characters or an unsupported length). Pure and UI-free; the
    /// `Color(hex:)` initializer and `HexColor` build on it and add the SwiftUI bridge
    /// and the DEBUG typo assertions.
    public init?(hex: String) {
        guard let components = Self.hexComponents(hex) else { return nil }
        self.init(
            red: components.red, green: components.green, blue: components.blue,
            opacity: components.alpha)
    }

    /// The one hex parser behind `RGBAColor` and `HexColor`: unquantized sRGB components for
    /// a 3/4/6/8-digit string with an optional `#` and surrounding whitespace.
    static func hexComponents(
        _ hex: String
    ) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        // `Scanner` also accepts a `0x` prefix and leading whitespace, and `isHexDigit`
        // admits fullwidth digits, so only ASCII hex digits may reach the scan.
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isASCII && $0.isHexDigit }),
            let value = UInt64(cleaned, radix: 16)
        else { return nil }

        switch cleaned.count {
        case 8:  // RRGGBBAA
            return (
                Double((value & 0xFF00_0000) >> 24) / 255,
                Double((value & 0x00FF_0000) >> 16) / 255,
                Double((value & 0x0000_FF00) >> 8) / 255,
                Double(value & 0x0000_00FF) / 255
            )
        case 6:  // RRGGBB
            return (
                Double((value & 0xFF_0000) >> 16) / 255,
                Double((value & 0x00_FF00) >> 8) / 255,
                Double(value & 0x00_00FF) / 255,
                1
            )
        case 4:  // RGBA shorthand → each nibble doubled (e.g. F → FF)
            return (
                Double((value & 0xF000) >> 12) / 15,
                Double((value & 0x0F00) >> 8) / 15,
                Double((value & 0x00F0) >> 4) / 15,
                Double(value & 0x000F) / 15
            )
        case 3:  // RGB shorthand
            return (
                Double((value & 0xF00) >> 8) / 15,
                Double((value & 0x0F0) >> 4) / 15,
                Double(value & 0x00F) / 15,
                1
            )
        default:
            return nil
        }
    }

    /// The canonical `#RRGGBBAA` hex string for these components.
    public var hexString: String {
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
