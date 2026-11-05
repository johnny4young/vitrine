import SwiftUI

/// Draws a slide's `2 / 4` badge in the canvas corner. An overlay never changes the
/// canvas's measured size, and without a page label the content passes through unchanged.
struct SlidePageBadgeOverlay: ViewModifier {
    let cue: SlideCue?
    let watermark: Watermark?

    func body(content: Content) -> some View {
        if let label = cue?.pageLabel {
            content.overlay(alignment: alignment) {
                SlidePageBadge(label: label).padding(Self.inset)
            }
        } else {
            content
        }
    }

    /// Yields the corner to a brand mark already placed there.
    private var alignment: Alignment {
        guard let watermark, watermark.hasContent else { return .topTrailing }
        let holdsCorner =
            switch watermark.placement {
            case .topTrailing: true
            case .free: watermark.freePosition.x > 0.5 && watermark.freePosition.y < 0.2
            default: false
            }
        return holdsCorner ? .topLeading : .topTrailing
    }

    private static let inset: CGFloat = 40
}

/// Solid colors and a system font only, so it renders deterministically through
/// `ImageRenderer` and stays legible over any background.
struct SlidePageBadge: View {
    let label: String

    var body: some View {
        Text(verbatim: label)
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .fixedSize()
    }
}
