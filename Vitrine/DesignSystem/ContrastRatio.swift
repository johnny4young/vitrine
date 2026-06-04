import SwiftUI

extension Brand {

    /// WCAG 2.1 contrast utilities (CS-036). Used to assert that critical
    /// text/background pairs in the brand palette stay legible across light,
    /// dark, and high-contrast appearances.
    enum Contrast {

        /// WCAG AA threshold for normal-size body text.
        static let aaNormal = 4.5
        /// WCAG AA threshold for large text (>= ~18 pt, or 14 pt bold).
        static let aaLarge = 3.0

        /// The WCAG contrast ratio (1...21) between two opaque colors, computed
        /// from their relative luminance.
        static func ratio(_ a: Color, on b: Color) -> Double {
            let la = relativeLuminance(a)
            let lb = relativeLuminance(b)
            let lighter = max(la, lb)
            let darker = min(la, lb)
            return (lighter + 0.05) / (darker + 0.05)
        }

        /// WCAG relative luminance of a color, resolved in sRGB.
        static func relativeLuminance(_ color: Color) -> Double {
            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
            func linear(_ channel: Double) -> Double {
                channel <= 0.039_28 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            let r = linear(Double(srgb.redComponent))
            let g = linear(Double(srgb.greenComponent))
            let b = linear(Double(srgb.blueComponent))
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
    }
}
