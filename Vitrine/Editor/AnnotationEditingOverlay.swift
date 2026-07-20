import SwiftUI

/// The interactive editing layer drawn over the live preview.
///
/// It does **not** draw the annotations themselves — `SnapshotCanvas` does, so the
/// editor preview and the exported image always agree. It adds the editor-side
/// chrome and interaction:
///
/// - With a **drawing tool** active, a full-canvas layer turns a click-drag into a
///   new mark (a click places a text/counter), so marks are painted with the cursor
///   the way CleanShot works — not auto-dropped.
/// - With the **Select** tool, each mark gets a grab/move hit area, a dashed
///   selection outline, and resize handles.
///
/// It lives inside the preview's `scaleEffect`, sharing the canvas coordinate space,
/// so a pointer drag maps straight to normalized annotation coordinates.
struct AnnotationEditingOverlay: View {
    @Bindable var settings: AppSettings
    @Binding var selection: UUID?
    /// The text callout being edited inline, if any — its handle is hidden and a
    /// focused field is shown over it instead .
    @Binding var editingAnnotationID: UUID?
    let canvasSize: CGSize
    let activeTool: AnnotationTool
    let drawColor: Color
    let drawThickness: Double
    /// The emoji the sticker tool places; unused by every other tool.
    var stickerGlyph: String = AnnotationTool.stickerChoices[0]
    /// Called once at the start of each discrete edit (draw, move, resize, delete) so
    /// the editor can snapshot the annotations for undo.
    let onBeginEdit: () -> Void
    /// Closes the edit transaction after the mutation so unchanged interactions do
    /// not create an undo entry or discard redo.
    let onEndEdit: () -> Void

    var body: some View {
        ZStack {
            if editingAnnotationID == nil {
                if let kind = activeTool.kind {
                    // Draw mode: a click-drag paints a new mark. It sits *below* the
                    // handles, so the just-drawn (selected) mark stays editable.
                    DrawingLayer(
                        kind: kind, color: drawColor, thickness: drawThickness,
                        canvasSize: canvasSize,
                        nextCounterNumber: nextCounterNumber,
                        stickerGlyph: stickerGlyph,
                        onBeginDraw: onBeginEdit,
                        onEndDraw: onEndEdit,
                        onCommit: { annotation in
                            settings.config.annotations.append(annotation)
                            selection = annotation.id
                            // A new text callout opens straight into its inline field.
                            if annotation.kind == .text { editingAnnotationID = annotation.id }
                        })
                } else if selection != nil {
                    // Select mode: tapping empty space clears the selection.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { selection = nil }
                }
            } else {
                // While editing, a click anywhere outside the field commits the edit.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { endTextEditing() }
            }
            // Handles: every mark in Select mode, and the selected mark even while a
            // draw tool is active — so you can move/resize/delete what you just drew
            // without leaving the tool (CleanShot-style). The mark being
            // text-edited shows only its field, so its handle is hidden.
            ForEach(settings.config.annotations) { annotation in
                let isSelected = selection == annotation.id
                if editingAnnotationID != annotation.id,
                    activeTool == .select || isSelected,
                    let binding = binding(for: annotation.id)
                {
                    AnnotationHandle(
                        annotation: binding,
                        isSelected: isSelected,
                        canvasSize: canvasSize,
                        onBeginEdit: onBeginEdit,
                        onEndEdit: onEndEdit,
                        onSelect: { selection = annotation.id },
                        onEdit: annotation.kind == .text
                            ? { beginTextEditing(annotation.id) } : nil,
                        onDelete: { delete(annotation.id) })
                }
            }
            // The focused inline field for the text callout being edited.
            if let id = editingAnnotationID, let binding = binding(for: id),
                binding.wrappedValue.kind == .text
            {
                TextAnnotationEditor(
                    annotation: binding, canvasSize: canvasSize, onCommit: endTextEditing)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    /// The next badge number — one past the highest counter currently placed.
    private var nextCounterNumber: Int {
        (settings.config.annotations.filter { $0.kind == .counter }.map(\.number).max() ?? 0) + 1
    }

    /// An id-keyed binding into the annotations array, robust to reordering.
    private func binding(for id: UUID) -> Binding<Annotation>? {
        guard settings.config.annotations.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                settings.config.annotations.first(where: { $0.id == id })
                    ?? Annotation(kind: .text, start: .zero, end: .zero)
            },
            set: { newValue in
                if let index = settings.config.annotations.firstIndex(where: { $0.id == id }) {
                    settings.config.annotations[index] = newValue
                }
            })
    }

    /// Opens a text callout's inline field, snapshotting first so the whole edit is a
    /// single undo step.
    private func beginTextEditing(_ id: UUID) {
        onBeginEdit()
        selection = id
        editingAnnotationID = id
    }

    /// Leaves inline editing, dropping a callout that was never given content so no
    /// invisible mark is left behind. Idempotent — safe to call from both `onSubmit`
    /// and the focus-loss handler.
    private func endTextEditing() {
        guard let id = editingAnnotationID else { return }
        if settings.config.annotations.first(where: { $0.id == id })?.isBlankText == true {
            settings.config.annotations.removeAll { $0.id == id }
            if selection == id { selection = nil }
        }
        editingAnnotationID = nil
        onEndEdit()
    }

    private func delete(_ id: UUID) {
        onBeginEdit()
        settings.config.annotations.removeAll { $0.id == id }
        if selection == id { selection = nil }
        if editingAnnotationID == id { editingAnnotationID = nil }
        onEndEdit()
    }
}

/// The full-canvas drawing surface for a single active tool: a click-drag paints a
/// shape (with a live preview), a click places a text/counter.
private struct DrawingLayer: View {
    let kind: Annotation.Kind
    let color: Color
    let thickness: Double
    let canvasSize: CGSize
    let nextCounterNumber: Int
    var stickerGlyph: String = ""
    let onBeginDraw: () -> Void
    let onEndDraw: () -> Void
    let onCommit: (Annotation) -> Void

