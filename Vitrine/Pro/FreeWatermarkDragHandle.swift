import AppKit
import SwiftUI

/// The interactive drag layer for a free-placed brand mark (CS-092 follow-up).
///
/// The mark itself is drawn by `SnapshotCanvas`'s `WatermarkOverlay` (in the live
/// editor preview) or baked into the rendered preview image (in Settings) beneath
/// this layer, so the preview always stays WYSIWYG. This view adds only the
/// interaction: a pointer drag over the mark becomes a normalized position update,
/// clamped to the canvas. It is shown only when the Brand Kit placement is `.free`.
///
/// Like `AnnotationEditingOverlay`, it drives the move from the drag *translation*
/// (a coordinate-space-independent delta) plus a captured origin, so it is correct
/// whether it sits inside the editor's `scaleEffect` or over an aspect-fit image.
struct FreeWatermarkDragHandle: View {
    /// The mark's normalized center (x,y in 0…1), bound to the brand kit.
    @Binding var position: CGPoint
    /// The image/canvas content rect in this view's coordinate space. Pass the full
    /// bounds for a live canvas, or the letterboxed rect for an aspect-fit image.
    let contentRect: CGRect

    /// The normalized position when the current drag began.
    @State private var dragOrigin: CGPoint?

    /// A grab zone roughly the size of the badge, so hovering "over the mark" works
    /// without measuring the rendered badge.
    private static let hitSize = CGSize(width: 172, height: 50)

    var body: some View {
        let center = CGPoint(
            x: contentRect.minX + position.x * contentRect.width,
            y: contentRect.minY + position.y * contentRect.height)
        // An invisible grab zone (a dashed outline appears only while dragging, as
        // grab feedback) that never alters the rendered mark beneath it.
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(
                VitrineTokens.Accent.base.opacity(dragOrigin == nil ? 0 : 0.9),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
            )
            .frame(width: Self.hitSize.width, height: Self.hitSize.height)
            .contentShape(Rectangle())
            .position(center)
            .gesture(dragGesture)
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help("Drag to place the brand mark")
            .accessibilityLabel("Brand mark position")
            .accessibilityIdentifier("brand-kit-free-drag-handle")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragOrigin == nil { dragOrigin = position }
                guard let origin = dragOrigin, contentRect.width > 0, contentRect.height > 0
                else { return }
                let dx = value.translation.width / contentRect.width
                let dy = value.translation.height / contentRect.height
                position = Watermark.clampFreePosition(
                    CGPoint(x: origin.x + dx, y: origin.y + dy))
            }
            .onEnded { _ in dragOrigin = nil }
    }

    /// The largest rect with `imageSize`'s aspect ratio that fits centered in `bounds`
    /// — the content rect of an aspect-fit preview image, so a drag maps to the image,
    /// not the letterbox around it.
    static func aspectFitRect(imageSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0
        else { return CGRect(origin: .zero, size: bounds) }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
            width: size.width, height: size.height)
    }
}
