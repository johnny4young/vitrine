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
        ExportSheetScaffold(
            title: "Export carousel",
            subtitle: "Split the snippet into numbered 4:5 slides for a carousel post.",
            width: 400,
            rootIdentifier: "carousel-export-sheet",
            failureNote: failureNote,
            progress: progress,
            progressIdentifier: nil,
            cancelIdentifier: "carousel-cancel",
            cancelDisabled: isExporting,
            onCancel: { dismiss() },
            confirmTitle: "Export…",
            confirmIdentifier: "carousel-export-confirm",
            confirmDisabled: pages.isEmpty || isExporting,
            onConfirm: exportSlides,
            content: {
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
            }
        )
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
