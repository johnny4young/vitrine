import SwiftUI
import VitrineDomain
import VitrineRendering

/// The PRO multi-size one-pass export sheet: the capture rendered at every platform preset at
/// once, a shared focal point for sizes too small for it, and one file per selected preset
/// written in a single action.
///
/// This is the code/card export ladder fanned out over `ExportPreset` sizes (a
/// publishing convenience) — distinct from the free multi-viewport web
/// capture. Each file equals what a single export with that preset selected would
/// produce; the rendering itself lives in `ExportManager.exportPresetSizes`.
struct MultiSizeExportView: View {
    /// What the running measurement depends on. `restarts` starts it again after a stop.
    private struct EstimateRequest: Equatable {
        var input: PresetSizeEstimator.Input
        var selected: Set<String>
        var isExporting: Bool
        var restarts: Int
    }

    /// What the tiles depend on. A drag in progress waits for its release.
    private struct BoardRequest: Equatable {
        var config: SnapshotConfig
        var selected: Set<String>
        var isExporting: Bool
        var restarts: Int
    }

    /// The user's current snapshot (code + style + any brand watermark). Each preset
    /// overlays only its own padding/background/size on top of this.
    let baseConfig: SnapshotConfig
    let format: ExportFormat
    let profile: ColorProfile
    /// Whether the active editor session should write plain-text sidecars next to the
    /// exported images. Passed in by the editor so a per-window session stays
    /// authoritative instead of re-reading the app-wide defaults.
    let textSidecar: Bool
    let feedback: FeedbackDisplay
    let presentation: BatchExportPresentation

    @Environment(\.dismiss) private var dismiss

    /// The selected preset ids — every preset on by default, so "Export" is one tap
    /// for the common "give me all the sizes" case.
    @State private var selected: Set<String> = Set(ExportPreset.all.map(\.id))

    /// A short result line shown only when some files failed to write.
    @State private var failureNote: String?

    /// Live "completed/total" while the (off-main) batch runs; `nil` when idle. Drives
    /// the inline progress indicator so a multi-preset export at 2–3× scale shows work
    /// instead of a frozen sheet.
    @State private var progress: (completed: Int, total: Int)?

    @State private var estimator = PresetSizeEstimator()
    @State private var estimateRestarts = 0

    @State private var board = EverySizeBoardModel()
    @State private var focalPoint: CGPoint?
    /// The focal point under a drag, shown on every tile before the tiles re-render.
    @State private var draggedFocalPoint: CGPoint?

    /// Whether an export is in flight — disables the buttons so the batch can't be
    /// re-triggered or the sheet dismissed mid-write.
    private var isExporting: Bool { progress != nil }

    var body: some View {
        ExportSheetScaffold(
            title: "Export sizes",
            subtitle: "Write one image per platform size into a folder.",
            width: 640,
            rootIdentifier: "multi-size-export-sheet",
            failureNote: failureNote,
            progress: progress,
            progressIdentifier: "multi-size-progress",
            cancelIdentifier: "multi-size-cancel",
            cancelDisabled: isExporting,
            onCancel: { dismiss() },
            confirmTitle: "Export…",
            confirmIdentifier: "multi-size-export-confirm",
            confirmDisabled: selected.isEmpty || isExporting,
            onConfirm: exportSelected,
            content: { content }
        )
        // Disabling the buttons stops a *button* dismissal, but not Escape or a click
        // outside, and the export runs in an unstructured `Task` that would keep writing
        // into the chosen folder while reporting completion to a sheet that is gone. This
        // enforces the invariant the buttons only imply.
        .interactiveDismissDisabled(isExporting)
        .task(id: estimateRequest) {
            guard !isExporting else {
                estimator.stop()
                return
            }
            let request = estimateRequest
            await estimator.measure(
                ExportPreset.all.filter { request.selected.contains($0.id) }, for: request.input)
        }
        .task(id: boardRequest) {
            guard !isExporting else {
                board.stop()
                return
            }
            let request = boardRequest
            await board.render(
                ExportPreset.all.filter { request.selected.contains($0.id) }, for: request.config)
        }
    }

    /// Marks sit at fixed canvas positions and the PDF path draws every size centered, so
    /// either keeps the focal point out of the export.
    private var acceptsFocalPoint: Bool {
        format != .pdf && !FocalCrop.isBlocked(for: baseConfig)
    }

    private var exportConfig: SnapshotConfig {
        var config = baseConfig
        if acceptsFocalPoint { config.focalPoint = focalPoint }
        return config
    }

    private var boardRequest: BoardRequest {
        BoardRequest(
            config: exportConfig, selected: selected, isExporting: isExporting,
            restarts: estimateRestarts)
    }

    private var estimateInput: PresetSizeEstimator.Input {
        PresetSizeEstimator.Input(config: exportConfig, format: format, profile: profile)
    }

    private var estimateRequest: EstimateRequest {
        EstimateRequest(
            input: estimateInput, selected: selected, isExporting: isExporting,
            restarts: estimateRestarts)
    }

