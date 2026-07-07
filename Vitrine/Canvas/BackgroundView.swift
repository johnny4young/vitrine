import SwiftUI

/// Renders the snapshot background: solid color, gradient preset, custom
/// gradient, user image, or transparent (CS-005 / CS-051).
///
/// The transparent case is load-bearing for color management (CS-024): it must
/// export with a real alpha channel and never composite the canvas over an
/// opaque matte. `Color.clear` produces fully transparent pixels — `(0, 0, 0, 0)`
/// — which the exporter carries through to the PNG's alpha channel unchanged. The
/// solid, gradient, and image cases are explicitly opaque, so an opaque
/// background never leaks partial transparency into the export.
///
/// A missing or unreadable background image degrades gracefully to the signature
/// gradient default rather than rendering nothing (CS-051), so a relocated file
/// never produces a blank or broken export.
struct BackgroundView: View {
    let style: BackgroundStyle

    /// Resolves image references to files in the app container. Taken from the
    /// environment so a test or preview can inject an isolated store
    /// (`\.backgroundImageStore`).
    @Environment(\.backgroundImageStore) private var imageStore

    var body: some View {
        switch style {
        case .solid(let color):
            color.color.opacity(1)
        case .gradient(let preset):
            preset.gradient.opacity(1)
        case .customGradient(let gradient):
            gradient.linearGradient.opacity(1)
        case .image(let image):
            imageBackground(image)
        case .transparent:
            // Real transparency: clear in the preview and a true alpha channel in
            // the export, with no matte fill behind the card (CS-024).
            Color.clear
        }
    }

    /// Renders an image background with fit, optional blur, and dimming. Falls
    /// back to the signature gradient when the file cannot be resolved (CS-051).
    @ViewBuilder
    private func imageBackground(_ image: ImageBackground) -> some View {
        if let nsImage = imageStore.image(for: image.reference) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: image.fit.contentMode)
                // Blur first, then clip so a blurred edge never bleeds past the
                // canvas; the frame is filled by the parent's sizing.
                .blur(radius: image.blur)
                .clipped()
                // A dark overlay improves code legibility over a busy photo
                // without modifying the photo's pixels.
                .overlay(Color.black.opacity(image.dimming))
        } else {
            // Graceful degradation: a relocated/missing image still produces a
            // valid, recognizably-Vitrine background instead of nothing.
            GradientPreset.aurora.gradient.opacity(1)
        }
    }
}
