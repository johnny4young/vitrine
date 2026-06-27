import SwiftUI

/// The interactive editing layer drawn over the live preview (CS-083 / CS-085).
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
    let canvasSize: CGSize
    let activeTool: AnnotationTool
    let drawColor: Color
    let drawThickness: Double
    /// Called once at the start of each discrete edit (draw, move, resize, delete) so
    /// the editor can snapshot the annotations for undo (CS-086).
    let onBeginEdit: () -> Void

    var body: some View {
        ZStack {
            if let kind = activeTool.kind {
                // Draw mode: a click-drag paints a new mark. It sits *below* the
                // handles, so the just-drawn (selected) mark stays editable.
                DrawingLayer(
                    kind: kind, color: drawColor, thickness: drawThickness, canvasSize: canvasSize,
                    nextCounterNumber: nextCounterNumber,
                    onBeginDraw: onBeginEdit,
                    onCommit: { annotation in
                        settings.config.annotations.append(annotation)
                        selection = annotation.id
                    })
            } else if selection != nil {
                // Select mode: tapping empty space clears the selection.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selection = nil }
            }
            // Handles: every mark in Select mode, and the selected mark even while a
            // draw tool is active — so you can move/resize/delete what you just drew
            // without leaving the tool (CS-085, CleanShot-style).
            ForEach(settings.config.annotations) { annotation in
                let isSelected = selection == annotation.id
                if activeTool == .select || isSelected,
                    let binding = binding(for: annotation.id)
                {
                    AnnotationHandle(
                        annotation: binding,
                        isSelected: isSelected,
                        canvasSize: canvasSize,
                        onBeginEdit: onBeginEdit,
                        onSelect: { selection = annotation.id },
                        onDelete: { delete(annotation.id) })
                }
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

    private func delete(_ id: UUID) {
        onBeginEdit()
        settings.config.annotations.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }
}

/// The full-canvas drawing surface for a single active tool: a click-drag paints a
/// shape (with a live preview), a click places a text/counter (CS-085).
private struct DrawingLayer: View {
    let kind: Annotation.Kind
    let color: Color
    let thickness: Double
    let canvasSize: CGSize
    let nextCounterNumber: Int
    let onBeginDraw: () -> Void
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
                } else {
                    // Ignore an accidental click (no real drag) so a stray tap never
                    // leaves a zero-size shape behind.
                    let distance = hypot(
                        value.location.x - value.startLocation.x,
                        value.location.y - value.startLocation.y)
                    guard distance > 6 else { return }
                    onBeginDraw()
                    onCommit(makeAnnotation(from: value.startLocation, to: value.location))
                }
            }
    }

    private func makeAnnotation(from start: CGPoint, to end: CGPoint) -> Annotation {
        Annotation.make(
            kind: kind, from: normalize(start), to: normalize(end), color: RGBAColor(color),
            thickness: thickness, number: kind == .counter ? nextCounterNumber : 0)
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
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var dragOrigin: Annotation?
    @State private var isResizing = false

    private var accent: Color { VitrineTokens.Accent.base }
    private var startPoint: CGPoint { annotation.startPoint(in: canvasSize) }
    private var endPoint: CGPoint { annotation.endPoint(in: canvasSize) }
    private var rect: CGRect { annotation.rect(in: canvasSize) }

    private var isLineLike: Bool { annotation.kind == .arrow || annotation.kind == .line }
    private var isBoxLike: Bool {
        annotation.kind == .rectangle || annotation.kind == .highlighter || annotation.kind == .blur
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
    /// a mark now that the inspector list is gone (CS-085).
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
        Color.clear
            .frame(width: hitSize.width, height: hitSize.height)
            .contentShape(Rectangle())
            .rotationEffect(isLineLike ? .radians(shaftAngle) : .zero)
            .position(hitCenter)
            .onTapGesture { onSelect() }
            .gesture(moveGesture)
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
                let dx = value.translation.width / max(canvasSize.width, 1)
                let dy = value.translation.height / max(canvasSize.height, 1)
                annotation.start = Annotation.clampNormalized(
                    CGPoint(x: origin.start.x + dx, y: origin.start.y + dy))
                annotation.end = Annotation.clampNormalized(
                    CGPoint(x: origin.end.x + dx, y: origin.end.y + dy))
            }
            .onEnded { _ in dragOrigin = nil }
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
            .onEnded { _ in isResizing = false }
    }
}
