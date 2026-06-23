import AppKit
import SwiftUI

/// The PRO multi-size one-pass export sheet (CS-093): multi-select the platform
/// presets, choose a folder, and write one correctly-sized file per preset in a
/// single action.
///
/// This is the code/card export ladder fanned out over `ExportPreset` sizes (a
/// publishing convenience) — distinct from CS-044's free multi-_viewport_ web
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

    @Environment(\.dismiss) private var dismiss

    /// The selected preset ids — every preset on by default, so "Export" is one tap
    /// for the common "give me all the sizes" case.
    @State private var selected: Set<String> = Set(ExportPreset.all.map(\.id))

    /// A short result line shown only when some files failed to write.
    @State private var failureNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export sizes")
                    .font(.system(size: VitrineTokens.FontSize.headline, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.primary)
                Text("Write one image per platform size into a folder.")
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
            }

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

            if let failureNote {
                Text(verbatim: failureNote)
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("multi-size-cancel")
                Spacer()
                Button("Export…") { exportSelected() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)
                    .accessibilityIdentifier("multi-size-export-confirm")
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(VitrineTokens.Surface.window)
        .accessibilityIdentifier("multi-size-export-sheet")
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

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Export")
        panel.message = String(localized: "Choose a folder for the exported images.")
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        let result = ExportManager.exportPresetSizes(
            baseConfig, presets: presets, to: directory, format: format, profile: profile,
            textSidecar: textSidecar)
        if result.failed == 0 {
            // Confirm and reveal the folder so the export doesn't finish silently — the
            // feedback convention every other export follows (audit P1-UX-1).
            CaptureHUDController.shared.present(
                Notifier.confirmation(String(localized: "Images exported")))
            NSWorkspace.shared.activateFileViewerSelecting([directory])
            dismiss()
        } else {
            // Keep the sheet open so the user can retry. The count rides in a verbatim
            // prefix so the localized sentence stays a plain (non-format) catalog key.
            failureNote =
                "\(result.written)/\(selected.count) — "
                + String(
                    localized: "Some images couldn't be written. Check the folder and try again.")
        }
    }
}
