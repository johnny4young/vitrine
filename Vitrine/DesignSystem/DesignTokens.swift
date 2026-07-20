import SwiftUI

/// Vitrine's centralized visual design tokens.
///
/// `Brand` is the single source of truth for the values that repeat across the
/// app chrome and the exported image: spacing, corner radii, shadow recipes,
/// stroke widths, and the brand color palette. Views read these tokens instead
/// of hardcoding numbers and colors, so the product reads as one coherent
/// "display case" rather than a generic settings app.
///
/// The palette colors are defined in code (sRGB) with explicit light, dark, and
/// high-contrast variants so the look is correct in every appearance without
/// depending on asset-catalog round-trips. `BrandColor.color` resolves the right
/// variant for the current `ColorScheme` / accessibility contrast.
enum Brand {

    // MARK: Spacing

    /// A 4-point spacing scale. Use these names instead of bare numbers so
    /// rhythm stays consistent across panes, toolbars, and cards.
    enum Spacing {
        /// 4 pt — hairline gaps (e.g. between a label and its caption).
        static let xxs: CGFloat = 4
        /// 8 pt — tight stacks and the traffic-light dot gap.
        static let xs: CGFloat = 8
        /// 12 pt — default control spacing.
        static let sm: CGFloat = 12
        /// 16 pt — section padding.
        static let md: CGFloat = 16
        /// 24 pt — pane padding and card insets.
        static let lg: CGFloat = 24
        /// 32 pt — generous canvas padding (matches the default export padding).
        static let xl: CGFloat = 32
        /// 48 pt — hero / empty-state breathing room.
        static let xxl: CGFloat = 48
    }

    // MARK: Layout

    /// Shared layout sizes for app chrome. Centralizing these keeps adjacent
    /// controls aligned instead of drifting to slightly different magic numbers.
    enum Layout {
        /// Maximum width for the popup controls in the editor header, so the
        /// Language and Destination pickers sit at the same size on one row.
        static let headerControlMaxWidth: CGFloat = 220
    }

    // MARK: Radius

    /// Corner-radius scale. Cards and previews use `.continuous` rounded
    /// rectangles for the soft, modern Vitrine silhouette.
    enum Radius {
        /// 6 pt — small chips and tags.
        static let sm: CGFloat = 6
        /// 10 pt — preview surfaces and thumbnails.
        static let md: CGFloat = 10
        /// 14 pt — large panels and the editor stage.
        static let lg: CGFloat = 14
        /// 20 pt — the brand "vitrine" card framing.
        static let xl: CGFloat = 20

        /// The default code-card corner radius exposed in `SnapshotConfig`.
        static let card: CGFloat = 8
    }

    // MARK: Stroke

    /// Hairline border widths. Vitrine uses thin, low-opacity strokes to read as
    /// glass rather than heavy outlines.
    enum Stroke {
        /// 1 pt — the standard hairline border.
        static let hairline: CGFloat = 1
        /// 1.5 pt — emphasized focus ring.
        static let focus: CGFloat = 1.5
    }

    // MARK: Shadow

    /// A named drop-shadow recipe (color + blur radius + offset). Centralizing
    /// these keeps elevation consistent between the in-app preview and exports.
    struct ShadowStyle: Equatable {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        /// No shadow — a clear, zero-radius recipe, e.g. for a disabled control that
        /// must not keep its elevation/glow.
        static let none = ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
    }

    enum Shadow {
        /// Subtle lift for cards and thumbnails inside the app chrome.
        static let card = ShadowStyle(
            color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        /// The deeper, offset shadow used under the exported code card.
        static let elevated = ShadowStyle(
            color: .black.opacity(0.35), radius: 20, x: 0, y: 8)
    }

    // MARK: Materials

    /// Glass / surface materials. Prefer SwiftUI `Material` so surfaces respect
    /// the system vibrancy and stay macOS-native.
    enum Surface {
        /// Translucent panel chrome (inspectors, toolbars over content).
        static let glass: Material = .bar
        /// A regular elevated surface (cards on a neutral stage).
        static let raised: Material = .regular
    }
}

extension View {
    /// Applies a `Brand.ShadowStyle` recipe as a single drop shadow, so views
    /// adopt a named elevation token (`Brand.Shadow.card` / `.elevated`) in one
    /// call instead of spelling out the color/radius/offset fields by hand.
    func brandShadow(_ style: Brand.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
