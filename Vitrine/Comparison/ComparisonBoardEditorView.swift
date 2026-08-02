import AppKit
import SwiftUI

/// A session-only editor for arranging and exporting two to four recent captures.
struct ComparisonBoardEditorView: View {
    private enum Field: Hashable {
        case label(UUID)
        case detail(UUID)
    }

    @Bindable var draft: ComparisonBoardDraft
    let environment: AppEnvironment
    let feedback: FeedbackDisplay
    let presentation: ComparisonBoardPresentation

    @State private var preview: RenderedAsset?
    @FocusState private var focusedField: Field?

    var settings: AppSettings { environment.appSettings }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                previewStage
                inspector
                    .frame(width: 320)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 860, minHeight: 560)
        .background(VitrineTokens.Surface.window)
        .tint(VitrineTokens.Accent.system)
        .task(id: draft.previewKey(profile: settings.export.colorProfile)) {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            preview = try? draft.compose(scale: 1, profile: settings.export.colorProfile)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: VitrineTokens.Spacing.xs) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 18, weight: .semibold))
                Text("Comparison Board")
                    .font(.system(size: VitrineTokens.FontSize.headline, weight: .bold))
            }
            .foregroundStyle(VitrineTokens.Text.primary)

            Spacer(minLength: 0)

            GlassIconButton(systemImage: "square.and.arrow.down", action: saveBoard)
                .help("Render and save the board as a file")
                .disabled(!draft.isValid)
                .accessibilityLabel(VitrineCommand.saveImage.accessibilityLabel)
                .accessibilityIdentifier("comparison-board-save-button")

            GlassIconButton(systemImage: "square.and.arrow.up", action: shareBoard)
                .help("Share the rendered board")
                .disabled(!draft.isValid)
                .accessibilityLabel(VitrineCommand.shareImage.accessibilityLabel)
                .accessibilityIdentifier("comparison-board-share-button")

            GradientCTAButton {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                Text("Copy board")
            } action: {
                copyBoard()
            }
            .help("Render and copy the board to the clipboard")
            .disabled(!draft.isValid)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .accessibilityIdentifier("comparison-board-copy-button")
        }
        .padding(.vertical, 10)
        .padding(.trailing, VitrineTokens.Spacing.md)
        .padding(.leading, 86)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VitrineTokens.Line.border)
                .frame(height: Brand.Stroke.hairline)
        }
        .accessibilityContainerIdentifier("comparison-board-toolbar")
        .accessibilityLabel("Toolbar")
    }

    private var previewStage: some View {
        GeometryReader { proxy in
            ZStack {
                if let preview {
                    let size = preview.pixelSize
                    let scale = min(
                        1,
                        max(0.01, (proxy.size.width - 72) / size.width),
                        max(0.01, (proxy.size.height - 72) / size.height))
                    Image(decorative: preview.cgImage, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .shadow(color: .black.opacity(0.28), radius: 24, y: 18)
                } else if draft.isValid {
                    // A valid board with no preview yet is simply still rendering
                    // (the debounce, or the first pass after the window opened) —
                    // claiming it "needs complete labels" here would be false.
                    ProgressView()
                        .controlSize(.large)
                } else {
                    ContentUnavailableView(
                        "Board needs complete labels",
                        systemImage: "rectangle.on.rectangle.slash",
                        description: Text("Add a short label to every capture to preview it."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .background(VitrineTokens.Surface.stage)
        .layoutPriority(2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Board preview")
        .accessibilityIdentifier("comparison-board-preview-stage")
        .onTapGesture { focusedField = nil }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.lg) {
                inspectorSection("Layout") {
                    Picker("Layout", selection: $draft.layout) {
                        ForEach(ComparisonBoard.Layout.allCases, id: \.self) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("comparison-board-layout-picker")
                }

                inspectorSection("Captures") {
                    ForEach(Array(draft.items.enumerated()), id: \.element.id) { index, item in
                        VStack(spacing: VitrineTokens.Spacing.lg) {
                            captureEditor(item: item, index: index)
                            if index < draft.items.count - 1 { Divider() }
                        }
                    }
                }
            }
            .padding(VitrineTokens.Spacing.lg)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(VitrineTokens.Line.border)
                .frame(width: Brand.Stroke.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
        .accessibilityIdentifier("comparison-board-inspector")
    }

    private func captureEditor(item: ComparisonBoardDraft.Item, index: Int) -> some View {
        VStack(alignment: .leading, spacing: VitrineTokens.Spacing.sm) {
            HStack {
                Text("Capture \(index + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                Spacer()
                Button {
                    draft.moveItem(id: item.id, offset: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(index == 0)
                .help("Move capture earlier")
                .accessibilityLabel("Move capture earlier")
                Button {
                    draft.moveItem(id: item.id, offset: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(index == draft.items.count - 1)
                .help("Move capture later")
                .accessibilityLabel("Move capture later")
                Button(role: .destructive) {
                    draft.removeItem(id: item.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .disabled(draft.items.count == ComparisonBoard.itemCountRange.lowerBound)
                .help("Remove capture from board")
                .accessibilityLabel("Remove capture from board")
            }
            TextField("Label", text: labelBinding(for: item.id))
                .focused($focusedField, equals: .label(item.id))
                .accessibilityIdentifier("comparison-board-label-\(index)")
            TextField("Optional detail", text: detailBinding(for: item.id))
                .focused($focusedField, equals: .detail(item.id))
                .accessibilityIdentifier("comparison-board-detail-\(index)")
        }
    }

    private func inspectorSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: VitrineTokens.Spacing.sm) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .textCase(.uppercase)
            content()
        }
    }

    private func labelBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { draft.items.first(where: { $0.id == id })?.label ?? "" },
            set: { value in
                guard let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
                draft.items[index].label = String(value.prefix(ComparisonBoard.maximumLabelLength))
            })
    }

    private func detailBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { draft.items.first(where: { $0.id == id })?.detail ?? "" },
            set: { value in
                guard let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
                draft.items[index].detail = String(
                    value.prefix(ComparisonBoard.maximumDetailLength))
            })
    }

    private func copyBoard() {
        do {
            let asset = try renderedBoard()
            feedback(ExportFeedback.copyOutcome(ExportManager.copyPNGToPasteboard(asset.cgImage)))
        } catch {
            feedback(boardFailure)
        }
    }

    private func saveBoard() {
        let payload = ExportManager.encodedPayload(
            settings.export.format,
            png: { try? renderedBoard().cgImage },
            // The PDF is a raster page, so it embeds the same export-scale render the
            // PNG path saves — a format switch must not silently drop resolution to 1×.
            pdf: {
                guard let image = try? renderedBoard() else { return nil }
                return ExportManager.pdfData(from: image.cgImage)
            })
        guard let payload else {
            feedback(boardFailure)
            return
        }
        if let outcome = ExportFeedback.saveOutcome(
            ExportManager.saveToFile(payload: payload, suggestedName: "vitrine-comparison"))
        {
            feedback(outcome)
        }
    }

    private func shareBoard() {
        do {
            let asset = try renderedBoard()
            presentation.share(
                NSImage(
                    cgImage: asset.cgImage,
                    size: NSSize(width: asset.pixelWidth, height: asset.pixelHeight)))
        } catch {
            feedback(ExportFeedback.shareFailure)
        }
    }

    private func renderedBoard() throws -> RenderedAsset {
        try draft.compose(
            scale: draft.exportScale,
            profile: settings.export.colorProfile)
    }

    private var boardFailure: Notifier.CaptureFeedback {
        Notifier.failure(String(localized: "Couldn't render the comparison board"))
    }
}

extension ComparisonBoard.Layout {
    fileprivate var title: LocalizedStringKey {
        switch self {
        case .automatic: "Auto"
        case .horizontal: "Row"
        case .vertical: "Column"
        case .grid: "Grid"
        }
    }
}
