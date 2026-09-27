import SwiftUI

extension View {
    /// Interpolates a decorative change unless Reduce Motion is on; the new state
    /// still applies immediately.
    func motionSensitiveAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionSensitiveAnimation(animation: animation, value: value))
    }
}

private struct MotionSensitiveAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
