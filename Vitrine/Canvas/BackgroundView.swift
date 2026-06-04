import SwiftUI

/// Renders the snapshot background: solid color, gradient, or transparent (CS-005).
struct BackgroundView: View {
    let style: BackgroundStyle

    var body: some View {
        switch style {
        case .solid(let color):
            color
        case .gradient(let preset):
            preset.gradient
        case .transparent:
            // Exports as real transparency; clear in the preview.
            Color.clear
        }
    }
}
