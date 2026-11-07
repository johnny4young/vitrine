import AppKit
import SwiftUI
import VitrineDomain
import VitrineRendering

/// Comments pinned to diff lines: a text callout whose place comes from its line's row.
extension EditorView {
    /// Pins a new comment to the line under the code editor's caret and opens its field. A
    /// line that already has an attached comment reopens that one instead.
    func commentOnSelectedLine() {
        guard let row = Self.caretRow(in: editorWindow.value),
            settings.config.showsDiffRow(row)
        else { return }
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

    /// The caret's line in `window`'s code editor.
    static func caretRow(in window: NSWindow?) -> Int? {
        guard let textView = CodeFormatOperation.editorTextView(in: window) else { return nil }
        return caretRow(in: textView.string, at: textView.selectedRange().location)
    }

    /// The 1-based line holding UTF-16 offset `location` of `text`.
    static func caretRow(in text: String, at location: Int) -> Int {
        let utf16 = text.utf16
        let end = utf16.index(utf16.startIndex, offsetBy: min(max(location, 0), utf16.count))
        return utf16[..<end].reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    /// Each pinned comment's anchor, keyed by mark.
    static func commentAnchors(in annotations: [Annotation]) -> [UUID: DiffLineAnchor] {
        Dictionary(
            uniqueKeysWithValues: annotations.compactMap { annotation in
                annotation.lineAnchor.map { (annotation.id, $0) }
            })
    }
}

/// How the editing overlay treats pinned comments: a handle only where the canvas drew one,
/// at that place, and never moved off its line.
extension AnnotationEditingOverlay {
    static func isDrawn(_ annotation: Annotation, placed: [UUID: CGPoint]) -> Bool {
        annotation.lineAnchor == nil || placed[annotation.id] != nil
    }

    static func shown(_ annotation: Annotation, placed: [UUID: CGPoint]) -> Annotation {
        guard let point = placed[annotation.id] else { return annotation }
        var shown = annotation
        (shown.start, shown.end) = (point, point)
        return shown
    }

    static func stored(
        _ edited: Annotation, over current: Annotation, placed: [UUID: CGPoint]
    ) -> Annotation {
        guard placed[current.id] != nil else { return edited }
        var stored = edited
        (stored.start, stored.end) = (current.start, current.end)
        return stored
    }
}
