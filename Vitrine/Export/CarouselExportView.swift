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
        var output: CarouselOutput
    }

    /// What the fitted type size depends on.
    private struct FitRequest: Equatable {
        var base: SnapshotConfig
        var slides: [CarouselPaginator.Slide]
        var cues: CarouselPaginator.Cues
        var size: CarouselSlideSize
    }

    private struct EstimateRequest: Equatable {
        var input: CarouselFilmstripModel.Input
        var output: CarouselOutput
    }

    /// The user's current snapshot (style + any brand watermark); each slide replaces
    /// only its `code` with that page's lines.
    let baseConfig: SnapshotConfig
    let profile: ColorProfile
    let feedback: FeedbackDisplay
    let presentation: BatchExportPresentation
    /// The split lives with the window, because the editor's dividers follow it too.
    @Bindable var splitModel: CarouselSplitModel

    @Environment(\.dismiss) private var dismiss

    @State private var cues: CarouselPaginator.Cues

    /// The latest finished split, which the sheet reads for everything it shows.
    @State private var outcome: CarouselPaginator.Outcome?

    @State private var filmstrip = CarouselFilmstripModel()

    /// The folder chosen in this sheet. Without one, confirming asks for it, because
    /// the sandbox grants no folder until the user picks it.
    @State private var folder: URL?

    /// The last fit and what it was measured for; tiles, the estimate and the export share it.
    @State private var fit: (request: FitRequest, value: CarouselFit)?

    /// The encoded size of every file, sampled from one slide.
    @State private var estimatedBytes: Int?

    /// Held in state so slides written during the export don't rename the line under it.
    @State private var plannedFilenames: [String] = []

    /// A short result line shown only when some slides failed to write.
    @State private var failureNote: String?

    /// Live "completed/total" while the batch runs; `nil` when idle.
    @State private var progress: (completed: Int, total: Int)?

    init(
        baseConfig: SnapshotConfig, profile: ColorProfile, feedback: FeedbackDisplay,
        presentation: BatchExportPresentation, splitModel: CarouselSplitModel
    ) {
        self.baseConfig = baseConfig
        self.profile = profile
        self.feedback = feedback
        self.presentation = presentation
        self.splitModel = splitModel
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

    private var request: SplitRequest {
        SplitRequest(
            split: splitModel.split, code: CarouselPaginator.splittableCode(of: baseConfig))
    }

    private var pages: [CarouselPaginator.Slide] { outcome?.slides(for: request.code) ?? [] }

    private var fitRequest: FitRequest {
        FitRequest(base: baseConfig, slides: pages, cues: cues, size: splitModel.size)
    }

    /// `nil` while the choices have moved on from the last fit.
    private var currentFit: CarouselFit? {
        guard let fit, fit.request == fitRequest else { return nil }
        return fit.value
    }

    private var filmstripInput: CarouselFilmstripModel.Input {
        CarouselFilmstripModel.Input(
            base: baseConfig, slides: pages, cues: cues, size: splitModel.size,
            fontSize: currentFit?.fontSize, profile: profile)
    }

    private var confirmTitle: LocalizedStringKey {
        guard folder != nil else { return "Export…" }
        let count = pages.count
        return count == 1 ? "Export 1 slide" : "Export \(count) slides"
    }

    var body: some View {
        ExportSheetScaffold(
            title: "Export carousel",
            subtitle: rule == nil
                ? "Split the snippet into numbered slides for a carousel post." : nil,
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
            showsConfirm: rule == nil,
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
                        sizeControls
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
        .onAppear {
            outcome = CarouselPaginator.Outcome(split: request.split, code: request.code)
            refreshFit()
        }
        .task(id: request) { await refreshSplit() }
        // A fit is several layouts on the main actor, so a stepper run settles first.
        .task(id: fitRequest) {
            guard currentFit == nil else { return }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            refreshFit()
        }
        // The tiles' input is everything a slide's pixels depend on, config and profile included.
        .task(id: EstimateRequest(input: filmstripInput, output: splitModel.output)) {
            await refreshSizeEstimate()
        }
        .task(id: OutputPlan(folder: folder, slideCount: pages.count, output: splitModel.output)) {
            refreshPlannedFilenames()
        }
    }

    private var splitControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Stepper(
                    value: $splitModel.split.linesPerSlide,
                    in: CarouselPaginator.linesPerSlideRange
                ) {
                    Text("Lines per slide: \(splitModel.split.linesPerSlide)")
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
            switchRow(
                "Prefer blank-line breaks", isOn: $splitModel.split.prefersBlankLineBreaks,
                identifier: "carousel-prefer-blank-lines")
            switchRow(
                "Show dividers in the code", isOn: $splitModel.showsDividers,
                identifier: "carousel-show-dividers")
        }
    }

    private var slideControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledRow("Line numbers") { lineNumbersPicker }
            switchRow(
                "Page badge “2 / 4”", isOn: $cues.showsPageBadge,
                identifier: "carousel-page-badge")
            switchRow(
                "“continues →” cue", isOn: $cues.showsContinuation,
                identifier: "carousel-continuation-cue")
        }
    }

    private var sizeControls: some View {
        labeledRow("Size") {
            Picker("Size", selection: $splitModel.size) {
                Text(verbatim: "LinkedIn 4:5").tag(CarouselSlideSize.linkedIn)
                Text(verbatim: "Instagram 1:1").tag(CarouselSlideSize.instagram)
                Text(verbatim: "X 16:9").tag(CarouselSlideSize.x)
                Text("Story 9:16").tag(CarouselSlideSize.story)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("carousel-slide-size")
        }
    }

    /// Segments share one width, so a long label can outgrow the row.
    private func labeledRow(
        _ title: LocalizedStringKey, @ViewBuilder control: () -> some View
    ) -> some View {
        let control = control()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text(title).fixedSize()
                Spacer(minLength: 0)
                control
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                control
            }
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
        // Paginated once here: every line below needs only the count.
        let slideCount = pages.count
        return VStack(alignment: .leading, spacing: 6) {
            labeledRow("Output") {
                Picker("Output", selection: $splitModel.output) {
                    Text("PNG set").tag(CarouselOutput.pngSet)
                    Text(verbatim: "PDF").tag(CarouselOutput.pdf)
                    Text("Both").tag(CarouselOutput.both)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("carousel-output-format")
            }
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
        let size = CarouselPaginator.slideSizeLabel(splitModel.size.pixels)
        return ([summary, size, String(localized: "Existing files are kept")] + overflowNote)
            .joined(separator: " · ")
    }

    private func refreshSplit() async {
        let request = request
        guard outcome?.split != request.split || outcome?.code != request.code else { return }
        let finished = await request.split.outcome(of: request.code)
        guard !Task.isCancelled else { return }
        outcome = finished
    }

    private func spokenOutputLine(slideCount: Int, estimatedBytes: Int?) -> String {
        guard slideCount > 0 else { return "" }
        let summary = CarouselPaginator.spokenOutputSummary(
            filenames: outputFilenames(slideCount: slideCount), estimatedBytes: estimatedBytes)
        let size = CarouselPaginator.slideSizeLabel(splitModel.size.pixels)
        return ([summary, size, String(localized: "Existing files are kept")] + overflowNote)
            .joined(separator: ", ")
    }

    private var overflowNote: [String] {
        currentFit?.overflows == true ? [String(localized: "Some lines don't fit the slide")] : []
    }

    private func refreshFit() {
        let request = fitRequest
        fit = (
            request,
            CarouselPaginator.fit(
                request.base, slides: request.slides, cues: request.cues, size: request.size)
        )
    }

    private func outputFilenames(slideCount: Int) -> [String] {
        let requested = CarouselPaginator.requestedFilenames(
            slideCount: slideCount, output: splitModel.output)
        return plannedFilenames.count == requested.count ? plannedFilenames : requested
    }

    /// Waits out a stepper run before rendering, since the sample renders on the main actor.
    private func refreshSizeEstimate() async {
        // The old sample described other slides, so the size is left out until the new one.
        estimatedBytes = nil
        guard let fit = currentFit else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let estimate = await ExportManager.estimatedCarouselBytes(
            baseConfig, slides: pages, cues: cues, size: splitModel.size, fit: fit,
            output: splitModel.output, profile: profile)
        guard !Task.isCancelled else { return }
        estimatedBytes = estimate
    }

    private func refreshPlannedFilenames() {
        plannedFilenames = CarouselPaginator.plannedFilenames(
            slideCount: pages.count, output: splitModel.output, in: folder)
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
        guard rule == nil else { return }
        // A click can land before the split catches up with the last stepper tick.
        let pages = request.split.slides(of: request.code)
        guard !pages.isEmpty else { return }
        guard let directory = folder ?? presentation.chooseDirectory(message: folderPrompt)
        else { return }

        let (size, output) = (splitModel.size, splitModel.output)
        let fileCount = CarouselPaginator.requestedFilenames(
            slideCount: pages.count, output: output
        ).count
        // The settled fit holds only for the split it was measured on.
        let fit = currentFit.flatMap { pages == fitRequest.slides ? $0 : nil }
        failureNote = nil
        progress = (0, ExportManager.carouselProgressUnits(slideCount: pages.count, output: output))
        Task {
            let result = await ExportManager.exportCarousel(
                baseConfig, slides: pages, cues: cues, size: size, fit: fit, output: output,
                to: directory, profile: profile,
                onProgress: { completed, total in progress = (completed, total) })
            progress = nil
            let completion = BatchExportCompletion(
                written: result.written,
                failed: result.failed,
                expected: fileCount,
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
