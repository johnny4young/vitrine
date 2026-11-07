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
    /// Snaps dragged marks to the canvas layout; without a layout, drags stay free.
    var snapper = AnnotationSnapper()
    /// Called once at the start of each discrete edit (draw, move, resize, delete) so
    /// the editor can snapshot the annotations for undo.
    let onBeginEdit: () -> Void
    /// Closes the edit transaction after the mutation so unchanged interactions do
    /// not create an undo entry or discard redo.
    let onEndEdit: () -> Void

    @State private var snapGuides: [SnapGuide] = []

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
                        snapper: snapper, onGuides: { snapGuides = $0 },
                        onBeginDraw: onBeginEdit,
                        // A new callout's edit stays open until its inline field closes,
                        // so a callout left blank leaves no undo step behind.
                        onEndDraw: kind == .text ? {} : onEndEdit,
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
                        onDelete: { delete(annotation.id) },
                        offersMarkToolbar: activeTool == .select,
                        snapper: snapper, onGuides: { snapGuides = $0 })
                }
            }
            // The focused inline field for the text callout being edited.
            if let id = editingAnnotationID, let binding = binding(for: id),
                binding.wrappedValue.kind == .text
            {
                TextAnnotationEditor(
                    annotation: binding, canvasSize: canvasSize, onCommit: endTextEditing)
            }
            if !snapGuides.isEmpty {
                SnapGuidesView(guides: snapGuides, lineWidth: snapper.guideWidth)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        #if DEBUG
            .task(id: canvasSize) { await showDemoSnapGuide() }
        #endif
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

    #if DEBUG
        /// The `--demo-snap-guide` hook: a box resized onto the code rows with its guides up,
        /// since a guide otherwise shows only mid-drag.
        private func showDemoSnapGuide() async {
            guard ProcessInfo.processInfo.arguments.contains("--demo-snap-guide"),
                canvasSize.width > 0, settings.style.annotations.isEmpty
            else { return }
            for _ in 0..<100 where snapper.layout == nil {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let targets = snapper.targets(bypassed: false), targets.rowEdges.count > 3
            else { return }
            let start = CGPoint(x: targets.frameXs[2].position, y: targets.rowEdges[1].position)
            let dragged = CGPoint(
                x: canvasSize.width * 0.6, y: targets.rowEdges[3].position + targets.threshold / 2)
            let (end, guides) = targets.snapEnd(dragged, anchor: start, kind: .rectangle)
            let mark = Annotation.make(
                kind: .rectangle,
                from: AnnotationInteractionGeometry.normalize(start, in: canvasSize),
                to: AnnotationInteractionGeometry.normalize(end, in: canvasSize),
                color: RGBAColor(drawColor), thickness: drawThickness)
            settings.style.annotations.append(mark)
            selection = mark.id
            snapGuides = guides
        }
    #endif

    private func delete(_ id: UUID) {
        onBeginEdit()
        settings.style.annotations.removeMark(id)
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
    let snapper: AnnotationSnapper
    let onGuides: ([SnapGuide]) -> Void
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
        .onDisappear { if drag != nil { onGuides([]) } }
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !kind.isPointPlaced {
                    drag = snapped(value.startLocation, value.location)
                }
            }
            .onEnded { value in
                defer {
                    drag = nil
                    onGuides([])
                }
                guard
                    AnnotationInteractionGeometry.shouldCommit(
                        kind: kind, from: value.startLocation, to: value.location)
                else { return }
                onBeginDraw()
                let ends: (start: CGPoint, end: CGPoint)
                if kind.isPointPlaced {
                    let placed = snapper.apply(value.location, onGuides: { _ in }) {
                        $0.snapEnd(value.location, anchor: value.location, kind: kind)
                    }
                    ends = (placed, placed)
                } else {
                    ends = AnnotationSnapper.committedEnds(
                        preview: drag, start: value.startLocation, end: value.location)
                }
                onCommit(makeAnnotation(from: ends.start, to: ends.end))
                onEndDraw()
            }
    }

    /// Both ends of a drawn shape, snapped against each other.
    private func snapped(_ start: CGPoint, _ end: CGPoint) -> (start: CGPoint, end: CGPoint) {
        snapper.apply((start, end), onGuides: onGuides) {
            $0.snapEnds(start: start, end: end, kind: kind)
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
    /// Whether the selected mark's toolbar may show beside this mark.
    let offersMarkToolbar: Bool
    let snapper: AnnotationSnapper
    let onGuides: ([SnapGuide]) -> Void

    @State private var dragOrigin: Annotation?
    @State private var isResizing = false

    private var kindTitle: String {
        AnnotationTool.allCases.first { $0.kind == annotation.kind }?.localizedTitle
            ?? String(localized: "Annotation")
    }

    private var accent: Color { VitrineTokens.Accent.base }
    private var geometry: AnnotationInteractionGeometry {
        AnnotationInteractionGeometry(annotation: annotation, canvasSize: canvasSize)
    }

    var body: some View {
        ZStack {
            if isSelected { selectionChrome }
            bodyHitArea
                .accessibilityElement()
                .accessibilityLabel(kindTitle)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { onSelect() }
                .accessibilityAction(named: Text("Delete")) { onDelete() }
            if isSelected && !annotation.kind.isPointPlaced { resizeHandles }
            if isSelected { deleteButton }
            // Withdrawn while the mark is dragged or resized.
            if isSelected, offersMarkToolbar, dragOrigin == nil, !isResizing {
                let chrome = geometry.chromeBounds
                Color.clear
                    .frame(width: chrome.width, height: chrome.height)
                    .anchorPreference(key: MarkToolbarAnchorsKey.self, value: .bounds) {
                        MarkToolbarAnchors(mark: $0)
                    }
                    .position(x: chrome.midX, y: chrome.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        // A mark deleted mid-drag never sees its gesture end.
        .onDisappear { if dragOrigin != nil || isResizing { onGuides([]) } }
    }

    /// A small delete badge at the selection's top-right — the primary way to remove
    /// a mark now that the inspector list is gone.
    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
                .font(.system(size: AnnotationInteractionGeometry.deleteBadgeSize))
        }
        .buttonStyle(.plain)
        .position(geometry.deleteBadgeCenter)
        .accessibilityLabel("Delete annotation")
        .accessibilityIdentifier("annotation-delete")
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
            // Same exclusivity for text callouts; the single click yields to the double
            // click that re-opens the field.
            base.gesture(
                moveGesture.exclusively(
                    before: TapGesture(count: 2).onEnded { onEdit() }
                        .exclusively(before: TapGesture().onEnded { onSelect() })))
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
                let delta = snapper.apply(CGSize.zero, onGuides: onGuides) {
                    $0.snapMove(moved, in: canvasSize)
                }
                if delta != .zero {
                    moved = origin
                    moved.nudge(
                        by: CGSize(
                            width: value.translation.width + delta.width,
                            height: value.translation.height + delta.height),
                        in: canvasSize)
                }
                annotation = moved
            }
            .onEnded { _ in
                dragOrigin = nil
                onGuides([])
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
        handleDot(at: geometry.start, gesture: resizeGesture(\.start, anchor: \.end))
        handleDot(at: geometry.end, gesture: resizeGesture(\.end, anchor: \.start))
    }

    private func handleDot<G: Gesture>(at point: CGPoint, gesture: G) -> some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(accent, lineWidth: 2))
            .frame(
                width: AnnotationInteractionGeometry.handleDiameter,
                height: AnnotationInteractionGeometry.handleDiameter
            )
            .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            .contentShape(Circle())
            .position(point)
            .gesture(gesture)
    }

    private func resizeGesture(
        _ keyPath: WritableKeyPath<Annotation, CGPoint>, anchor: KeyPath<Annotation, CGPoint>
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isResizing {
                    isResizing = true
                    onBeginEdit()
                }
                onSelect()
                let other = Annotation.denormalize(annotation[keyPath: anchor], in: canvasSize)
                let point = snapper.apply(value.location, onGuides: onGuides) {
                    $0.snapEnd(value.location, anchor: other, kind: annotation.kind)
                }
                annotation[keyPath: keyPath] = AnnotationInteractionGeometry.normalize(
                    point, in: canvasSize)
            }
            .onEnded { _ in
                isResizing = false
                onGuides([])
                onEndEdit()
            }
    }
}

/// The guides of the active snap. Stage chrome: the export never draws the overlay.
private struct SnapGuidesView: View {
    let guides: [SnapGuide]
    let lineWidth: CGFloat

    var body: some View {
        Path { path in
            for guide in guides {
                switch guide.axis {
                case .vertical:
                    path.move(to: CGPoint(x: guide.position, y: guide.span.lowerBound))
                    path.addLine(to: CGPoint(x: guide.position, y: guide.span.upperBound))
                case .horizontal:
                    path.move(to: CGPoint(x: guide.span.lowerBound, y: guide.position))
                    path.addLine(to: CGPoint(x: guide.span.upperBound, y: guide.position))
                }
            }
        }
        .stroke(VitrineTokens.Chrome.snapGuide, lineWidth: lineWidth)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
            // A request made as the field appears lands before SwiftUI registers it as
            // a focus target and is dropped, leaving focus wherever it was.
            .task {
                await Task.yield()
                isFocused = true
            }
            .onSubmit(onCommit)
            .onExitCommand(perform: onCommit)
            .onChange(of: isFocused) { _, focused in
                if !focused { onCommit() }
            }
            .accessibilityIdentifier("annotation-text-field")
    }
}
