import SwiftUI

/// Draws the safe-area guide over the editor's preview (feature #20): a dashed
/// rectangle marking the margin platforms may crop or cover, plus a small chip with
/// the snippet's live line × column budget. Editor-only chrome — it is a sibling of
/// the annotation overlay in the stage, so the export (`SnapshotCanvas`) never sees it.
struct SafeAreaGuideOverlay: View {
    let canvasSize: CGSize
    let code: String
    /// Whether to draw the dashed crop-margin rect. Only meaningful when a destination
    /// preset pins an exact canvas (a content-hugging canvas has no fixed crop to
    /// guard); the budget chip is useful either way, so it always shows.
    let showsGuideRect: Bool

    var body: some View {
        let guide = SafeAreaGuide.guideRect(for: canvasSize)
        let budget = SafeAreaGuide.budget(for: code)
        ZStack(alignment: .bottomTrailing) {
            if showsGuideRect, guide.width > 0 {
                Rectangle()
                    .path(in: guide)
                    .stroke(
                        VitrineTokens.Accent.system.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }
            if budget.lines > 0 {
                // The live content budget: lines × widest column. Numbers-only by
                // design (locale-neutral), with a localized accessibility label.
                Text(verbatim: "\(budget.lines) × \(budget.columns)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(VitrineTokens.Accent.system.opacity(0.85))
                    )
                    .padding(8)
                    .accessibilityLabel("Lines by widest column")
                    .accessibilityValue(Text(verbatim: "\(budget.lines) × \(budget.columns)"))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
        .accessibilityIdentifier("editor-safe-area-overlay")
    }
}
