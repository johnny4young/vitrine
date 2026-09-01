import SwiftUI

/// The PRO multi-size one-pass export sheet: multi-select the platform
/// presets, choose a folder, and write one correctly-sized file per preset in a
/// single action.
///
/// This is the code/card export ladder fanned out over `ExportPreset` sizes (a
/// publishing convenience) — distinct from the free multi-viewport web
/// capture. Each file equals what a single export with that preset selected would
/// produce; the rendering itself lives in `ExportManager.exportPresetSizes`.
struct MultiSizeExportView: View {
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

    /// Whether an export is in flight — disables the buttons so the batch can't be
    /// re-triggered or the sheet dismissed mid-write.
    private var isExporting: Bool { progress != nil }

    var body: some View {
        ExportSheetScaffold(
            title: "Export sizes",
            subtitle: "Write one image per platform size into a folder.",
            width: 420,
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
    }

    /// The multi-size sheet's distinct body: the scrollable preset list and the
    /// select-all/none controls.
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ExportPreset.all) { preset in
                        Toggle(isOn: binding(for: preset)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: preset.displayName)
                                    .font(.system(size: VitrineTokens.FontSize.body))
                                    .foregroundStyle(VitrineTokens.Text.primary)
                                Text(verbatim: preset.summary)
                                    .font(.system(size: VitrineTokens.FontSize.caption))
                                    .foregroundStyle(VitrineTokens.Text.tertiary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("multi-size-preset-\(preset.id)")
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 240)

            HStack(spacing: 10) {
                Button("Select all") { selected = Set(ExportPreset.all.map(\.id)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(VitrineTokens.Accent.system)
                    .accessibilityIdentifier("multi-size-select-all")
                Button("Select none") { selected = [] }
                    .buttonStyle(.plain)
                    .foregroundStyle(VitrineTokens.Accent.system)
                    .accessibilityIdentifier("multi-size-select-none")
            }
            .font(.system(size: VitrineTokens.FontSize.caption))
        }
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

        guard
            let directory = presentation.chooseDirectory(
                message: String(localized: "Choose a folder for the exported images."))
        else { return }

        failureNote = nil
        let total = presets.count
        progress = (0, total)
        // Render each preset on the main actor, but encode+write off-main with a yield
        // between presets, so the sheet stays responsive and shows live progress.
        Task {
            let result = await ExportManager.exportPresetSizes(
                baseConfig, presets: presets, to: directory, format: format, profile: profile,
                textSidecar: textSidecar,
                onProgress: { completed, total in progress = (completed, total) })
            progress = nil
            let completion = BatchExportCompletion(
                written: result.written,
                failed: result.failed,
                expected: total,
                renderFailure: result.firstRenderFailure)
            if completion.isComplete {
                feedback(Notifier.confirmation(String(localized: "Images exported")))
                presentation.reveal(directory)
                dismiss()
            } else {
                failureNote = completion.failureNote
            }
        }
    }
}
