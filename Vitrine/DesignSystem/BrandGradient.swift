import SwiftUI

extension Brand {

    /// Brand gradients shared by the app chrome and the exported presets so the
    /// UI and the images speak the same visual language.
    enum Gradient {
        /// The signature violet→azure brand gradient. This is the same direction
        /// and vocabulary used by the `GradientPreset.aurora` export preset, so a
        /// rendered screenshot reads as unmistakably "Vitrine".
        static let signature = LinearGradient(
            colors: [Palette.accent.color, Palette.accentSecondary.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// A muted version for large background washes behind hero content.
        static func signatureWash(opacity: Double = 0.18) -> LinearGradient {
            LinearGradient(
                colors: [
                    Palette.accent.color.opacity(opacity),
                    Palette.accentSecondary.color.opacity(opacity),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
