import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VitrineDomain
import VitrineRendering

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

    @State private var preview = ComparisonBoardPreview()
    @State private var editingCaption: UUID?
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
        .tint(VitrineTokens.Accent.systemText)
        .task(id: draft.previewKey(profile: settings.export.colorProfile)) {
            await preview.refresh(
                isValid: draft.isValid,
                keepsLastFrame: editingCaption != nil,
                debounce: preview.debounce(dividerPercent: draft.dividerPercent),
                captionFrames: { draft.captionFrames },
                wipe: { draft.wipe },
                render: { try draft.composePreview(profile: settings.export.colorProfile) })
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

            Text(verbatim: boardSummary)
                .font(.system(size: VitrineTokens.FontSize.caption).monospacedDigit())
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .lineLimit(1)
                .accessibilityIdentifier("comparison-board-summary")

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
                if let asset = preview.asset,
                    preview.phase == .ready || preview.phase == .rendering
                        || editingCaption != nil
                {
                    let size = asset.pixelSize
                    let scale = min(
                        1,
                        max(0.01, (proxy.size.width - 72) / size.width),
                        max(0.01, (proxy.size.height - 72) / size.height))
                    Image(decorative: asset.cgImage, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .background {
                            if draft.background == .transparent { TransparencyGrid() }
                        }
                        .shadow(color: .black.opacity(0.28), radius: 24, y: 18)
                        .overlay {
                            captionLayer(
                                scale: scale,
                                canvas: CGSize(
                                    width: size.width * scale, height: size.height * scale))
                        }
                } else if preview.phase == .rendering {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityLabel("Rendering locally…")
                } else if preview.phase == .failed {
                    ContentUnavailableView(
                        "Couldn't render the comparison board",
                        systemImage: "exclamationmark.triangle")
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
        .onTapGesture { endEditing() }
    }

    private func captionLayer(scale: CGFloat, canvas: CGSize) -> some View {
        ZStack {
            if let wipe = preview.wipe {
                ComparisonBoardDividerHandle(
                    percent: $draft.dividerPercent, wipe: wipe, scale: scale,
                    isEditingCaption: editingCaption != nil, onEndEditing: endEditing)
            }
            ForEach(Array(draft.items.enumerated()), id: \.element.id) { index, item in
                if let frame = preview.captionFrames[item.id] {
                    CaptionHotspot(index: index, label: item.label) {
                        editingCaption = item.id
                    }
                    .frame(width: frame.width * scale, height: max(frame.height * scale, 18))
                    .position(x: frame.midX * scale, y: frame.midY * scale)
                }
            }
            if let id = editingCaption,
                let index = draft.items.firstIndex(where: { $0.id == id }),
                let frame = preview.captionFrames[id]
            {
                inlineCaptionEditor(
                    id: id, index: index, frame: frame, scale: scale, canvas: canvas)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    private func inlineCaptionEditor(
        id: UUID, index: Int, frame: CGRect, scale: CGFloat, canvas: CGSize
    ) -> some View {
        let width = max(frame.width * scale, 240)
        return ComparisonBoardCaptionEditor(
            captureID: id,
            index: index,
            label: labelBinding(for: id),
            detail: detailBinding(for: id),
            // A field being replaced by another caption's ends after the switch.
            onEnd: { ended in if editingCaption == ended { editingCaption = nil } }
        )
        .frame(width: width)
        // The rendered caption can be far smaller than a usable field on a large board.
        .position(
            x: Self.clamped(frame.midX * scale, span: width, within: canvas.width),
            y: Self.clamped(
                frame.midY * scale, span: ComparisonBoardCaptionEditor.height,
                within: canvas.height))
    }

    private static func clamped(_ center: CGFloat, span: CGFloat, within limit: CGFloat) -> CGFloat
    {
        guard span < limit else { return limit / 2 }
        return min(max(center, span / 2), limit - span / 2)
    }

    private func endEditing() {
        focusedField = nil
        editingCaption = nil
    }

    private var boardSummary: String {
        let size = draft.metrics.pointSize
        let captures = String(localized: "\(draft.items.count) captures")
        return "\(captures) · \(Int(size.width)) × \(Int(size.height))"
            + " · \(Int(draft.resolvedExportScale))×"
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.lg) {
                if !draft.variants.isEmpty {
                    inspectorSection("Theme variants") { variantChips }
                }

                inspectorSection("Layout") {
                    // Wraps rather than overflows when five labels outgrow the column.
                    TokenSegmentedPicker(
                        options: draft.availableLayouts.map { ($0, Text($0.title)) },
                        selection: $draft.layout,
                        optionIdentifiers: draft.availableLayouts.map {
                            "comparison-board-layout-\($0.rawValue)"
                        }
                    )
                    .accessibilityLabel("Layout")
                    .accessibilityIdentifier("comparison-board-layout-picker")
                }

                inspectorSection("Board size") {
                    Picker("Board size", selection: $draft.size) {
                        ForEach(ComparisonBoard.Size.allCases, id: \.self) { size in
                            size.title.tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("comparison-board-size-picker")
                }

                // A wipe has one card and no gap, so the divider takes this row.
                if draft.metrics.isWipe {
                    InspectorRow(label: Text("Divider")) {
                        ValueSlider(
                            label: "Divider position",
                            value: Binding(
                                get: { Double(draft.dividerPercent) },
                                set: { draft.dividerPercent = Int($0.rounded()) }),
                            range: Double(
                                ComparisonBoard.dividerRange.lowerBound)...Double(
                                    ComparisonBoard.dividerRange.upperBound),
                            step: 1,
                            identifier: "comparison-board-divider-slider")
                    }
                } else {
                    InspectorRow(label: Text("Gap")) {
                        ValueSlider(
                            label: "Gap",
                            value: Binding(
                                get: { Double(draft.gap) },
                                set: { draft.gap = CGFloat($0) }),
                            range: Double(
                                ComparisonBoard.gapRange.lowerBound)...Double(
                                    ComparisonBoard.gapRange.upperBound),
                            step: 2,
                            identifier: "comparison-board-gap-slider")
                    }
                }

                InspectorRow(label: Text("Board background")) {
                    HStack(spacing: VitrineTokens.Spacing.xs) {
                        ForEach(ComparisonBoard.Background.allCases, id: \.self) { background in
                            BackgroundSwatch(
                                background: background,
                                isSelected: draft.background == background
                            ) {
                                draft.background = background
                            }
                        }
                    }
                }

                InspectorRow(label: Text("Footer line")) {
                    Toggle("Footer line", isOn: $draft.showsFooter)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("comparison-board-footer-toggle")
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

    private var variantChips: some View {
        FlowLayout(spacing: VitrineTokens.Spacing.sm, lineSpacing: VitrineTokens.Spacing.sm) {
            ForEach(draft.variants) { variant in
                ThemeChip(theme: variant.theme, isSelected: draft.isOnBoard(variant)) {
                    if editingCaption == variant.id { endEditing() }
                    draft.toggleVariant(id: variant.id)
                }
                .disabled(!draft.canToggle(variant))
                .accessibilityIdentifier("comparison-board-variant-\(variant.theme.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comparison-board-variants")
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
                    if editingCaption == item.id { endEditing() }
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
            feedback(
                ExportFeedback.copyOutcome(
                    ExportManager.copyPNGToPasteboardOutcome(
                        asset.cgImage, concealed: settings.outputBehavior.concealClipboard)))
        } catch ComparisonBoardComposer.CompositionError.renderFailure(let error) {
            feedback(ExportFeedback.renderFailure(error))
        } catch {
            feedback(boardFailure)
        }
    }

    private func saveBoard() {
        let payload: (data: Data, type: UTType, ext: String)
        do {
            payload = try ComparisonBoardExporter.encodedPayloadChecked(
                for: draft,
                format: settings.export.format,
                profile: settings.export.colorProfile)
        } catch let error {
            feedback(ExportFeedback.renderFailure(error))
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
        } catch ComparisonBoardComposer.CompositionError.renderFailure(let error) {
            feedback(ExportFeedback.renderFailure(error))
        } catch {
            feedback(ExportFeedback.shareFailure)
        }
    }

    private func renderedBoard() throws -> RenderedAsset {
        try draft.compose(
            scale: draft.resolvedExportScale,
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
        case .slider: "Slider"
        }
    }
}

extension ComparisonBoard.Size {
    fileprivate var title: Text {
        switch self {
        case .automatic: Text("Auto")
        case .widescreen: Text(verbatim: "16:10")
        case .openGraph: Text(verbatim: "OG")
        case .square: Text("Square")
        }
    }
}

extension ComparisonBoard.Background {
    fileprivate var title: Text {
        switch self {
        case .vitrine: Text(verbatim: "Vitrine")
        case .card: Text("Card")
        case .aurora: Text(verbatim: "Aurora")
        case .transparent: Text("Transparent")
        }
    }
}

private struct BackgroundSwatch: View {
    let background: ComparisonBoard.Background
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        FillSwatch(title: background.title, isSelected: isSelected, action: action) {
            if background == .transparent {
                TransparencyGrid(cell: 6)
            } else {
                ComparisonBoardComposer.BackgroundFill(background: background)
            }
        }
        .accessibilityIdentifier("comparison-board-background-\(background.rawValue)")
    }
}

/// A clickable region over a caption drawn into the preview image.
private struct CaptionHotspot: View {
    let index: Int
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.sm, style: .continuous)
                .strokeBorder(.white.opacity(isHovered ? 0.5 : 0), lineWidth: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Edit caption \(index + 1)")
        .accessibilityLabel("Edit caption \(index + 1)")
        .accessibilityValue(Text(verbatim: label))
        .accessibilityIdentifier("comparison-board-caption-\(index)")
    }
}
