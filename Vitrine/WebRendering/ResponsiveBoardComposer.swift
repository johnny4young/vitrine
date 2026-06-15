import CoreGraphics
import SwiftUI

/// Composites the captured viewports of a multi-resolution batch into one shareable
/// "responsive board" image (CS-044): each capture on a labeled card, laid out in a row
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
    /// The reserved height for a card's size label below its image.
    static let labelHeight: CGFloat = 38

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
            return SizedCapture(
                capture: capture, cardWidth: (cardImageHeight * aspect).rounded())
        }

        let totalWidth =
            padding * 2 + sized.map(\.cardWidth).reduce(0, +)
            + spacing * CGFloat(max(sized.count - 1, 0))
        let totalHeight = padding * 2 + cardImageHeight + labelHeight

        let board = BoardView(sized: sized).frame(width: totalWidth, height: totalHeight)
        let renderer = ImageRenderer(content: board)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage else { return nil }
        return RenderedAsset(
            cgImage: ExportManager.normalized(cgImage, to: profile), profile: profile)
    }

    /// One capture paired with its computed card width (aspect-derived from the fixed
    /// card height), so the board layout is fully determined before rendering.
    struct SizedCapture: Identifiable {
        let capture: CapturedViewport
        let cardWidth: CGFloat
        var id: WebSnapshotConfig.ViewportPreset.Kind { capture.kind }
    }

    /// The board canvas: the cards in a row over a fixed dark gradient. The gradient is
    /// hard-coded (not theme-derived) so the composite is deterministic.
    private struct BoardView: View {
        let sized: [SizedCapture]

        var body: some View {
            HStack(alignment: .top, spacing: ResponsiveBoardComposer.spacing) {
                ForEach(sized) { item in
                    VStack(spacing: 12) {
                        Image(decorative: item.capture.asset.cgImage, scale: 1)
                            .resizable()
                            .frame(
                                width: item.cardWidth,
                                height: ResponsiveBoardComposer.cardImageHeight
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                        Text(verbatim: item.capture.label)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(height: ResponsiveBoardComposer.labelHeight)
                    }
                }
            }
            .padding(ResponsiveBoardComposer.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.06, blue: 0.13),
                        Color(red: 0.10, green: 0.08, blue: 0.20),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}