    /// The in-progress drag (canvas points), for the live preview.
    @State private var drag: (start: CGPoint, end: CGPoint)?

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(drawGesture)

            // Live preview of the shape being dragged.
            if let drag, !kind.isPointPlaced {
                AnnotationMarkView(
                    annotation: makeAnnotation(from: drag.start, to: drag.end), size: canvasSize
                )
                .allowsHitTesting(false)
                .opacity(0.9)
            }
        }
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !kind.isPointPlaced {
                    drag = (value.startLocation, value.location)
                }
            }
            .onEnded { value in
                defer { drag = nil }
                if kind.isPointPlaced {
                    onBeginDraw()
                    onCommit(makeAnnotation(from: value.location, to: value.location))
                    onEndDraw()
                } else {
                    // Ignore an accidental click (no real drag) so a stray tap never
                    // leaves a zero-size shape behind.
                    let distance = hypot(
                        value.location.x - value.startLocation.x,
                        value.location.y - value.startLocation.y)
                    guard distance > 6 else { return }
                    onBeginDraw()
                    onCommit(makeAnnotation(from: value.startLocation, to: value.location))
                    onEndDraw()
                }
            }
    }

    private func makeAnnotation(from start: CGPoint, to end: CGPoint) -> Annotation {
        Annotation.make(
            kind: kind, from: normalize(start), to: normalize(end), color: RGBAColor(color),
            thickness: thickness, number: kind == .counter ? nextCounterNumber : 0,
            text: kind == .sticker ? stickerGlyph : "")
    }

    private func normalize(_ point: CGPoint) -> CGPoint {
        Annotation.clampNormalized(
            CGPoint(
                x: point.x / max(canvasSize.width, 1), y: point.y / max(canvasSize.height, 1)))
    }
}

