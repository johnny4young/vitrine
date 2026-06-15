import SwiftUI

/// Composites the PRO Brand Kit watermark onto a snapshot canvas (CS-092).
///
/// Applied by `SnapshotCanvas` to its finished output. When `watermark` is `nil`
/// it returns the content **unchanged** — the exact same view tree — so the
/// default render and every golden image stay byte-for-byte identical; the overlay
/// only ever appears when the brand kit resolved a watermark at the export/preview
/// seam. Because it is an `.overlay`, it never changes the canvas's measured size,
/// so the editor's annotation coordinate space is unaffected.
struct WatermarkOverlay: ViewModifier {
    let watermark: Watermark?

    func body(content: Content) -> some View {
        if let watermark, watermark.hasContent {
            content.overlay(alignment: watermark.placement.alignment) {
                WatermarkBadge(watermark: watermark)
                    .padding(Self.inset)
            }
        } else {
            content
        }
    }

    /// The gap between the mark and the canvas edge.
    private static let inset: CGFloat = 18
}

/// The brand mark drawn in a snapshot's corner (CS-092): the optional logo and the
/// handle/project line on a subtle scrim that keeps it legible over any background.
///
/// It draws only solid colors and a system font (no materials/blurs), so it renders
/// deterministically through `ImageRenderer` and looks the same on every machine.
struct WatermarkBadge: View {
    let watermark: Watermark

    var body: some View {
        HStack(spacing: 7) {
            if let data = watermark.logoImageData, let logo = NSImage(data: data) {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: Self.logoHeight)
                    .accessibilityHidden(true)
            }
            if !watermark.text.isEmpty {
                Text(verbatim: watermark.text)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(watermark.tint?.color ?? .white)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .opacity(0.96)
    }

    /// The drawn height of the logo; the text sits beside it at a matched weight.
    private static let logoHeight: CGFloat = 20
}
