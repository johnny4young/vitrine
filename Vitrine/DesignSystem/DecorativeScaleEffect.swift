import SwiftUI

/// Shared press/hover feedback, not functional preview scaling. Reduce Motion
/// keeps the control's size stable; its color, focus, and action remain available.
struct DecorativeScaleEffect: ViewModifier {
    /// The lift a swatch or theme chip takes under the pointer.
    static let hoverScale: CGFloat = 1.06

    let isActive: Bool
    let scale: CGFloat
    let reduceMotion: Bool
    var duration: Double = 0.12

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: duration), value: isActive)
    }
}
