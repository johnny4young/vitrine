/// The annotation editor's undo/redo stacks, as a value type.
///
/// The editor snapshots the whole mark list before each discrete edit — a draw, a
/// move, a resize, a delete — and this holds those snapshots. It is deliberately
/// UI-free and pure so the stack semantics (coalescing, the depth cap, the redo
/// invalidation) are unit-testable without driving a view; `EditorView` owns one as
/// `@State` and calls it from the toolbar and the editing overlay.
///
/// Undo/redo here is *separate from the code editor's own* `UndoManager`: a mark and
/// a keystroke are different edit streams, and `EditorView.annotationContextActive`
/// decides which one ⌘Z drives.
struct AnnotationHistory {
    /// The deepest history kept. Each entry is a full mark-list snapshot; marks are
    /// small value types and a canvas holds a handful, so 60 steps of headroom costs
    /// far less than the surprise of a lost edit.
    static let depthLimit = 60

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var editStart: [Annotation]?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Starts a gesture or inline edit. The matching `endEdit` decides whether the
    /// canvas actually changed, so a click, zero-distance resize, or unchanged text
    /// field never creates a dead undo step or invalidates a valid redo branch.
    mutating func beginEdit(_ annotations: [Annotation]) {
        guard editStart == nil else { return }
        editStart = annotations
    }

    /// Commits the pending edit only when its visual state changed.
    mutating func endEdit(current: [Annotation]) {
        guard let before = editStart else { return }
        editStart = nil
        guard before != current else { return }
        record(before)
    }

    /// Snapshots `annotations` as the state to return to, and invalidates redo — the
    /// user branched off the old future, so replaying it would resurrect marks the
    /// new edit never knew about.
    ///
    /// Consecutive identical snapshots coalesce as a final defensive check for
    /// callers that record equivalent completed states.
    mutating func record(_ annotations: [Annotation]) {
        redoStack.removeAll()
        guard undoStack.last != annotations else { return }
        undoStack.append(annotations)
        if undoStack.count > Self.depthLimit { undoStack.removeFirst() }
    }

    /// The state to restore, with `current` pushed onto redo — or `nil` when there is
    /// nothing to undo, so the caller leaves the canvas untouched.
    mutating func undo(current: [Annotation]) -> [Annotation]? {
        endEdit(current: current)
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// The state to restore, with `current` pushed back onto undo — or `nil` when
    /// there is nothing to redo.
    mutating func redo(current: [Annotation]) -> [Annotation]? {
        endEdit(current: current)
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    /// Drops both stacks — used when the canvas's content is replaced wholesale (a new
    /// capture), where the old marks are not a state this canvas can return to.
    mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
        editStart = nil
    }
}