/// One annotation's Select-mode chrome: a grab/move hit area, a dashed outline, and
/// (for shapes) resize handles. Geometry is in canvas points.
private struct AnnotationHandle: View {
    @Binding var annotation: Annotation
    let isSelected: Bool
    let canvasSize: CGSize
    let onBeginEdit: () -> Void
    let onEndEdit: () -> Void
    let onSelect: () -> Void
    /// Re-opens a text callout's inline field on double-click; `nil` for kinds that
    /// have no editable text.
    let onEdit: (() -> Void)?
    let onDelete: () -> Void

    @State private var dragOrigin: Annotation?
    @State private var isResizing = false

    private var accent: Color { VitrineTokens.Accent.base }
    private var startPoint: CGPoint { annotation.startPoint(in: canvasSize) }
    private var endPoint: CGPoint { annotation.endPoint(in: canvasSize) }
    private var rect: CGRect { annotation.rect(in: canvasSize) }

    /// Marks whose geometry is a stroke between two free points: their grab area and
    /// selection outline follow the span, not a rect. The curved arrow's arc and the
    /// measure's shaft both live along (near) the start→end line, so line hit-testing
    /// serves them; leaving a kind out of both groups drops it into the point-placed
    /// fallback — a small box at `start` — which broke select/move for the newer kinds.
    private var isLineLike: Bool {
        annotation.kind == .arrow || annotation.kind == .line
            || annotation.kind == .curvedArrow || annotation.kind == .measure
    }
    /// Marks whose geometry is the spanned rectangle. A spotlight is a region exactly
    /// like blur, so it selects and resizes by its rect.
    private var isBoxLike: Bool {
        annotation.kind == .rectangle || annotation.kind == .highlighter
            || annotation.kind == .blur || annotation.kind == .spotlight
    }

    var body: some View {
        ZStack {
            if isSelected { selectionChrome }
            bodyHitArea
            if isSelected && !annotation.kind.isPointPlaced { resizeHandles }
            if isSelected { deleteButton }
        }
    }

    /// A small delete badge at the selection's top-right — the primary way to remove
    /// a mark now that the inspector list is gone.
    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
                .font(.system(size: 17))
        }
        .buttonStyle(.plain)
        .position(deleteAnchor)
        .accessibilityLabel("Delete annotation")
        .accessibilityIdentifier("annotation-delete")
    }

    private var deleteAnchor: CGPoint {
        let box =
            isLineLike
            ? CGRect(
                x: min(startPoint.x, endPoint.x), y: min(startPoint.y, endPoint.y),
                width: abs(startPoint.x - endPoint.x), height: abs(startPoint.y - endPoint.y))
            : selectionRect
        return CGPoint(
            x: min(box.maxX + 4, canvasSize.width - 10),
            y: max(box.minY - 4, 10))
    }

    // MARK: Grab / move

    @ViewBuilder
    private var bodyHitArea: some View {
        let base = Color.clear
            .frame(width: hitSize.width, height: hitSize.height)
            .contentShape(Rectangle())
            .rotationEffect(isLineLike ? .radians(shaftAngle) : .zero)
            .position(hitCenter)
        if let onEdit {
            // A double-click re-opens a text callout's field; the single-click select is
            // declared after so it yields to the double-click.
            base
                .onTapGesture(count: 2) { onEdit() }
                .onTapGesture { onSelect() }
                .gesture(moveGesture)
        } else {
            base
                .onTapGesture { onSelect() }
                .gesture(moveGesture)
        }
    }

    private var hitSize: CGSize {
        if isLineLike {
            let length = max(hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y), 1)
            return CGSize(width: length, height: max(26, annotation.thickness + 18))
        }
        if isBoxLike {
            return CGSize(width: max(rect.width, 24), height: max(rect.height, 24))
        }
        // Point-placed: a generous box around the anchor.
        let span = annotation.kind == .counter ? max(40, annotation.thickness * 4 + 16) : 120
        return CGSize(width: span, height: annotation.kind == .counter ? span : 44)
    }

    private var hitCenter: CGPoint {
        if isLineLike {
            return CGPoint(x: (startPoint.x + endPoint.x) / 2, y: (startPoint.y + endPoint.y) / 2)
        }
        if isBoxLike { return CGPoint(x: rect.midX, y: rect.midY) }
        return startPoint
    }

    private var shaftAngle: Double {
        atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragOrigin == nil {
                    onBeginEdit()
                    dragOrigin = annotation
                    onSelect()
                }
                guard let origin = dragOrigin else { return }
                var moved = origin
                moved.nudge(by: value.translation, in: canvasSize)
                annotation = moved
            }
            .onEnded { _ in
                dragOrigin = nil
                onEndEdit()
            }
    }

    // MARK: Selection outline

    @ViewBuilder
    private var selectionChrome: some View {
        if isLineLike {
            Path { path in
                path.move(to: startPoint)
                path.addLine(to: endPoint)
            }
            .stroke(accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        } else {
            let outline = selectionRect
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(accent.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .frame(width: outline.width, height: outline.height)
                .position(x: outline.midX, y: outline.midY)
        }
    }

    private var selectionRect: CGRect {
        if isBoxLike { return rect }
        // Point-placed: a box around the anchor.
        let span = annotation.kind == .counter ? max(40, annotation.thickness * 4 + 16) : 120
        let h = annotation.kind == .counter ? span : 44
        return CGRect(x: startPoint.x - span / 2, y: startPoint.y - h / 2, width: span, height: h)
    }

    // MARK: Resize handles (shapes only)

    @ViewBuilder
    private var resizeHandles: some View {
        handleDot(at: startPoint, gesture: resizeGesture(\.start))
        handleDot(at: endPoint, gesture: resizeGesture(\.end))
    }

    private func handleDot<G: Gesture>(at point: CGPoint, gesture: G) -> some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(accent, lineWidth: 2))
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            .contentShape(Circle())
            .position(point)
            .gesture(gesture)
    }

    private func resizeGesture(_ keyPath: WritableKeyPath<Annotation, CGPoint>) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isResizing {
                    isResizing = true
                    onBeginEdit()
                }
                onSelect()
                annotation[keyPath: keyPath] = Annotation.clampNormalized(
                    CGPoint(
                        x: value.location.x / max(canvasSize.width, 1),
                        y: value.location.y / max(canvasSize.height, 1)))
            }
            .onEnded { _ in
                isResizing = false
                onEndEdit()
            }
    }
}

