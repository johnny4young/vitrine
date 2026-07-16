import AppKit
import SwiftUI

/// The carousel export sheet (feature #15): choose the lines-per-slide, see how many
/// slides the snippet splits into, pick a folder, and write `carousel-01.png` … in one
/// action. Splitting lives in `CarouselPaginator`; rendering in
/// `ExportManager.exportCarousel` — this view only collects the two choices.
struct CarouselExportView: View {
    /// The user's current snapshot (style + any brand watermark); each slide replaces
    /// only its `code` with that page's lines.
    let baseConfig: SnapshotConfig
    let profile: ColorProfile

    @Environment(\.dismiss) private var dismiss

    @State private var linesPerSlide = CarouselPaginator.defaultLinesPerSlide

    /// A short result line shown only when some slides failed to write.
    @State private var failureNote: String?

    /// Live "completed/total" while the batch runs; `nil` when idle.
    @State private var progress: (completed: Int, total: Int)?

    private var isExporting: Bool { progress != nil }

    private var pages: [String] {
        CarouselPaginator.pages(for: baseConfig.code, maxLinesPerSlide: linesPerSlide)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export carousel")
                    .font(.system(size: VitrineTokens.FontSize.headline, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.primary)
                Text("Split the snippet into numbered 4:5 slides for a carousel post.")
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
            }

            HStack(spacing: 10) {
                Stepper(value: $linesPerSlide, in: CarouselPaginator.linesPerSlideRange) {
                    Text("Lines per slide: \(linesPerSlide)")
                        .font(.system(size: VitrineTokens.FontSize.body))
                }
                .accessibilityIdentifier("carousel-lines-stepper")
                Spacer(minLength: 0)
                // The live outcome, so the choice is informed before any file exists.
                Text("\(pages.count) slides")
                    .font(.system(size: VitrineTokens.FontSize.caption, weight: .semibold))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("carousel-slide-count")
            }

            if let failureNote {
                Text(verbatim: failureNote)
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .disabled(isExporting)
                    .accessibilityIdentifier("carousel-cancel")
                Spacer()
                if let progress {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(verbatim: "\(progress.completed)/\(progress.total)")
                            .font(.system(size: VitrineTokens.FontSize.caption))
                            .foregroundStyle(VitrineTokens.Text.secondary)
                            .monospacedDigit()
                    }
                }
                Button("Export…") { exportSlides() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pages.isEmpty || isExporting)
                    .accessibilityIdentifier("carousel-export-confirm")
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(VitrineTokens.Surface.window)
        // A plain VStack is not an AX element, so an identifier put directly on it
        // propagates down and CLOBBERS every child's identifier (the stepper, the
        // count, the buttons would all report the root's id). `.contain` makes the
        // root a real container element so the children keep their own ids.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("carousel-export-sheet")
    }

    private func exportSlides() {
        let pages = pages
        guard !pages.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Export")
        panel.message = String(localized: "Choose a folder for the carousel slides.")
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        failureNote = nil
        progress = (0, pages.count)
        Task {
            let result = await ExportManager.exportCarousel(
                baseConfig, pages: pages, to: directory, profile: profile,
                onProgress: { completed, total in progress = (completed, total) })
            progress = nil
            if result.failed == 0 {
                CaptureHUDController.shared.present(
                    Notifier.confirmation(String(localized: "Carousel exported")))
                NSWorkspace.shared.activateFileViewerSelecting([directory])
                dismiss()
            } else {
                failureNote =
                    "\(result.written)/\(pages.count) — "
                    + String(
                        localized:
                            "Some images couldn't be written. Check the folder and try again.")
            }
        }
    }
}
