import SwiftUI
import VitrineDomain
import VitrineRendering

/// The carousel export sheet: choose how the snippet splits and what each slide says
/// about its place, see the outcome, and write `carousel-01.png` … in one action.
/// Splitting and per-slide configs live in `CarouselPaginator`; rendering in
/// `ExportManager.exportCarousel` — this view only collects the choices.
struct CarouselExportView: View {
    /// What a split depends on.
    private struct SplitRequest: Equatable {
        var split: CarouselSplit
        var code: String
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

    @State private var split = CarouselSplit()

    @State private var cues: CarouselPaginator.Cues

    /// The latest finished split, which the sheet reads for everything it shows.
    @State private var outcome: CarouselPaginator.Outcome?

    @State private var filmstrip = CarouselFilmstripModel()

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
        _cues = State(
            initialValue: CarouselPaginator.Cues(
                lineNumbers: baseConfig.showLineNumbers ? .continuing : .off,
                showsPageBadge: true,
                showsContinuation: true,
                continuationLabel: String(
                    localized: "continues →",
                    comment: "Cue drawn on a carousel slide when another slide follows.")))
    }

    private var isExporting: Bool { progress != nil }

    private var rule: LocalizedStringKey? { EditorView.carouselRule(for: baseConfig) }

    private var pages: [CarouselPaginator.Slide] { outcome?.slides ?? [] }

    /// A refused capture has nothing to split, so nothing of it can reach a tile.
    private var request: SplitRequest {
        SplitRequest(split: split, code: rule == nil ? baseConfig.code : "")
    }

    private var filmstripInput: CarouselFilmstripModel.Input {
        CarouselFilmstripModel.Input(
            base: baseConfig, slides: pages, cues: cues, profile: profile)
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
            width: 440,
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
                if let rule {
                    Text(rule)
                        .font(.system(size: VitrineTokens.FontSize.body))
                        .foregroundStyle(VitrineTokens.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("carousel-rule")
                } else {
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
            }
        )
        .interactiveDismissDisabled(isExporting)
        // Synchronously, so the sheet doesn't open on an empty strip and a zero count.
        .onAppear { outcome = CarouselPaginator.Outcome(split: request.split, code: request.code) }
        .task(id: request) { await refreshSplit() }
        .task(id: filmstripInput) { await refreshSizeEstimate() }
        .task(id: OutputPlan(folder: folder, slideCount: pages.count)) {
            refreshPlannedFilenames()
        }
    }

    private var splitControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Stepper(
                    value: $split.linesPerSlide, in: CarouselPaginator.linesPerSlideRange
                ) {
                    Text("Lines per slide: \(split.linesPerSlide)")
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
            CarouselFilmstrip(
                input: filmstripInput, hasShortTail: outcome?.hasShortTail ?? false,
                model: filmstrip)
            HStack(spacing: 10) {
                Text("Slide size")
                Spacer(minLength: 0)
                Text(verbatim: CarouselPaginator.slideSizeLabel(ExportManager.carouselSlideSize))
                    .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    .accessibilityIdentifier("carousel-slide-size")
            }
            switchRow(
                "Prefer blank-line breaks", isOn: $split.prefersBlankLineBreaks,
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
                "Page badge “2 / 4”", isOn: $cues.showsPageBadge,
                identifier: "carousel-page-badge")
            switchRow(
                "“continues →” cue", isOn: $cues.showsContinuation,
                identifier: "carousel-continuation-cue")
        }
    }

    private var lineNumbersPicker: some View {
        Picker(
            "Line numbers",
            selection: Binding(
                get: { cues.lineNumbers ?? .off },
                set: { cues.lineNumbers = $0 })
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
        VStack(alignment: .leading, spacing: 6) {
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
            Text(verbatim: outputLine)
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.secondary)
                .monospacedDigit()
                // Two rows held from the start: the size arrives late and can wrap the line.
                .lineLimit(2, reservesSpace: true)
                .accessibilityIdentifier("carousel-output-summary")
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

    private var outputLine: String {
        let count = pages.count
        guard count > 0 else { return "" }
        let filenames =
            plannedFilenames.count == count
            ? plannedFilenames : CarouselPaginator.plannedFilenames(slideCount: count, in: nil)
        let summary = CarouselPaginator.outputSummary(
            filenames: filenames, estimatedBytes: bytesPerSlide.map { $0 * count })
        return summary + " · " + String(localized: "Existing files are kept")
    }

    private func refreshSplit() async {
        let request = request
        guard outcome?.split != request.split || outcome?.code != request.code else { return }
        let finished = await request.split.outcome(of: request.code)
        guard !Task.isCancelled else { return }
        outcome = finished
    }

    /// Waits out a stepper run before rendering, since the sample renders on the main actor.
    private func refreshSizeEstimate() async {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let estimate = await ExportManager.estimatedCarouselSlideBytes(
            baseConfig, slides: pages, cues: cues, profile: profile)
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
        // A click can land before the split catches up with the last stepper tick.
        let pages = request.split.slides(of: request.code)
        guard !pages.isEmpty else { return }
        guard let directory = folder ?? presentation.chooseDirectory(message: folderPrompt)
        else { return }

        failureNote = nil
        progress = (0, pages.count)
        Task {
            let result = await ExportManager.exportCarousel(
                baseConfig, slides: pages, cues: cues, to: directory, profile: profile,
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
