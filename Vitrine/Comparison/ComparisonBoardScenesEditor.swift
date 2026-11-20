import SwiftUI

/// The board's camera, its saved scenes, and their export, in the inspector.
struct ComparisonBoardScenesEditor: View {
    @Bindable var draft: ComparisonBoardDraft
    let progress: (completed: Int, total: Int)?
    let exportPNGs: () -> Void
    let cancelPNGs: () -> Void
    let exportPDF: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VitrineTokens.Spacing.sm) {
            InspectorRow(label: Text("Zoom")) {
                HStack(spacing: 8) {
                    Slider(value: cameraBinding(.zoom), in: 100...400, step: 25)
                        .frame(width: 110)
                        .accessibilityLabel("Zoom")
                        .accessibilityValue(Text(verbatim: zoomText))
                        .accessibilityIdentifier("comparison-board-view-zoom-slider")
                    Text(verbatim: zoomText)
                        .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                        .frame(width: 38, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
            InspectorRow(label: Text("Horizontal")) {
                ValueSlider(
                    label: "Horizontal", value: cameraBinding(.horizontal), range: 0...100, step: 1,
                    identifier: "comparison-board-view-x-slider")
            }
            .disabled(draft.camera.zoom == 1)
            InspectorRow(label: Text("Vertical")) {
                ValueSlider(
                    label: "Vertical", value: cameraBinding(.vertical), range: 0...100, step: 1,
                    identifier: "comparison-board-view-y-slider")
            }
            .disabled(draft.camera.zoom == 1)

            ForEach(Array(draft.scenes.enumerated()), id: \.element.id) { index, scene in
                sceneRow(scene, index: index)
            }

            Button {
                draft.addSceneFromView()
            } label: {
                Label("Add scene from view", systemImage: "plus.viewfinder")
            }
            .disabled(!draft.canAddScene || !draft.isValid)
            .accessibilityIdentifier("comparison-board-add-scene-button")

            InspectorRow(label: Text("Export")) {
                if let progress {
                    ProgressView(
                        value: Double(progress.completed), total: Double(max(progress.total, 1))
                    )
                    .frame(width: 90)
                    .accessibilityIdentifier("comparison-board-export-scenes-progress")
                    Button("Cancel", action: cancelPNGs)
                        .accessibilityIdentifier("comparison-board-export-scenes-cancel")
                } else {
                    Button("Carousel", action: exportPNGs)
                        .help("Save each scene as a PNG in a folder")
                        .accessibilityIdentifier("comparison-board-export-scenes-png")
                    Button(action: exportPDF) { Text(verbatim: "PDF") }
                        .help("Save the scenes as pages of one PDF")
                        .accessibilityIdentifier("comparison-board-export-scenes-pdf")
                }
            }
            .disabled(progress == nil && (draft.scenes.isEmpty || !draft.isValid))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comparison-board-scenes")
    }

    private func sceneRow(_ scene: ComparisonBoardScene, index: Int) -> some View {
        HStack(spacing: VitrineTokens.Spacing.xs) {
            Text(verbatim: "\(index + 1)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(VitrineTokens.Text.secondary)
            TextField(
                "Scene name",
                text: Binding(
                    get: { scene.name },
                    set: { draft.renameScene(id: scene.id, to: $0) })
            )
            .accessibilityIdentifier("comparison-board-scene-name-\(index)")
            Text("\(scene.seconds) s")
                .monospacedDigit()
                .accessibilityHidden(true)
            Stepper(
                "Duration",
                value: Binding(
                    get: { scene.seconds },
                    set: { draft.setSeconds($0, forScene: scene.id) }),
                in: ComparisonBoardScene.durationRange
            )
            .labelsHidden()
            .accessibilityValue(Text("\(scene.seconds) s"))
            .accessibilityIdentifier("comparison-board-scene-duration-\(index)")
            Button {
                draft.moveScene(id: scene.id, offset: -1)
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(index == 0)
            .help("Move scene earlier")
            .accessibilityLabel("Move scene earlier")
            .accessibilityIdentifier("comparison-board-scene-up-\(index)")
            Button {
                draft.moveScene(id: scene.id, offset: 1)
            } label: {
                Image(systemName: "arrow.down")
            }
            .disabled(index == draft.scenes.count - 1)
            .help("Move scene later")
            .accessibilityLabel("Move scene later")
            .accessibilityIdentifier("comparison-board-scene-down-\(index)")
            Button(role: .destructive) {
                draft.removeScene(id: scene.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .help("Remove scene")
            .accessibilityLabel("Remove scene")
            .accessibilityIdentifier("comparison-board-scene-remove-\(index)")
        }
        .buttonStyle(.borderless)
    }

    private var zoomText: String {
        Double(draft.camera.zoom).formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    private func cameraBinding(_ axis: ComparisonBoardViewport.Axis) -> Binding<Double> {
        Binding(
            get: { draft.camera.percent(axis) },
            set: { draft.camera = draft.camera.setting(axis, percent: $0) })
    }
}

/// Dashed, numbered frames for the saved scenes and a solid one for the current view.
struct ComparisonBoardSceneFrames: View {
    let scenes: [ComparisonBoardScene]
    let camera: ComparisonBoardViewport

    var body: some View {
        let slots = Self.badgeSlots(scenes)
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                    let frame = Self.frame(scene.viewport, in: proxy.size)
                    // Dark under light dashes reads on both light and dark boards.
                    ZStack {
                        Rectangle().strokeBorder(.black.opacity(0.55), lineWidth: 1.5)
                        Rectangle().strokeBorder(
                            .white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    Text(verbatim: "\(index + 1)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.black.opacity(0.7)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                        .position(
                            x: frame.minX + 12 + CGFloat(slots[index]) * 22, y: frame.minY + 12)
                }
                if camera != .whole {
                    let frame = Self.frame(camera, in: proxy.size)
                    Rectangle()
                        .strokeBorder(VitrineTokens.Accent.system, lineWidth: 2)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// How many earlier scenes share each scene's top-left corner, so their badges sit side
    /// by side instead of on top of each other.
    static func badgeSlots(_ scenes: [ComparisonBoardScene]) -> [Int] {
        var seen: [String: Int] = [:]
        return scenes.map { scene in
            let corner = scene.viewport.rect.origin
            let key = "\(Int((corner.x * 1000).rounded())),\(Int((corner.y * 1000).rounded()))"
            defer { seen[key, default: 0] += 1 }
            return seen[key, default: 0]
        }
    }

    private static func frame(_ viewport: ComparisonBoardViewport, in size: CGSize) -> CGRect {
        let rect = viewport.rect
        return CGRect(
            x: rect.minX * size.width, y: rect.minY * size.height,
            width: rect.width * size.width, height: rect.height * size.height)
    }
}
