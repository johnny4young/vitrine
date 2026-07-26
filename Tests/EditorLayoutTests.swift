import CoreGraphics
import Testing

@testable import Vitrine

/// The editor's column geometry.
///
/// The inspector was pinned at one width, so it was the only column a bigger window never
/// helped: its theme and font strips clipped a chip mid-word on a large display exactly as
/// on a laptop, because every extra point went to the preview. These hold the rule that
/// replaced that — grow, but not without a ceiling.
@Suite("Editor column layout")
struct EditorLayoutTests {
    @Test func theInspectorCanGrowBeyondItsDesignedWidth() {
        #expect(EditorLayout.inspectorMaxWidth > EditorLayout.inspectorMinWidth)
    }

    /// The minimum is the width every inspector control was designed against, so growth
    /// must start there rather than below it.
    @Test func theInspectorNeverShrinksBelowItsDesignedWidth() {
        #expect(EditorLayout.inspectorMinWidth == 302)
    }

    /// The cap is the half of the rule that is easy to drop. Without it the inspector
    /// keeps widening on an ultrawide display, stretching sliders across empty space and
    /// crowding out the preview — the thing being styled.
    @Test func theInspectorStaysNarrowerThanAUsablePreview() {
        // At the narrowest window the editor is used at, a fully grown inspector plus the
        // code column must still leave the preview the widest column.
        let smallestUsableWindow: CGFloat = 1_180
        let preview =
            smallestUsableWindow - EditorLayout.codeColumnWidth - EditorLayout.inspectorMaxWidth
        #expect(preview > EditorLayout.inspectorMaxWidth)
    }
}