    /// The multi-size sheet's distinct body: a tile per preset and the selection controls.
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 14, alignment: .top)],
                    alignment: .leading, spacing: 14
                ) {
                    ForEach(ExportPreset.all) { preset in
                        tile(preset)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 360)
            .accessibilityIdentifier("multi-size-board")

            HStack(spacing: 10) {
                Button("Select all") { selected = Set(ExportPreset.all.map(\.id)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(VitrineTokens.Accent.systemText)
                    .accessibilityIdentifier("multi-size-select-all")
                Button("Select none") { selected = [] }
                    .buttonStyle(.plain)
                    .foregroundStyle(VitrineTokens.Accent.systemText)
                    .accessibilityIdentifier("multi-size-select-none")
                if focalPoint != nil, acceptsFocalPoint {
                    Button("Clear focal point") {
                        focalPoint = nil
                        draggedFocalPoint = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VitrineTokens.Accent.systemText)
                    .disabled(isExporting)
                    .accessibilityIdentifier("multi-size-focal-clear")
                }
                Spacer(minLength: 0)
                sizeEstimate
            }
            .font(.system(size: VitrineTokens.FontSize.caption))
        }
    }

    private func tile(_ preset: ExportPreset) -> some View {
        let frame = preset.sizing.fixedSize ?? CGSize(width: preset.sizing.aspectRatio, height: 1)
        return VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(frame.width / frame.height, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        thumbnail(preset, frame: frame, size: proxy.size)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96)
            Toggle(isOn: binding(for: preset)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: preset.displayName)
                        .font(.system(size: VitrineTokens.FontSize.body))
                        .foregroundStyle(VitrineTokens.Text.primary)
                        .lineLimit(1)
                    Text(verbatim: "\(Int(frame.width)) × \(Int(frame.height))")
                        .font(.system(size: VitrineTokens.FontSize.caption))
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                        .monospacedDigit()
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("multi-size-preset-\(preset.id)")
        }
    }

    @ViewBuilder
    private func thumbnail(_ preset: ExportPreset, frame: CGSize, size: CGSize) -> some View {
        let isSelected = selected.contains(preset.id)
        let tile = isSelected ? board.tiles[preset.id] : nil
        let shape = RoundedRectangle(cornerRadius: VitrineTokens.Radius.sm, style: .continuous)
        let scale = size.width / frame.width
        let canFocus = isSelected && acceptsFocalPoint && tile != nil && !isExporting
        ZStack(alignment: .topLeading) {
            if let tile {
                Image(decorative: tile.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                shape.fill(VitrineTokens.Surface.inset)
            }
            if let tile, let focal = draggedFocalPoint ?? focalPoint, acceptsFocalPoint {
                let point = tile.geometry.point(for: focal)
                Circle()
                    .fill(VitrineTokens.Accent.base)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .frame(width: 11, height: 11)
                    .position(x: point.x * scale, y: point.y * scale)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .opacity(isSelected ? 1 : 0.45)
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let tile, scale > 0 else { return }
                    draggedFocalPoint = tile.geometry.focal(
                        at: CGPoint(x: value.location.x / scale, y: value.location.y / scale))
                }
                .onEnded { _ in
                    focalPoint = draggedFocalPoint ?? focalPoint
                    draggedFocalPoint = nil
                },
            including: canFocus ? .all : .none
        )
        .help(focalHelp(isSelected: isSelected))
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: preset.displayName))
        .accessibilityIdentifier("multi-size-tile-\(preset.id)")
    }

    private func focalHelp(isSelected: Bool) -> Text {
        if format == .pdf { return Text("PDF exports keep every size centered.") }
        if FocalCrop.isBlocked(for: baseConfig) {
            return Text("Marks on the capture keep every size centered.")
        }
        return isSelected ? Text("Drag to choose what stays in view.") : Text(verbatim: "")
    }

    /// Shares the row with the selection buttons, so its arrival never resizes the sheet.
    private var sizeEstimate: some View {
        let summary = estimator.total(of: selected, for: estimateInput).map {
            ExportSizeEstimate.summary(format: format, bytes: $0)
        }
        return Text(verbatim: summary?.text ?? "")
            .foregroundStyle(VitrineTokens.Text.secondary)
            .monospacedDigit()
            .accessibilityLabel(Text(verbatim: summary?.spokenText ?? ""))
            .accessibilityHidden(summary == nil)
            .accessibilityIdentifier("multi-size-size-estimate")
    }

    private func binding(for preset: ExportPreset) -> Binding<Bool> {
        Binding(
            get: { selected.contains(preset.id) },
            set: { isOn in
                if isOn {
                    selected.insert(preset.id)
                } else {
                    selected.remove(preset.id)
                }
            })
    }

    private func exportSelected() {
        let presets = ExportPreset.all.filter { selected.contains($0.id) }
        guard !presets.isEmpty else { return }

        // The panel runs a modal loop, and renders would keep stealing time from it.
        estimator.stop()
        board.stop()
        guard
            let directory = presentation.chooseDirectory(
                message: String(localized: "Choose a folder for the exported images."))
        else {
            estimateRestarts += 1
            return
        }

        failureNote = nil
        let total = presets.count
        progress = (0, total)
        // Render each preset on the main actor, but encode+write off-main with a yield
        // between presets, so the sheet stays responsive and shows live progress.
        Task {
            let result = await ExportManager.exportPresetSizes(
                exportConfig, presets: presets, to: directory, format: format, profile: profile,
                textSidecar: textSidecar,
                onProgress: { completed, total in progress = (completed, total) })
            progress = nil
            let completion = BatchExportCompletion(
                written: result.written,
                failed: result.failed,
                expected: total,
                renderFailure: result.firstRenderFailure)
            if completion.isComplete {
                let droppedLegend = presets.contains { preset in
                    var config = baseConfig
                    preset.apply(to: &config)
                    return config.counterLegendFit(in: preset.sizing.fixedSize).dropped > 0
                }
                feedback(
                    Notifier.confirmation(
                        droppedLegend
                            ? String(localized: "Images exported. Some legend entries didn't fit.")
                            : String(localized: "Images exported")))
                presentation.reveal(directory)
                dismiss()
            } else {
                failureNote = completion.failureNote
            }
        }
    }
}
