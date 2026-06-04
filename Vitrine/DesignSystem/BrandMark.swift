import SwiftUI

/// Vitrine's brand mark: the app's SF Symbol filled with the signature
/// violet→azure brand gradient (CS-036). The menu-bar extra, the About pane, and
/// empty states all use the same symbol so the identity is consistent.
///
/// The underlying symbol (`Brand.symbolName`) is the single place that names the
/// app glyph, so the menu-bar icon and in-app marks never drift apart.
struct BrandMark: View {
    /// Point size of the symbol.
    var size: CGFloat = 48
    /// When false, the symbol uses the system tint instead of the brand
    /// gradient (e.g. where a flat monochrome glyph reads better).
    var gradient: Bool = true

    var body: some View {
        Image(systemName: Brand.symbolName)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(fill)
            .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        gradient ? AnyShapeStyle(Brand.Gradient.signature) : AnyShapeStyle(.tint)
    }
}

extension Brand {
    /// The single SF Symbol that represents Vitrine across the menu bar and the
    /// in-app brand marks. Change it here and every surface follows.
    static let symbolName = "camera.viewfinder"
}
