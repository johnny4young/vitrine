import SwiftUI

/// SwiftUI bridging for the UI-free background gradient models (VitrineCore
/// prerequisite): the models own the colors/stops/angle as value types, and these
/// adapters reconstruct the `SwiftUI.Color`/`LinearGradient`/`Gradient` the renderers and
/// editors draw with.
extension GradientPreset {
    /// Stop colors (top-leading → bottom-trailing) as `SwiftUI.Color`.
    var colors: [Color] { stopColors.map(\.color) }

    /// The preset as a SwiftUI diagonal linear gradient.
    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension BackgroundFit {
    /// The SwiftUI content mode this fit maps to.
    var contentMode: ContentMode {
        switch self {
        case .fill: .fill
        case .fit: .fit
        }
    }
}

extension CustomGradient {
    /// The stops sorted by location, mapped to SwiftUI `Gradient.Stop`s (the order
    /// `Gradient` expects).
    var sortedStops: [Gradient.Stop] {
        stopsSortedByLocation.map { Gradient.Stop(color: $0.color.color, location: $0.location) }
    }

    /// The unit-space start/end points for `angle`, mapping a direction in degrees onto
    /// the `0...1 × 0...1` view rectangle. `0°` points right, increasing clockwise (90°
    /// points down, matching screen coordinates).
    var endpoints: (start: UnitPoint, end: UnitPoint) {
        let radians = angle * .pi / 180
        let dx = cos(radians)
        let dy = sin(radians)
        // Center the axis and extend half a unit each way so the endpoints stay on-canvas.
        let start = UnitPoint(x: 0.5 - dx / 2, y: 0.5 - dy / 2)
        let end = UnitPoint(x: 0.5 + dx / 2, y: 0.5 + dy / 2)
        return (start, end)
    }

    /// The SwiftUI gradient for this configuration.
    var linearGradient: LinearGradient {
        let (start, end) = endpoints
        return LinearGradient(
            gradient: Gradient(stops: sortedStops), startPoint: start, endPoint: end)
    }
}