/// The focused inline field for editing a text callout in place .
///
/// It mirrors `TextMark`'s font, color, pill, and center anchor so editing is WYSIWYG,
/// and `SnapshotCanvas` blanks the same mark while this is up (see `previewConfig`), so
/// the field is the only text drawn. Committing on Return / Escape / focus-loss keeps
/// non-empty content; an empty field is dropped by the overlay.
private struct TextAnnotationEditor: View {
    @Binding var annotation: Annotation
    let canvasSize: CGSize
    let onCommit: () -> Void

    @FocusState private var isFocused: Bool

    /// Matches `TextMark.fontSize` so the field and the rendered callout are the same size.
    private var fontSize: CGFloat { max(12, annotation.thickness * 4) }

    var body: some View {
        TextField("Annotation text", text: $annotation.text, prompt: Text("Note"))
            .textFieldStyle(.plain)
            .labelsHidden()
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(annotation.color.color)
            .multilineTextAlignment(.center)
            .fixedSize()
            .padding(.horizontal, fontSize * 0.5)
            .padding(.vertical, fontSize * 0.28)
            .background(
                RoundedRectangle(cornerRadius: fontSize * 0.5, style: .continuous)
                    .fill(Color.black.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: fontSize * 0.5, style: .continuous)
                    .strokeBorder(VitrineTokens.Accent.base, lineWidth: 1.5)
            )
            .position(annotation.startPoint(in: canvasSize))
            .focused($isFocused)
            // `.task` (MainActor, post-appearance) focuses more reliably than setting
            // `@FocusState` straight from `.onAppear`.
            .task { isFocused = true }
            .onSubmit(onCommit)
            .onExitCommand(perform: onCommit)
            .onChange(of: isFocused) { _, focused in
                if !focused { onCommit() }
            }
            .accessibilityIdentifier("annotation-text-field")
    }
}
