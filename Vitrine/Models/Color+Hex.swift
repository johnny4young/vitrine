import SwiftUI

extension Color {
    /// The color's straight (non-premultiplied) sRGB components, in `0...1`.
    ///
    /// `Color` is not directly `Codable`, so background persistence and
    /// the custom-gradient/solid editors round-trip through this fixed
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
        // Parse UI-free via `RGBAColor`; keep the DEBUG typo assertion + release
        // black fallback in the SwiftUI layer (the model parser stays pure).
        guard let rgba = RGBAColor(hex: hex) else {
            // Malformed input (non-hex characters or an unsupported length): surface
            // palette typos immediately in DEBUG, degrade to opaque black in release.
            assertionFailure("Color(hex:) got malformed input \"\(hex)\"; falling back to black")
            self = RGBAColor.fallbackBlack.color
            return
        }
        self = rgba.color
    }

    /// Captures this color as a validated `HexColor`, resolved through the
    /// same fixed sRGB representation as `sRGBComponents` so a color saved from the
    /// custom-theme editor round-trips to the exact value the theme file stores.
    var hexColor: HexColor {
        // The components are always finite and in 0...1, so the canonical hex string
        // parses back; the `?? .black` is an unreachable belt-and-suspenders fallback.
        HexColor(RGBAColor(self).hexString) ?? .black
    }
}

// MARK: - RGBAColor ⇄ SwiftUI.Color bridge

extension RGBAColor {
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
}
