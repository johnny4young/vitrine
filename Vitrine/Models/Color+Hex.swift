import SwiftUI

extension Color {
    /// The color's straight (non-premultiplied) sRGB components, in `0...1`.
    ///
    /// `Color` is not directly `Codable`, so background persistence (CS-050) and
    /// the custom-gradient/solid editors (CS-051) round-trip through this fixed
    /// sRGB representation. Resolving through `NSColor(...).usingColorSpace(.sRGB)`
    /// pins a single, display-independent color space so an encoded color decodes
    /// to the same value on any screen. If conversion ever fails (not expected for
    /// an sRGB-constructible color) it degrades to opaque black rather than
    /// trapping, mirroring `Color(hex:)`'s release behavior.
    var sRGBComponents: (red: Double, green: Double, blue: Double, opacity: Double) {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else {
            return (0, 0, 0, 1)
        }
        return (
            Double(srgb.redComponent), Double(srgb.greenComponent),
            Double(srgb.blueComponent), Double(srgb.alphaComponent)
        )
    }

    /// Creates a color from a hex string such as `"#282C34"`, `"282C34"`,
    /// `"#282C34FF"` (RGBA), or the `"#FFF"` / `"#FFFF"` shorthands.
    ///
    /// On malformed input (non-hex characters or an unsupported length) it falls
    /// back to opaque black so the app never crashes in release. Because this is
    /// the load-bearing primitive under the whole brand palette, a malformed
    /// literal is almost always a typo, so DEBUG builds `assertionFailure` to
    /// surface it immediately in tests and development instead of silently
    /// rendering an invisible/wrong brand color.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        let scanned = Scanner(string: cleaned).scanHexInt64(&value)

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
            // Unsupported length (including the empty string): one clear
            // assertion. The scan-failure assert below is gated to valid
            // lengths so malformed input never trips two asserts.
            assertionFailure("Color(hex:) got malformed input \"\(hex)\"; falling back to black")
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
            return
        }
        // The length matched a known format but the scan failed, so non-hex
        // characters slipped in (e.g. a stray letter) — a typo worth surfacing
        // in DEBUG. This is reachable only from the valid 3/4/6/8 branches.
        if !scanned {
            assertionFailure("Color(hex:) could not parse \"\(hex)\"; falling back to black")
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Captures this color as a validated `HexColor` (CS-031), resolved through the
    /// same fixed sRGB representation as `sRGBComponents` so a color saved from the
    /// custom-theme editor round-trips to the exact value the theme file stores.
    var hexColor: HexColor {
        let components = sRGBComponents
        // The components are always finite and in 0...1, so the canonical hex string
        // parses back; the `?? black` is an unreachable belt-and-suspenders fallback.
        return HexColor(
            String(
                format: "#%02X%02X%02X%02X",
                Int((components.red * 255).rounded()),
                Int((components.green * 255).rounded()),
                Int((components.blue * 255).rounded()),
                Int((components.opacity * 255).rounded())))
            ?? HexColor("#000000")!
    }
}

/// A `Codable` sRGB color, used to persist solid and custom-gradient colors
/// (CS-051) since SwiftUI's `Color` is not itself `Codable`.
///
/// Colors are stored as four straight (non-premultiplied) sRGB components in
/// `0...1`, resolved through a fixed color space so the value is
/// display-independent. Decoding clamps each component, so a hand-edited or
/// corrupt store can never produce an out-of-range color (CS-050).
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

    /// Captures `color` in fixed sRGB so it survives a persistence round-trip.
    init(_ color: Color) {
        let components = color.sRGBComponents
        self.init(
            red: components.red, green: components.green, blue: components.blue,
            opacity: components.opacity)
    }

    /// The SwiftUI color, reconstructed in the sRGB space it was captured in.
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.red = Self.clamp(try container.decode(Double.self, forKey: .red))
        self.green = Self.clamp(try container.decode(Double.self, forKey: .green))
        self.blue = Self.clamp(try container.decode(Double.self, forKey: .blue))
        // Default a missing alpha to fully opaque so an older or partial record
        // decodes to a visible color rather than a transparent one.
        self.opacity = Self.clamp((try? container.decode(Double.self, forKey: .opacity)) ?? 1)
    }

    /// Clamps to `0...1`, replaces non-finite input with `0`, and **quantizes**
    /// to a fixed precision.
    ///
    /// Quantizing matters for equality: capturing the same visible color from
    /// different `Color` representations (a named color, a `Color(hex:)`, a
    /// persisted-then-restored color) can drift by sub-`1e-6` amounts through the
    /// sRGB color-space conversion. Rounding to four decimals — finer than the
    /// 8-bit precision the PNG ultimately carries — collapses that noise so a
    /// color equals its own round-trip exactly, and so the encoded JSON is
    /// deterministic.
    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let clamped = min(max(value, 0), 1)
        return (clamped * 10_000).rounded() / 10_000
    }
}
