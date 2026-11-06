import SwiftUI

extension View {
    /// Interpolates a decorative change unless Reduce Motion is on; the new state
    /// still applies immediately.
    func motionSensitiveAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionSensitiveAnimation(animation: animation, value: value))
    }
}

extension EnvironmentValues {
    /// Stands in for the system setting, whose environment value is read-only.
    @Entry var reduceMotionOverride: Bool?
}

/// Whether to remove motion: the system setting, unless a host overrides it.
@propertyWrapper
struct ReducesMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var system
    @Environment(\.reduceMotionOverride) private var override

    var wrappedValue: Bool { override ?? system }
}

private struct MotionSensitiveAnimation<V: Equatable>: ViewModifier {
    @ReducesMotion private var reduceMotion

    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
