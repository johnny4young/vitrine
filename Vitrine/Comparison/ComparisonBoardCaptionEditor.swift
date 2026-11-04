import SwiftUI
import VitrineRendering

/// The fields that open over a caption drawn into the board preview.
struct ComparisonBoardCaptionEditor: View {
    static let height: CGFloat = 76

    let captureID: UUID
    let index: Int
    @Binding var label: String
    @Binding var detail: String
    let onEnd: (UUID) -> Void

    var body: some View {
        // Keyed so a new caption gets fresh fields and focus, never the last one's field editor.
        Fields(
            captureID: captureID, index: index, label: $label, detail: $detail, onEnd: onEnd
        )
        .id(captureID)
    }

    private struct Fields: View {
        private enum Field { case label, detail }

        let captureID: UUID
        let index: Int
        @Binding var label: String
        @Binding var detail: String
        let onEnd: (UUID) -> Void

        @FocusState private var focus: Field?
        @State private var hasSettled = false

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.md, style: .continuous)
        }

        var body: some View {
            VStack(spacing: VitrineTokens.Spacing.xs) {
                TextField("Label", text: $label)
                    .focused($focus, equals: .label)
                    .accessibilityIdentifier("comparison-board-inline-label-\(index)")
                TextField("Optional detail", text: $detail)
                    .focused($focus, equals: .detail)
                    .accessibilityIdentifier("comparison-board-inline-detail-\(index)")
            }
            .multilineTextAlignment(.center)
            .onSubmit { onEnd(captureID) }
            .onExitCommand { onEnd(captureID) }
            .padding(VitrineTokens.Spacing.xs)
            .frame(height: ComparisonBoardCaptionEditor.height)
            .background(VitrineTokens.Surface.window, in: shape)
            .overlay(
                shape.strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
            )
            .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
            .contentShape(Rectangle())
            .onTapGesture {}
            .task {
                // A request made as the field appears can be dropped, and the outgoing caption's
                // field leaves on its own schedule, so ask again until focus lands.
                for _ in 0..<10 where focus == nil {
                    await Task.yield()
                    focus = .label
                    try? await Task.sleep(for: .milliseconds(30))
                }
                hasSettled = true
            }
            .onChange(of: focus) { previous, current in
                if hasSettled, previous != nil, current == nil { onEnd(captureID) }
            }
        }
    }
}
