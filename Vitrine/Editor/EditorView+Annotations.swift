import SwiftUI

/// The editor's annotation toolbar state and undo/redo history.
extension EditorView {
    // MARK: - Annotation toolbar style

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
    /// `!= .blur` check had drifted from the tool policy.
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

    // MARK: - Selection actions

    /// Copies the selected mark and selects the copy, so an already styled mark can
    /// be reused and placed precisely instead of being redrawn from scratch.
    func duplicateSelection() {
        guard let id = selectedAnnotationID,
            let original = settings.config.annotations.first(where: { $0.id == id })
        else { return }

        beginAnnotationEdit()
        let copy = original.duplicated(in: cardSize, counterNumber: nextCounterNumber)
        settings.config.annotations.append(copy)
        selectedAnnotationID = copy.id
        endAnnotationEdit()
    }

    /// One past the highest badge placed, so duplicating a counter continues the
    /// sequence instead of creating two badges with the same number.
    var nextCounterNumber: Int {
        (settings.config.annotations.filter { $0.kind == .counter }.map(\.number).max() ?? 0) + 1
    }

    /// Whether moving the selected mark to either edge of the visible draw order
    /// would change the canvas.
    var canBringSelectionToFront: Bool {
        selectedAnnotationID.map { settings.config.annotations.frontmostMove(for: $0) != nil }
            ?? false
    }

    var canSendSelectionToBack: Bool {
        selectedAnnotationID.map { settings.config.annotations.backmostMove(for: $0) != nil }
            ?? false
    }

    func bringSelectionToFront() { moveSelection(toFront: true) }
    func sendSelectionToBack() { moveSelection(toFront: false) }

    /// Guarded by the same conditions that enable the toolbar actions, so a no-op
    /// cannot consume an undo step.
    private func moveSelection(toFront front: Bool) {
        guard let id = selectedAnnotationID,
            front ? canBringSelectionToFront : canSendSelectionToBack
        else { return }
        beginAnnotationEdit()
        settings.config.annotations.moveMark(id, toFront: front)
        endAnnotationEdit()
    }

    /// Moves the selected mark by one arrow-key press: one canvas point normally or
    /// ten with Shift. Auto-repeat records only the initial undo snapshot.
    func nudgeSelection(_ key: KeyEquivalent, shift: Bool, isRepeat: Bool) -> Bool {
        guard let id = selectedAnnotationID,
            let index = settings.config.annotations.firstIndex(where: { $0.id == id })
        else { return false }

        let step = shift ? Annotation.coarseNudgeStep : Annotation.nudgeStep
        let delta: CGSize? =
            switch key {
            case .leftArrow: CGSize(width: -step, height: 0)
            case .rightArrow: CGSize(width: step, height: 0)
            case .upArrow: CGSize(width: 0, height: -step)
            case .downArrow: CGSize(width: 0, height: step)
            default: nil
            }
        guard let delta else { return false }

        if !isRepeat { beginAnnotationEdit() }
        settings.config.annotations[index].nudge(by: delta, in: cardSize)
        if !isRepeat { endAnnotationEdit() }
        return true
    }

    // MARK: - Annotation undo/redo

    /// Whether the user is in an annotation context (a draw tool is active or a mark
    /// is selected). The undo/redo keyboard shortcut is gated on this so it never
    /// hijacks the code editor's own Cmd-Z while you are typing code.
    var annotationContextActive: Bool {
        activeTool != .select || selectedAnnotationID != nil
    }

    /// Opens and closes an annotation edit transaction. History is recorded only if
    /// the marks actually changed, so no-op gestures preserve redo and cost no undo.
    func beginAnnotationEdit() {
        annotationHistory.beginEdit(settings.config.annotations)
    }

    func endAnnotationEdit() {
        annotationHistory.endEdit(current: settings.config.annotations)
    }

    func undoAnnotations() {
        guard let previous = annotationHistory.undo(current: settings.config.annotations)
        else { return }
        settings.config.annotations = previous
        selectedAnnotationID = nil
    }

    func redoAnnotations() {
        guard let next = annotationHistory.redo(current: settings.config.annotations)
        else { return }
        settings.config.annotations = next
        selectedAnnotationID = nil
    }
}
