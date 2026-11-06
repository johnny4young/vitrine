import SwiftUI
import VitrineDomain
import VitrineRendering

/// The carousel export sheet: choose how the snippet splits and what each slide says
/// about its place, see the outcome, and write `carousel-01.png` … in one action.
/// Splitting and per-slide configs live in `CarouselPaginator`; rendering in
/// `ExportManager.exportCarousel` — this view only collects the choices.
struct CarouselExportView: View {
    private struct Choices: Equatable {
        var linesPerSlide = CarouselPaginator.defaultLinesPerSlide
        var prefersBlankLineBreaks = true
        var cues: CarouselPaginator.Cues
    }

    /// Everything that changes the rendered slides, so the size estimate follows it.
    private struct EstimateInput: Equatable {
        var choices: Choices
        var config: SnapshotConfig
        var profile: ColorProfile
    }

    /// What the planned file names depend on.
    private struct OutputPlan: Equatable {
        var folder: URL?
        var slideCount: Int
    }

    /// The user's current snapshot (style + any brand watermark); each slide replaces
    /// only its `code` with that page's lines.
    let baseConfig: SnapshotConfig
    let profile: ColorProfile
    let feedback: FeedbackDisplay
    let presentation: BatchExportPresentation

    @Environment(\.dismiss) private var dismiss

    @State private var choices: Choices

    /// The folder chosen in this sheet. Without one, confirming asks for it, because
    /// the sandbox grants no folder until the user picks it.
    @State private var folder: URL?

    /// The encoded size of a sampled slide, scaled by the live slide count.
    @State private var bytesPerSlide: Int?

    /// Held in state so slides written during the export don't rename the line under it.
    @State private var plannedFilenames: [String] = []

    /// A short result line shown only when some slides failed to write.
    @State private var failureNote: String?

    /// Live "completed/total" while the batch runs; `nil` when idle.
    @State private var progress: (completed: Int, total: Int)?

    init(
        baseConfig: SnapshotConfig, profile: ColorProfile, feedback: FeedbackDisplay,
        presentation: BatchExportPresentation
    ) {
        self.baseConfig = baseConfig
        self.profile = profile
        self.feedback = feedback
        self.presentation = presentation
        _choices = State(
            initialValue: Choices(
                cues: CarouselPaginator.Cues(
                    lineNumbers: baseConfig.showLineNumbers ? .continuing : .off,
                    showsPageBadge: true,
                    showsContinuation: true,
                    continuationLabel: String(
                        localized: "continues →",
                        comment: "Cue drawn on a carousel slide when another slide follows."))))
    }

    private var isExporting: Bool { progress != nil }

    private var pages: [CarouselPaginator.Slide] {
        CarouselPaginator.slides(
            for: baseConfig.code, maxLinesPerSlide: choices.linesPerSlide,
            preferBlankLineBreaks: choices.prefersBlankLineBreaks)
    }

