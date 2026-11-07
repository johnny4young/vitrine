import AppKit
import SwiftUI
import VitrineDomain
import VitrineRendering

/// Comments pinned to diff lines: a text callout whose place comes from its line's row.
extension EditorView {
    /// Pins a new comment to the line under the code editor's caret and opens its field. A
    /// line that already has an attached comment reopens that one instead.
    func commentOnSelectedLine() {
        guard settings.style.diffOptionsApply, !settings.documentIsEmpty,
            let textView = CodeFormatOperation.editorTextView(in: editorWindow.value)
        else { return }
        let row = Self.caretRow(in: textView.string, at: textView.selectedRange().location)
        let anchor = DiffLineAnchor.anchor(
            row: row, in: DiffLayoutCache.shared.document(for: settings.documentCode))
        if let existing = settings.style.annotations.first(where: { $0.lineAnchor == anchor }) {
            beginAnnotationEdit()
            selectedAnnotationID = existing.id
            editingAnnotationID = existing.id
            return
        }
        // The edit stays open until the inline field closes, as for a drawn callout.
        beginAnnotationEdit()
        let thickness = max(Annotation.thicknessRange.lowerBound, settings.style.fontSize / 4)
        var comment = Annotation.make(
            kind: .text, from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.5, y: 0.5),
            color: RGBAColor(newDrawColor), thickness: thickness)
        comment.lineAnchor = anchor
        settings.style.annotations.append(comment)
        selectedAnnotationID = comment.id
        editingAnnotationID = comment.id
    }

    /// The 1-based line holding UTF-16 offset `location` of `text`.
    static func caretRow(in text: String, at location: Int) -> Int {
        let utf16 = text.utf16
        let end = utf16.index(utf16.startIndex, offsetBy: min(max(location, 0), utf16.count))
        return utf16[..<end].reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    /// Moves each pinned comment's cached point to where the canvas drew it, so its handle,
    /// selection and inline field sit on the drawn mark.
    func syncDiffCommentPositions() {
        var annotations = settings.style.annotations
        var changed = false
        for index in annotations.indices where annotations[index].lineAnchor != nil {
            guard let point = diffCommentPositions[annotations[index].id],
                abs(annotations[index].start.x - point.x) > 0.0001
                    || abs(annotations[index].start.y - point.y) > 0.0001
            else { continue }
            annotations[index].start = point
            annotations[index].end = point
            changed = true
        }
        if changed { settings.style.annotations = annotations }
    }
}
