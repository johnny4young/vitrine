import SwiftUI

/// A part of the rendered canvas an editor can map a pointer to.
public enum CanvasPart: Hashable, Sendable {
    case card, chrome, header, code
}

/// Where the canvas laid out its parts. Preferences never reach the rendered pixels.
public struct CanvasPartAnchorsKey: PreferenceKey {
    public static var defaultValue: [CanvasPart: Anchor<CGRect>] { [:] }

    /// The first report wins, so a blurred or cross-fading copy cannot move a part.
    public static func reduce(
        value: inout [CanvasPart: Anchor<CGRect>], nextValue: () -> [CanvasPart: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { current, _ in current }
    }
}

extension View {
    /// Adds to what the subtree reported: the card holds the other parts.
    func canvasPart(_ part: CanvasPart) -> some View {
        transformAnchorPreference(key: CanvasPartAnchorsKey.self, value: .bounds) {
            $0[part] = $1
        }
    }
}
