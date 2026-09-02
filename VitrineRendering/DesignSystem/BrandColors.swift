import SwiftUI
import VitrineDomain

extension Brand {

    /// A semantic brand color with explicit appearance variants. Resolving a
    /// single `Color` from these (`BrandColor.color`) guarantees the right value
    /// for light, dark, and high-contrast appearances without relying on
    /// an asset-catalog lookup, which keeps the palette testable in isolation.
    public struct BrandColor: Equatable {
        public let light: Color
        public let dark: Color
        /// Light + increased contrast.
        public let lightHighContrast: Color
        /// Dark + increased contrast.
        public let darkHighContrast: Color

        /// Creates a brand color, defaulting the high-contrast variants to the
        /// base ones when no separate value is needed.
        public init(
            light: Color,
            dark: Color,
            lightHighContrast: Color? = nil,
            darkHighContrast: Color? = nil
        ) {
            self.light = light
            self.dark = dark
            self.lightHighContrast = lightHighContrast ?? light
            self.darkHighContrast = darkHighContrast ?? dark
        }

        /// Resolves the variant for an appearance.
        public func resolved(scheme: ColorScheme, highContrast: Bool) -> Color {
            switch (scheme, highContrast) {
            case (.dark, true): darkHighContrast
            case (.dark, false): dark
            case (_, true): lightHighContrast
            default: light
            }
        }

        /// A SwiftUI `Color` that adapts to the current appearance automatically.
        /// Use this in views; it reads the trait environment at draw time.
        public var color: Color {
            Color(
                nsColor: NSColor(name: nil) { appearance in
                    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    let isHighContrast =
                        appearance.bestMatch(from: [
                            .accessibilityHighContrastAqua, .aqua,
                        ]) == .accessibilityHighContrastAqua
                        || appearance.bestMatch(from: [
                            .accessibilityHighContrastDarkAqua, .darkAqua,
                        ]) == .accessibilityHighContrastDarkAqua
                    let resolved = self.resolved(
                        scheme: isDark ? .dark : .light, highContrast: isHighContrast)
                    return NSColor(resolved)
                })
        }
    }

    /// The Vitrine brand palette. The signature accent is a violet→azure
    /// identity shared by the app accent, focus rings, and the brand gradient.
    public enum Palette {
        /// Primary brand accent (matches `AccentColor` in the asset catalog).
        public static let accent = BrandColor(
            light: Color(hex: "#4F46E5"),  // indigo 600
            dark: Color(hex: "#7C8CFF"),  // brightened for dark surfaces
            lightHighContrast: Color(hex: "#3A30C4"),
            darkHighContrast: Color(hex: "#AEB8FF")
        )

        /// Secondary accent used in the brand gradient's far stop.
        public static let accentSecondary = BrandColor(
            light: Color(hex: "#06B6D4"),  // cyan 500
            dark: Color(hex: "#22D3EE"),
            lightHighContrast: Color(hex: "#0E7490"),
            darkHighContrast: Color(hex: "#67E8F9")
        )

        /// The neutral stage behind previews (the "display case" backdrop).
        public static let stage = BrandColor(
            light: Color(hex: "#ECEDF2"),
            dark: Color(hex: "#15161C"),
            lightHighContrast: Color(hex: "#FFFFFF"),
            darkHighContrast: Color(hex: "#000000")
        )

        /// Primary text on app surfaces.
        public static let textPrimary = BrandColor(
            light: Color(hex: "#1A1B22"),
            dark: Color(hex: "#F4F5FA"),
            lightHighContrast: Color(hex: "#000000"),
            darkHighContrast: Color(hex: "#FFFFFF")
        )

        /// Secondary / caption text on app surfaces.
        public static let textSecondary = BrandColor(
            light: Color(hex: "#5B5D6B"),
            dark: Color(hex: "#A9ABBA"),
            lightHighContrast: Color(hex: "#3A3B45"),
            darkHighContrast: Color(hex: "#D6D8E4")
        )

        /// Hairline border for app cards and previews (chrome). Adapts to the
        /// app's appearance — use this for hairlines drawn *in the UI*.
        public static let border = BrandColor(
            light: Color(hex: "#1A1B22").opacity(0.12),
            dark: Color(hex: "#FFFFFF").opacity(0.10),
            lightHighContrast: Color(hex: "#1A1B22").opacity(0.32),
            darkHighContrast: Color(hex: "#FFFFFF").opacity(0.28)
        )

        /// Hairline border for the exported code card. Unlike ``border``, this is
        /// deliberately a single appearance-independent value: the stroke is
        /// *inside the exported image*, drawn over the always-dark code surface,
        /// so it must not flip with the app's light/dark appearance. Centralized
        /// here so the export content shares one documented token rather than a
        /// stray literal in the canvas view.
        public static let exportedCardBorder = Color.white.opacity(0.08)
    }
}
