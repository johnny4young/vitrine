import SwiftUI
import VitrineDomain

extension Brand {

    /// WCAG 2.1 contrast utilities. Used to assert that critical
    /// text/background pairs in the brand palette stay legible across light,
    /// dark, and high-contrast appearances.
    public enum Contrast {

        /// WCAG AA threshold for normal-size body text.
        public nonisolated static let aaNormal = 4.5
        /// WCAG AA threshold for large text (>= ~18 pt, or 14 pt bold).
        public nonisolated static let aaLarge = 3.0

        /// The WCAG contrast ratio (1...21) between two opaque colors, computed
        /// from their relative luminance.
        public nonisolated static func ratio(_ a: Color, on b: Color) -> Double {
            let la = relativeLuminance(a)
            let lb = relativeLuminance(b)
            let lighter = max(la, lb)
            let darker = min(la, lb)
            return (lighter + 0.05) / (darker + 0.05)
        }

        /// WCAG relative luminance of a color, resolved in sRGB.
        public nonisolated static func relativeLuminance(_ color: Color) -> Double {
            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
            func linear(_ channel: Double) -> Double {
                channel <= 0.039_28 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            let r = linear(Double(srgb.redComponent))
            let g = linear(Double(srgb.greenComponent))
            let b = linear(Double(srgb.blueComponent))
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }

        /// `top` flattened over `bottom` in sRGB, the opaque color a ratio can be measured from.
        public nonisolated static func composite(_ top: NSColor, over bottom: NSColor) -> NSColor {
            guard let top = top.usingColorSpace(.sRGB), let bottom = bottom.usingColorSpace(.sRGB)
            else { return bottom }
            let alpha = top.alphaComponent
            return NSColor(
                srgbRed: top.redComponent * alpha + bottom.redComponent * (1 - alpha),
                green: top.greenComponent * alpha + bottom.greenComponent * (1 - alpha),
                blue: top.blueComponent * alpha + bottom.blueComponent * (1 - alpha),
                alpha: 1)
        }
    }
}
