import SwiftUI

/// The editor's annotation toolbar state and undo/redo history (CS-085/086).
extension EditorView {
    // MARK: - Annotation toolbar style (CS-085)

    /// The annotation currently selected in Select mode, if any.
    var selectedAnnotation: Annotation? {
        guard let id = selectedAnnotationID else { return nil }
        return settings.config.annotations.first { $0.id == id }
    }

    /// The toolbar color: the selected mark's color when one is selected, otherwise
    /// the new-draw default. Writing it updates whichever target is active.
    var annotationStyleColor: Binding<Color> {
        Binding(
            get: { selectedAnnotation?.color.color ?? newDrawColor },
            set: { newValue in
                newDrawColor = newValue
                if let id = selectedAnnotationID,
                    let index = settings.config.annotations.firstIndex(where: { $0.id == id })
                {
                    settings.config.annotations[index].color = RGBAColor(newValue)
                }
            })
    }

    /// The toolbar size slider, mirroring `annotationStyleColor`'s selected-vs-default
    /// targeting.
    var annotationStyleThickness: Binding<Double> {
        Binding(
            get: { selectedAnnotation?.thickness ?? newDrawThickness },
            set: { newValue in
                newDrawThickness = newValue
                if let id = selectedAnnotationID,
                    let index = settings.config.annotations.firstIndex(where: { $0.id == id })
                {
                    settings.config.annotations[index].thickness = newValue
                }
            })
    }

    /// Whether the color swatch applies to the current context (the selected mark, or
    /// the active draw tool). The selected-mark case derives from the same
    /// `AnnotationTool` policy as the draw-tool case, so a kind excluded there (blur,
    /// sticker, spotlight) never shows an inert swatch when selected — the ad hoc
    /// `!= .blur` check had drifted from the tool policy (deep-review finding).
    var annotationStyleUsesColor: Bool {
        if let selected = selectedAnnotation { return tool(for: selected.kind)?.usesColor ?? true }
        return activeTool.usesColor
    }

    /// Whether the size slider applies to the current context, from the same shared
    /// tool policy as `annotationStyleUsesColor`.
    var annotationStyleUsesThickness: Bool {
        if let selected = selectedAnnotation {
            return tool(for: selected.kind)?.usesThickness ?? true
        }
        return activeTool.usesThickness
    }

    /// The draw tool for a mark's kind — the single owner of the color/thickness
    /// policy, so selection and drawing can never disagree about a kind's controls.
    private func tool(for kind: Annotation.Kind) -> AnnotationTool? {
        AnnotationTool.allCases.first { $0.kind == kind }
    }

    // MARK: - Annotation undo/redo (CS-086)

    /// Whether the user is in an annotation context (a draw tool is active or a mark
    /// is selected). The undo/redo keyboard shortcut is gated on this so it never
    /// hijacks the code editor's own Cmd-Z while you are typing code.
    var annotationContextActive: Bool {
        activeTool != .select || selectedAnnotationID != nil
    }

    /// Snapshots the current marks just before a discrete edit, so it can be undone.
    func recordAnnotationUndo() {
        annotationRedo.removeAll()
        annotationUndo.append(settings.config.annotations)
        if annotationUndo.count > 60 { annotationUndo.removeFirst() }
    }

    func undoAnnotations() {
        guard !annotationUndo.isEmpty else { return }
        annotationRedo.append(settings.config.annotations)
        settings.config.annotations = annotationUndo.removeLast()
        selectedAnnotationID = nil
    }

    func redoAnnotations() {
        guard !annotationRedo.isEmpty else { return }
        annotationUndo.append(settings.config.annotations)
        settings.config.annotations = annotationRedo.removeLast()
        selectedAnnotationID = nil
    }
}
