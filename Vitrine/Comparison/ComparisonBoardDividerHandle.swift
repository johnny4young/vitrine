import SwiftUI
import VitrineRendering

/// Moves the divider drawn into the board preview. The line itself is in the image, so this
/// adds only input and a knob, and a still export carries no control it cannot honor.
struct ComparisonBoardDividerHandle: View {
    @Binding var percent: Int
    /// What the preview image draws, in board points.
    let wipe: ComparisonBoardComposer.Wipe
    let scale: CGFloat
    let onDrag: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.clear
            knob
                .position(
                    x: (wipe.dividerX - wipe.area.minX) * scale,
                    y: wipe.area.height * scale / 2)
        }
        .frame(width: wipe.area.width * scale, height: wipe.area.height * scale)
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { value in
                onDrag()
                percent = wipe.percent(atX: wipe.area.minX + value.location.x / scale)
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Divider position")
        .accessibilityValue(Text(verbatim: "\(percent)%"))
        .accessibilityHint("Drag, or use the arrow keys, to move the divider")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(by: 1)
            case .decrement: nudge(by: -1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("comparison-board-divider")
        // `.activate` keeps a click from taking focus, like the other stage handles.
        .focusable(interactions: .activate)
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            nudge(by: press.key == .leftArrow ? -1 : 1)
            return .handled
        }
        .position(x: wipe.area.midX * scale, y: wipe.area.midY * scale)
    }

    private var knob: some View {
        Image(systemName: "arrow.left.and.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black.opacity(0.8))
            .frame(width: 24, height: 24)
            .background(.white, in: Circle())
            .overlay {
                if isFocused {
                    Circle().strokeBorder(VitrineTokens.Accent.system, lineWidth: 2)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
    }

    private func nudge(by delta: Int) {
        percent = ComparisonBoard.clampedDivider(percent + delta)
    }
}
