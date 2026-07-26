import CoreGraphics

/// The editor window's column geometry.
///
/// The editor is three columns: a fixed code column, a preview stage, and the style
/// inspector. Which one absorbs spare width is the whole rule, and it is decided by
/// layout priority rather than by the frames alone.
///
/// The inspector was pinned at `inspectorMinWidth`, so it was the one column a bigger
/// window never helped: its theme and font strips clipped a chip mid-word on a 27-inch
/// display exactly as on a laptop. Widening its frame alone did nothing, because the
/// preview stage is unboundedly flexible *and* carried the higher priority, so it was
/// sized first and took every spare point — the inspector measured 302 pt even in a
/// 2400 pt window.
///
/// The order is now inverted: the **bounded** column is sized first, so it reaches
/// `inspectorMaxWidth`, and the **unbounded** stage absorbs everything past it. In every
/// window the editor can actually be opened at, that settles the inspector at its maximum
/// and leaves the stage far wider — the preview stays the dominant column, which is the
/// point of the cap.
///
/// Kept here rather than as inline literals so the rule is stated once and
/// `EditorLayoutTests` can drive real layout with the same numbers the window uses.
enum EditorLayout {
    /// The fixed width of the code column.
    static let codeColumnWidth: CGFloat = 280

    /// The width every inspector control was designed against, and the floor the column
    /// falls back to if a window is ever too narrow to afford more.
    static let inspectorMinWidth: CGFloat = 302

    /// The widest the inspector may grow, and — because it is sized before the stage — the
    /// width it settles at in practice. Chosen so the theme and font strips gain roughly
    /// one more chip, which is what turns a chip cut mid-word into a readable one, without
    /// the inspector approaching the stage's share.
    static let inspectorMaxWidth: CGFloat = 380

    /// The inspector's layout priority. Must exceed ``stageLayoutPriority``: whichever of
    /// the two is sized first wins the spare width, and the bounded column has to go
    /// first for its cap to mean anything.
    static let inspectorLayoutPriority: Double = 3

    /// The preview stage's layout priority — above the code column, below the inspector,
    /// so it is sized last and absorbs whatever remains.
    static let stageLayoutPriority: Double = 2
}
