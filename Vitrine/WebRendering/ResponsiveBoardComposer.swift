import CoreGraphics
import SwiftUI

/// Composites the captured viewports of a multi-resolution batch into one shareable
/// "responsive board" image: each capture on a labeled card, laid out in a row
/// over a branded background, rendered with `ImageRenderer`.
///
/// The output size is a pure function of the input set — each card's image is scaled to a
/// fixed height and its width follows the capture's own aspect ratio, and the board frame
/// is computed from those — so the result is deterministic and golden-testable. The
/// composite never touches the network or the render core; it only arranges already-
/// rendered `CGImage`s, so it stays well clear of the gated export path.
enum ResponsiveBoardComposer {
    /// The fixed height each capture's card image is scaled to; the width follows the
    /// capture's aspect ratio, so a tall phone shot and a wide desktop shot sit side by
    /// side at a consistent height.
    static let cardImageHeight: CGFloat = 420
    /// The gap between cards.
    static let spacing: CGFloat = 28
    /// The board's outer padding.
    static let padding: CGFloat = 48
    /// The reserved height for a card's two-line caption (name + dimensions) below its
    /// image.
    static let labelHeight: CGFloat = 46
    /// The vertical gap between a card's image and its caption.
    static let labelGap: CGFloat = 12
    /// The minimum width a card's column occupies, regardless of how narrow the capture
    /// is. A full-page capture of a tall page yields a thin sliver of an image; flooring
    /// the column keeps the caption legible (centered under the image) instead of
    /// truncating it to "Deskt…" / "…". The image keeps its true aspect — only the
    /// column, and thus the caption's available width, is widened.
    static let minColumnWidth: CGFloat = 150

    /// The board's backing gradient, hard-coded (not theme-derived) so the composite stays
    /// deterministic for the golden suite. Named so the two anchor colors live in one place
    /// rather than as inline literals.
    static let boardGradientColors: [Color] = [
        Color(red: 0.07, green: 0.06, blue: 0.13),
        Color(red: 0.10, green: 0.08, blue: 0.20),
    ]

    /// Composes `captures` into a single board asset, or `nil` when the set is empty or
    /// the render fails. Main-actor bound (`ImageRenderer` requirement).
    @MainActor
    static func compose(
        _ captures: [CapturedViewport], scale: CGFloat, profile: ColorProfile
    ) -> RenderedAsset? {
        guard !captures.isEmpty else { return nil }

        let sized = captures.map { capture -> SizedCapture in
            let width = CGFloat(capture.asset.cgImage.width)
            let height = CGFloat(capture.asset.cgImage.height)
            let aspect = height > 0 ? width / height : 1
            let imageWidth = (cardImageHeight * aspect).rounded()
            return SizedCapture(
                capture: capture, imageWidth: imageWidth,
                columnWidth: max(imageWidth, minColumnWidth))
        }

        let totalWidth =
            padding * 2 + sized.map(\.columnWidth).reduce(0, +)
            + spacing * CGFloat(max(sized.count - 1, 0))
        let totalHeight = padding * 2 + cardImageHeight + labelGap + labelHeight

        let board = BoardView(sized: sized).frame(width: totalWidth, height: totalHeight)
        let renderer = ImageRenderer(content: board)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage else { return nil }
        return RenderedAsset(
            cgImage: ExportManager.normalized(cgImage, to: profile), profile: profile)
    }

    /// One capture paired with its computed image width (aspect-derived from the fixed
    /// card height) and the column width that hosts it (`max(imageWidth, minColumnWidth)`),
    /// so the board layout is fully determined before rendering.
    struct SizedCapture: Identifiable {
        let capture: CapturedViewport
        let imageWidth: CGFloat
        let columnWidth: CGFloat
        var id: WebSnapshotConfig.ViewportPreset.Kind { capture.kind }
    }

    /// The board canvas: the cards in a row over a fixed dark gradient. The gradient is
    /// hard-coded (not theme-derived) so the composite is deterministic.
    private struct BoardView: View {
        let sized: [SizedCapture]

        var body: some View {
            HStack(alignment: .top, spacing: ResponsiveBoardComposer.spacing) {
                ForEach(sized) { item in
                    VStack(spacing: ResponsiveBoardComposer.labelGap) {
                        Image(decorative: item.capture.asset.cgImage, scale: 1)
                            .resizable()
                            .frame(
                                width: item.imageWidth,
                                height: ResponsiveBoardComposer.cardImageHeight
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                        caption(for: item.capture.preset)
                            .frame(
                                width: item.columnWidth,
                                height: ResponsiveBoardComposer.labelHeight)
                    }
                    .frame(width: item.columnWidth)
                }
            }
            .padding(ResponsiveBoardComposer.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: ResponsiveBoardComposer.boardGradientColors,
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        }

        /// A card's two-line caption: the preset name above its dimensions. Split across
        /// two lines (and `minimumScaleFactor`-scaled as a last resort) so a long name like
        /// "Social card (1200 × 630)" no longer truncates to "…" on a narrow full-page card.
        @ViewBuilder
        private func caption(for preset: WebSnapshotConfig.ViewportPreset) -> some View {
            VStack(spacing: 2) {
                Text(verbatim: preset.boardName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                if !preset.boardDimensions.isEmpty {
                    Text(verbatim: preset.boardDimensions)
                        .font(.system(size: 13, weight: .regular).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
        }
    }
}
