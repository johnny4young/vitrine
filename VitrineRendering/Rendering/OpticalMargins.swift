import SwiftUI
import VitrineDomain

/// Balanced padding: the margin is measured to what the eye sees, the card plus the visible
/// part of its shadow, and the card sits a little above the geometric center.
public enum OpticalMargins {
    /// Share of the free vertical space that goes above the card.
    public static let topShare: CGFloat = 0.46
    /// How much of a shadow's blur radius reads as part of the card.
    public static let visibleShadowShare: CGFloat = 0.5

    /// Whole points, so a 1x export keeps the card's edges on the pixel grid.
    public static func insets(margin: CGFloat, shadow: Brand.ShadowStyle) -> EdgeInsets {
        let reach = shadow.radius * visibleShadowShare
        let lift = 2 * margin * (0.5 - topShare)
        return EdgeInsets(
            top: (margin + max(0, reach - shadow.y) - lift).rounded(),
            leading: (margin + max(0, reach - shadow.x)).rounded(),
            bottom: (margin + max(0, reach + shadow.y) + lift).rounded(),
            trailing: (margin + max(0, reach + shadow.x)).rounded())
    }
}

extension VerticalAlignment {
    private enum OpticalCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            (context.height * OpticalMargins.topShare).rounded()
        }
    }

    /// Places a view in a taller frame with `topShare` of the free space above it.
    public static let opticalCenter = VerticalAlignment(OpticalCenter.self)
}

extension SnapshotConfig {
    /// The exported card's drop shadow, or a true no-op when shadows are off: a zero-radius
    /// shadow with an offset would draw a crisp duplicate of the card.
    public var cardShadow: Brand.ShadowStyle {
        guard showShadow else { return .none }
        return Brand.ShadowStyle(
            color: Brand.Shadow.elevated.color,
            radius: effectiveShadowRadius,
            x: Brand.Shadow.elevated.x,
            y: Brand.Shadow.elevated.y)
    }

    /// The padding around the card on each edge.
    public var canvasInsets: EdgeInsets {
        switch paddingMode {
        case .manual: EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
        case .balanced: OpticalMargins.insets(margin: padding, shadow: cardShadow)
        }
    }

    /// Where the padded card sits in a fixed-size frame.
    public var canvasAlignment: Alignment {
        paddingMode == .balanced
            ? Alignment(horizontal: .center, vertical: .opticalCenter) : .center
    }

    /// The share of a fixed frame's free vertical space that `canvasAlignment` puts above.
    public var canvasTopShare: CGFloat {
        paddingMode == .balanced ? OpticalMargins.topShare : 0.5
    }
}
