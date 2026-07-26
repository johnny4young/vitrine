import AppKit
import SwiftUI
import Testing

@testable import Vitrine

/// The editor's column geometry.
///
/// These drive **real SwiftUI layout** and measure the width the inspector actually
/// resolves to. That distinction is the point of the suite: an earlier version asserted
/// only relationships between the constants — that the cap exceeded the floor, that the
/// floor was 302 — which held perfectly while the shipped window still pinned the
/// inspector at 302 pt in a 2400 pt window, because `previewStage` carried the higher
/// layout priority and was sized first. Constants cannot catch that; a laid-out view can.
@MainActor
@Suite("Editor column layout")
struct EditorLayoutTests {
    /// An AppKit-backed probe whose frame is assigned by SwiftUI during the host's
    /// synchronous layout pass. Reading this view avoids depending on `onAppear`, which
    /// is scheduled by SwiftUI and is not guaranteed to run before
    /// `layoutSubtreeIfNeeded()` returns.
    private final class WidthProbeView: NSView {}

    private struct WidthProbe: NSViewRepresentable {
        let view: WidthProbeView

        func makeNSView(context: Context) -> WidthProbeView { view }
        func updateNSView(_ nsView: WidthProbeView, context: Context) {}
    }

    /// Lays out the editor's three-column arrangement at `windowWidth` and returns the
    /// inspector's resolved width.
    ///
    /// The columns are stand-ins for content, but the modifiers that decide the split —
    /// the fixed code column, the bounded inspector frame, and both layout priorities —
    /// are the values `EditorView` applies, read from `EditorLayout` rather than repeated
    /// here, so the test cannot drift from the window on the numbers that matter.
    private func inspectorWidth(atWindowWidth windowWidth: CGFloat) -> CGFloat {
        let probe = WidthProbeView()

        let columns = HStack(spacing: 0) {
            Color.clear
                .frame(width: EditorLayout.codeColumnWidth)
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(EditorLayout.stageLayoutPriority)
            Color.clear
                .frame(
                    minWidth: EditorLayout.inspectorMinWidth,
                    maxWidth: EditorLayout.inspectorMaxWidth
                )
                .layoutPriority(EditorLayout.inspectorLayoutPriority)
                .background(WidthProbe(view: probe))
        }

        let host = NSHostingView(rootView: columns)
        host.frame = NSRect(x: 0, y: 0, width: windowWidth, height: 800)
        host.layoutSubtreeIfNeeded()
        return probe.frame.width
    }

    /// The regression: spare width has to reach the inspector at all.
    @Test func theInspectorWidensInsteadOfStayingAtItsFloor() {
        let width = inspectorWidth(atWindowWidth: 2_400)
        #expect(
            width > EditorLayout.inspectorMinWidth,
            "a 2400 pt window left the inspector at \(width) pt — the stage took the spare width")
        #expect(width == EditorLayout.inspectorMaxWidth)
    }

    /// The cap is the half of the rule that is easy to drop. Without it the inspector
    /// keeps widening on an ultrawide display, stretching sliders across empty space and
    /// crowding out the preview — the thing being styled.
    @Test func theInspectorStopsAtItsCapOnAnUltrawideWindow() {
        #expect(inspectorWidth(atWindowWidth: 5_120) == EditorLayout.inspectorMaxWidth)
    }

    /// Growth must not come out of the preview's share: the stage stays the widest column
    /// even at the narrowest window the editor opens at.
    @Test func theStageStaysTheWidestColumn() {
        let narrowest: CGFloat = 1_180
        let inspector = inspectorWidth(atWindowWidth: narrowest)
        let stage = narrowest - EditorLayout.codeColumnWidth - inspector
        #expect(stage > inspector)
    }

    /// The ordering rule itself, stated where it can be read: the bounded column must be
    /// sized before the unbounded one, or its cap means nothing.
    @Test func theBoundedColumnIsSizedBeforeTheUnboundedOne() {
        #expect(EditorLayout.inspectorLayoutPriority > EditorLayout.stageLayoutPriority)
    }
}
