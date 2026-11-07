import SwiftUI
import VitrineDomain
import VitrineRendering

/// The inspector rows that shape a diff: its layout, word marks, stats header, context,
/// numbering and hunks. Shown only for content that reads as a diff.
struct DiffViewInspectorRows: View {
    @Bindable var settings: AppSettings
    var feedback: FeedbackDisplay = .live

    var body: some View {
        if settings.style.diffOptionsApply {
            DiffSourceRows(settings: settings, feedback: feedback)
            InspectorRow(label: Text("Layout")) {
                TokenSegmentedPicker(
                    options: [
                        (DiffViewMode.unified, Text("Unified")),
                        (DiffViewMode.split, Text("Split")),
                    ],
                    selection: settings.diffViewSelection,
                    optionIdentifiers: ["diff-view-unified", "diff-view-split"]
                )
                .disabled(settings.style.diffLayoutIsLocked)
                .opacity(settings.style.diffLayoutIsLocked ? 0.5 : 1)
                .accessibilityLabel("Layout")
                .accessibilityIdentifier("diff-view-picker")
            }
            InspectorRow(label: Text("Word marks")) {
                Toggle("Word marks", isOn: settings.diffWordMarksEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(settings.style.diffLayoutIsLocked)
                    .accessibilityIdentifier("diff-word-marks-toggle")
            }
            InspectorRow(label: Text("Stats header")) {
                Toggle("Stats header", isOn: settings.diffStatsEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(settings.style.diffLayoutIsLocked)
                    .accessibilityIdentifier("diff-stats-toggle")
            }
            InspectorRow(label: Text("Context lines")) {
                HStack(spacing: 8) {
                    Slider(
                        value: settings.diffContextSliderValue,
                        in: AppSettings.diffContextSliderRange, step: 1
                    )
                    .frame(width: 90)
                    .disabled(settings.style.diffLayoutIsLocked)
                    .accessibilityLabel("Context lines")
                    .accessibilityValue(contextValue)
                    .accessibilityIdentifier("diff-context-slider")
                    contextValue
                        .font(
                            .system(size: VitrineTokens.FontSize.caption, design: .monospaced)
                        )
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            InspectorRow(label: Text("Numbering")) {
                TokenSegmentedPicker(
                    options: [
                        (DiffLineNumbers.rows, Text("Rows")),
                        (.old, Text("Old")),
                        (.new, Text("New")),
                        (.both, Text("Both")),
                    ],
                    selection: settings.diffLineNumbersSelection,
                    optionIdentifiers: [
                        "diff-line-numbers-rows", "diff-line-numbers-old", "diff-line-numbers-new",
                        "diff-line-numbers-both",
                    ]
                )
                .disabled(numberingIsLocked)
                .opacity(numberingIsLocked ? 0.5 : 1)
                .accessibilityLabel("Numbering")
                .accessibilityIdentifier("diff-line-numbers-picker")
            }
            DiffHunkPicker(settings: settings)
            DiffCommentInspectorRows(settings: settings)
            if settings.style.diffLayoutIsLocked {
                Text("Locked while a blur box is on the canvas.")
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .accessibilityIdentifier("diff-view-locked-note")
            }
        }
    }

    /// Numbering only changes a gutter the Line numbers switch shows.
    private var numberingIsLocked: Bool {
        settings.style.diffLayoutIsLocked || !settings.style.showLineNumbers
    }

    private var contextValue: Text {
        guard let lines = settings.style.diffContextLines else { return Text("All") }
        return Text(verbatim: "\(lines)")
    }
}

/// Where the diff came from, shown only for a CLI range or staged set. The sandboxed app
/// can't run Git, so Copy Command hands over the line that brings the diff back instead.
struct DiffSourceRows: View {
    @Bindable var settings: AppSettings
    var feedback: FeedbackDisplay

    var body: some View {
        if let source = settings.style.diffSource {
            InspectorRow(
                label: Text(String(localized: "diff.source.label", defaultValue: "Source"))
            ) {
                HStack(spacing: 6) {
                    Text(source.kind == .range ? "Revision range" : "Staged")
                        .font(.system(size: VitrineTokens.FontSize.caption))
                        .foregroundStyle(VitrineTokens.Text.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(VitrineTokens.Chrome.segmentTrack))
                        .accessibilityIdentifier("diff-source-chip")
                    Button("Copy Command") {
                        feedback(Self.copyCommand(source, settings: settings))
                    }
                    .controlSize(.small)
                    .help("Copy the command that renders this diff again")
                    .accessibilityIdentifier("diff-source-copy-command-button")
                }
            }
            let summary = [source.gitSummary, source.repository].compactMap { $0 }
                .joined(separator: " · ")
            Text(verbatim: summary)
                .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(Text(verbatim: summary))
                .accessibilityIdentifier("diff-source-summary")
            Toggle("Include in share links", isOn: sharesInLinks)
                .toggleStyle(.checkbox)
                .font(.system(size: VitrineTokens.FontSize.caption))
                .accessibilityIdentifier("diff-source-share-toggle")
            if !source.linkDetails.isEmpty {
                let details = source.linkDetails.joined(separator: ", ")
                Text("Shares: \(details)")
                    .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(Text(verbatim: details))
                    .accessibilityIdentifier("diff-source-share-details")
            }
        }
    }

    private var sharesInLinks: Binding<Bool> {
        Binding(
            get: { settings.style.diffSource?.sharesInLinks ?? false },
            set: { settings.style.diffSource?.sharesInLinks = $0 })
    }

    /// Pathspecs are root-relative, so the line runs at the root. A name from a share link is
    /// someone else's text and never goes into the instruction.
    static func copyCommand(
        _ source: DiffSource, settings: AppSettings,
        copy: (String, Bool) -> Bool = { ClipboardWriter.copy($0, concealed: $1) }
    ) -> Notifier.CaptureFeedback {
        let line = CLIReproductionCommand.line(source.refreshArguments)
        guard copy(line, settings.outputBehavior.concealClipboard) else {
            return Notifier.failure(String(localized: "Couldn't copy the command"))
        }
        guard let repository = source.repository, !source.isReceived,
            DiffSource.isValidRepository(repository)
        else {
            return Notifier.confirmation(
                String(localized: "Copied. Run it at the repository root."))
        }
        return Notifier.confirmation(
            String(localized: "Copied. Run it at the root of \(repository)."))
    }
}

/// One checkbox per hunk; an unchecked hunk folds to its counts on the card. Its own view
/// because it reads the document text, so a keystroke redraws only this list.
private struct DiffHunkPicker: View {
    @Bindable var settings: AppSettings

    var body: some View {
        let code = settings.documentCode
        let hunks = DiffLayoutCache.shared.hunks(in: code)
        if hunks.count > 1 {
            let lines = code.split(
                omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
            let shownCount = settings.style.diffShownHunks(count: hunks.count)?.count ?? hunks.count
            VStack(alignment: .leading, spacing: 4) {
                Text("Hunks")
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .foregroundStyle(VitrineTokens.Text.primary)
                ForEach(Array(hunks.enumerated()), id: \.offset) { offset, hunk in
                    let header =
                        lines.indices.contains(hunk.rows.lowerBound - 1)
                        ? String(lines[hunk.rows.lowerBound - 1]) : ""
                    let shown = settings.diffHunkShown(offset + 1, of: hunks.count)
                    HStack(spacing: 6) {
                        Toggle(isOn: shown) {
                            Text(verbatim: header)
                                .foregroundStyle(VitrineTokens.Text.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(
                            settings.style.diffLayoutIsLocked
                                || (shown.wrappedValue && shownCount == 1)
                        )
                        .accessibilityIdentifier("diff-hunk-toggle-\(offset + 1)")
                        Spacer(minLength: 0)
                        Text(verbatim: "+\(hunk.additions)")
                            .foregroundStyle(Color(nsColor: .systemGreen))
                        Text(verbatim: "−\(hunk.deletions)")
                            .foregroundStyle(Color(nsColor: .systemRed))
                    }
                    .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("diff-hunk-picker")
        }
    }
}
