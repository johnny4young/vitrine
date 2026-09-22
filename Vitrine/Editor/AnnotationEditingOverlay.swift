import SwiftUI
import VitrineDomain
import VitrineRendering

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
                            settings.style.annotations.append(annotation)
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
            ForEach(settings.style.annotations) { annotation in
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
        (settings.style.annotations.filter { $0.kind == .counter }.map(\.number).max() ?? 0) + 1
    }

    /// An id-keyed binding into the annotations array, robust to reordering.
    private func binding(for id: UUID) -> Binding<Annotation>? {
        guard settings.style.annotations.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                settings.style.annotations.first(where: { $0.id == id })
                    ?? Annotation(kind: .text, start: .zero, end: .zero)
            },
            set: { newValue in
                if let index = settings.style.annotations.firstIndex(where: { $0.id == id }) {
                    settings.style.annotations[index] = newValue
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
        if settings.style.annotations.first(where: { $0.id == id })?.isBlankText == true {
            settings.style.annotations.removeAll { $0.id == id }
            if selection == id { selection = nil }
        }
        editingAnnotationID = nil
        onEndEdit()
    }

    private func delete(_ id: UUID) {
        onBeginEdit()
        settings.style.annotations.removeAll { $0.id == id }
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
                guard
                    AnnotationInteractionGeometry.shouldCommit(
                        kind: kind, from: value.startLocation, to: value.location)
                else { return }
                onBeginDraw()
                let start = kind.isPointPlaced ? value.location : value.startLocation
                onCommit(makeAnnotation(from: start, to: value.location))
                onEndDraw()
            }
    }

    private func makeAnnotation(from start: CGPoint, to end: CGPoint) -> Annotation {
        Annotation.make(
            kind: kind, from: normalize(start), to: normalize(end), color: RGBAColor(color),
            thickness: thickness, number: kind == .counter ? nextCounterNumber : 0,
            text: kind == .sticker ? stickerGlyph : "")
    }

    private func normalize(_ point: CGPoint) -> CGPoint {
        AnnotationInteractionGeometry.normalize(point, in: canvasSize)
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
    private var geometry: AnnotationInteractionGeometry {
        AnnotationInteractionGeometry(annotation: annotation, canvasSize: canvasSize)
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
            geometry.isLineLike
            ? CGRect(
                x: min(geometry.start.x, geometry.end.x), y: min(geometry.start.y, geometry.end.y),
                width: abs(geometry.start.x - geometry.end.x),
                height: abs(geometry.start.y - geometry.end.y))
            : geometry.selectionRect
        return CGPoint(
            x: min(box.maxX + 4, canvasSize.width - 10),
            y: max(box.minY - 4, 10))
    }

    // MARK: Grab / move

    @ViewBuilder
    private var bodyHitArea: some View {
        let base = Color.clear
            .frame(width: geometry.hitSize.width, height: geometry.hitSize.height)
            .contentShape(Rectangle())
            .rotationEffect(geometry.isLineLike ? .radians(geometry.shaftAngle) : .zero)
            .position(geometry.hitCenter)
        if let onEdit {
            // A double-click re-opens a text callout's field; the single-click select is
            // declared after so it yields to the double-click.
            base
                .onTapGesture(count: 2) { onEdit() }
                .onTapGesture { onSelect() }
                .gesture(moveGesture)
        } else {
            base
                // A short move and a click are mutually exclusive, not competing
                // recognizers. Give a real drag first chance, then let a click select.
                .gesture(
                    moveGesture.exclusively(before: TapGesture().onEnded { onSelect() })
                )
        }
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
        if geometry.isLineLike {
            Path { path in
                path.move(to: geometry.start)
                path.addLine(to: geometry.end)
            }
            .stroke(accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        } else {
            let outline = geometry.selectionRect
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(accent.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .frame(width: outline.width, height: outline.height)
                .position(x: outline.midX, y: outline.midY)
        }
    }

    // MARK: Resize handles (shapes only)

    @ViewBuilder
    private var resizeHandles: some View {
        handleDot(at: geometry.start, gesture: resizeGesture(\.start))
        handleDot(at: geometry.end, gesture: resizeGesture(\.end))
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
                annotation[keyPath: keyPath] = AnnotationInteractionGeometry.normalize(
                    value.location, in: canvasSize)
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
