import CoreGraphics

/// The editor window's column geometry.
///
/// The editor is three columns: a fixed code column, a preview stage that takes what is
/// left, and the style inspector. The inspector used to be pinned at its minimum width,
/// which made it the one column that never benefited from a larger window — its theme and
/// font strips clipped a chip mid-word on a 27-inch display exactly as they did on a
/// laptop, because every extra point went to the preview.
///
/// It now takes a share of the extra space up to `inspectorMaxWidth`. The cap matters as
/// much as the growth: without it the inspector would keep widening on an ultrawide
/// display, stretching sliders and toggles across empty space and pushing the preview —
/// the thing being styled — out of comfortable view.
///
/// Kept here rather than as inline literals so the rule is stated once and a test can
/// assert it without building a window.
enum EditorLayout {
    /// The fixed width of the code column.
    static let codeColumnWidth: CGFloat = 280

    /// The width the inspector holds at its most cramped, and its ideal at small window
    /// sizes: the width every control in it was designed against.
    static let inspectorMinWidth: CGFloat = 302

    /// The widest the inspector may grow. Chosen so the two strips that clip — themes and
    /// fonts — gain roughly one more chip, which is what turns a chip cut mid-word into a
    /// readable one, without the inspector approaching the preview's share.
    static let inspectorMaxWidth: CGFloat = 380
}
