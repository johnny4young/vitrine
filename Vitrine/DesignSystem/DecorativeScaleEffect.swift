import SwiftUI

/// Shared press/hover feedback, not functional preview scaling. Reduce Motion
/// keeps the control's size stable; its color, focus, and action remain available.
struct DecorativeScaleEffect: ViewModifier {
    let isActive: Bool
    let scale: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: isActive)
    }
}