    private var confirmTitle: LocalizedStringKey {
        guard folder != nil else { return "Export…" }
        let count = pages.count
        return count == 1 ? "Export 1 slide" : "Export \(count) slides"
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
            confirmTitle: confirmTitle,
            confirmIdentifier: "carousel-export-confirm",
            confirmDisabled: pages.isEmpty || isExporting,
            onConfirm: exportSlides,
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    splitControls
                    Divider()
                    slideControls
                    Divider()
                    outputControls
                }
                .toggleStyle(.switch)
                .font(.system(size: VitrineTokens.FontSize.body))
                .disabled(isExporting)
            }
        )
        .interactiveDismissDisabled(isExporting)
        .task(id: EstimateInput(choices: choices, config: baseConfig, profile: profile)) {
            await refreshSizeEstimate()
        }
        .task(id: OutputPlan(folder: folder, slideCount: pages.count)) {
            refreshPlannedFilenames()
        }
    }

    private var splitControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Stepper(value: $choices.linesPerSlide, in: CarouselPaginator.linesPerSlideRange) {
                    Text("Lines per slide: \(choices.linesPerSlide)")
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
            switchRow(
                "Prefer blank-line breaks", isOn: $choices.prefersBlankLineBreaks,
                identifier: "carousel-prefer-blank-lines")
        }
    }

    private var slideControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Segments share one width, so a long label can outgrow the row.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Text("Line numbers")
                        .fixedSize()
                    Spacer(minLength: 0)
                    lineNumbersPicker
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Line numbers")
                    lineNumbersPicker
                }
            }
            switchRow(
                "Page badge “2 / 4”", isOn: $choices.cues.showsPageBadge,
                identifier: "carousel-page-badge")
            switchRow(
                "“continues →” cue", isOn: $choices.cues.showsContinuation,
                identifier: "carousel-continuation-cue")
        }
    }

    private var lineNumbersPicker: some View {
        Picker(
            "Line numbers",
            selection: Binding(
                get: { choices.cues.lineNumbers ?? .off },
                set: { choices.cues.lineNumbers = $0 })
        ) {
            Text("Continue").tag(CarouselPaginator.Cues.LineNumbers.continuing)
            Text("Restart").tag(CarouselPaginator.Cues.LineNumbers.restarting)
            Text("Off").tag(CarouselPaginator.Cues.LineNumbers.off)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("carousel-line-numbers")
    }

    private var outputControls: some View {
        // Paginated once here: every line below needs only the count.
        let slideCount = pages.count
        let estimatedBytes = bytesPerSlide.map { $0 * slideCount }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                folderLabel
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("carousel-folder-path")
                Spacer(minLength: 0)
                Button(folder == nil ? "Choose…" : "Change…", action: chooseFolder)
                    .controlSize(.small)
                    .accessibilityIdentifier("carousel-folder-change")
            }
            // A hidden copy holds room for the size, so its arrival cannot add a line.
            ZStack(alignment: .topLeading) {
                Text(
                    verbatim: outputLine(
                        slideCount: slideCount,
                        estimatedBytes: estimatedBytes ?? ExportSizeEstimate.widestBytes)
                )
                .hidden()
                Text(verbatim: outputLine(slideCount: slideCount, estimatedBytes: estimatedBytes))
                    .accessibilityLabel(
                        Text(
                            verbatim: spokenOutputLine(
                                slideCount: slideCount, estimatedBytes: estimatedBytes))
                    )
                    .accessibilityIdentifier("carousel-output-summary")
            }
            .font(.system(size: VitrineTokens.FontSize.caption))
            .foregroundStyle(VitrineTokens.Text.secondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func switchRow(
        _ title: LocalizedStringKey, isOn: Binding<Bool>, identifier: String
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer(minLength: 0)
            Toggle(title, isOn: isOn)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private var folderLabel: some View {
        if let folder {
            let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) }
            Text(verbatim: CarouselPaginator.displayPath(folder, home: home))
                .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                .foregroundStyle(VitrineTokens.Text.secondary)
                .help(folder.path)
        } else {
            Text("No folder chosen")
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.tertiary)
        }
    }

    private func outputLine(slideCount: Int, estimatedBytes: Int?) -> String {
        guard slideCount > 0 else { return "" }
        let summary = CarouselPaginator.outputSummary(
            filenames: outputFilenames(slideCount: slideCount), estimatedBytes: estimatedBytes)
        return summary + " · " + String(localized: "Existing files are kept")
    }

    private func spokenOutputLine(slideCount: Int, estimatedBytes: Int?) -> String {
        guard slideCount > 0 else { return "" }
        let summary = CarouselPaginator.spokenOutputSummary(
            filenames: outputFilenames(slideCount: slideCount), estimatedBytes: estimatedBytes)
        return summary + ", " + String(localized: "Existing files are kept")
    }

    private func outputFilenames(slideCount: Int) -> [String] {
        plannedFilenames.count == slideCount
            ? plannedFilenames : CarouselPaginator.plannedFilenames(slideCount: slideCount, in: nil)
    }

    /// Waits out a stepper run before rendering, since the sample renders on the main actor.
    private func refreshSizeEstimate() async {
        // The old sample described other slides, so the size is left out until the new one.
        bytesPerSlide = nil
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let estimate = await ExportManager.estimatedCarouselSlideBytes(
            baseConfig, slides: pages, cues: choices.cues, profile: profile)
        guard !Task.isCancelled else { return }
        bytesPerSlide = estimate
    }

    private func refreshPlannedFilenames() {
        plannedFilenames = CarouselPaginator.plannedFilenames(
            slideCount: pages.count, in: folder)
    }

    private func chooseFolder() {
        if let chosen = presentation.chooseDirectory(message: folderPrompt) {
            folder = chosen
        }
    }

    private var folderPrompt: String {
        String(localized: "Choose a folder for the carousel slides.")
    }

    private func exportSlides() {
        let pages = pages
        guard !pages.isEmpty else { return }
        guard let directory = folder ?? presentation.chooseDirectory(message: folderPrompt)
        else { return }

        failureNote = nil
        progress = (0, pages.count)
        Task {
            let result = await ExportManager.exportCarousel(
                baseConfig, slides: pages, cues: choices.cues, to: directory, profile: profile,
                onProgress: { completed, total in progress = (completed, total) })
            progress = nil
            let completion = BatchExportCompletion(
                written: result.written,
                failed: result.failed,
                expected: pages.count,
                renderFailure: result.firstRenderFailure)
            if completion.isComplete {
                feedback(Notifier.confirmation(String(localized: "Carousel exported")))
                presentation.reveal(directory)
                dismiss()
            } else {
                failureNote = completion.failureNote
                refreshPlannedFilenames()
            }
        }
    }
}
