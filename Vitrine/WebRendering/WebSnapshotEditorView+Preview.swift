import AppKit
import SwiftUI

/// The Web Snapshot composer's center preview: the hero stage, the multi-size
/// filmstrip, and the loading / empty / error states.
extension WebSnapshotEditorView {
    // MARK: - Preview

    var previewStage: some View {
        GeometryReader { _ in
            ZStack {
                if model.isRendering {
                    loadingView
                } else if let asset = model.renderedAsset {
                    Image(nsImage: nsImage(from: asset))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(36)
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 16)
                } else if let error = model.errorMessage {
                    messageView(systemImage: "exclamationmark.triangle", text: error)
                } else {
                    emptyView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .background(VitrineTokens.Surface.stage)
        .layoutPriority(2)
        .accessibilityIdentifier("web-snapshot-preview-stage")
    }

    /// A filmstrip of the captured viewports in a multi-resolution batch (CS-044): one
    /// labeled thumbnail per size; tapping one shows it in the preview and makes it the
    /// single export target. Hidden for a single-viewport capture.
    @ViewBuilder
    var resultsFilmstrip: some View {
        if model.results.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: VitrineTokens.Spacing.xs + 2) {
                    if model.boardAsset != nil {
                        boardTile
                    }
                    ForEach(model.results) { result in
                        filmstripTile(result)
                    }
                }
                .padding(.horizontal, VitrineTokens.Spacing.md)
                .padding(.vertical, VitrineTokens.Spacing.xs + 2)
            }
            .background(VitrineTokens.Surface.window)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(VitrineTokens.Line.border)
                    .frame(height: Brand.Stroke.hairline)
            }
            .accessibilityIdentifier("web-snapshot-results")
        }
    }

    func filmstripTile(_ result: CapturedViewport) -> some View {
        resultTile(
            asset: result.thumbnailAsset,
            label: Text(verbatim: result.label),
            emphasized: false,
            isSelected: previewedKind == result.kind,
            identifier: "web-snapshot-result-\(result.kind.rawValue)",
            accessibilityLabel: Text(verbatim: result.label)
        ) {
            previewedKind = result.kind
            model.renderedAsset = result.asset
        }
    }

    /// The leading filmstrip tile for the composite responsive board (CS-044). Selected
    /// by default after a multi-size capture; tapping it shows the board in the preview
    /// and makes it the export target.
    @ViewBuilder
    var boardTile: some View {
        if let board = model.boardAsset {
            resultTile(
                asset: model.boardThumbnailAsset ?? board,
                label: Text("Board"),
                emphasized: true,
                isSelected: previewedKind == nil,
                identifier: "web-snapshot-result-board",
                accessibilityLabel: Text("Responsive board")
            ) {
                previewedKind = nil
                model.renderedAsset = board
            }
        }
    }

    /// One filmstrip thumbnail — a viewport result or the composite board. Tokenized
    /// preview tile with an accent ring when it is the selected export target, so both
    /// callers share one metric instead of hand-tuned sizes.
    private func resultTile(
        asset: RenderedAsset, label: Text, emphasized: Bool, isSelected: Bool,
        identifier: String, accessibilityLabel: Text, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: VitrineTokens.Spacing.xxs) {
                Image(nsImage: nsImage(from: asset))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Self.tileSize.width, height: Self.tileSize.height)
                    .background(VitrineTokens.Surface.stage)
                    .clipShape(
                        RoundedRectangle(cornerRadius: VitrineTokens.Radius.sm, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: VitrineTokens.Radius.sm, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? VitrineTokens.Accent.system : VitrineTokens.Line.border,
                                lineWidth: isSelected ? 2 : Brand.Stroke.hairline))
                label
                    .font(
                        .system(
                            size: VitrineTokens.FontSize.caption,
                            weight: emphasized ? .medium : .regular)
                    )
                    .foregroundStyle(
                        isSelected ? VitrineTokens.Text.primary : VitrineTokens.Text.secondary
                    )
                    .lineLimit(1)
            }
            .frame(width: Self.tileSize.width + VitrineTokens.Spacing.xxs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
    }

    /// The filmstrip thumbnail size (CS-044): a 16:10-ish tile big enough to read each
    /// viewport at a glance without crowding the strip.
    private static var tileSize: CGSize { CGSize(width: 92, height: 58) }

    /// The in-flight state: a spinner, a localized "loading locally" line, and — for a
    /// URL — the host shown verbatim, so it is always transparent which page is loading
    /// over the network (the non-invasive in-context network notice).
    var loadingView: some View {
        VStack(spacing: 14) {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(
                    model.mode == .url
                        ? "Loading the page locally in WebKit…" : "Rendering locally…"
                )
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VitrineTokens.Text.secondary)
                if let host = model.loadingHost {
                    Text(verbatim: host)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                }
                // Multi-size batches report which viewport is in flight, so a long
                // sequential capture shows forward motion instead of an opaque spinner.
                if let progress = model.renderProgress, progress.total > 1 {
                    Text("Capturing \(progress.current) of \(progress.total)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                        .monospacedDigit()
                }
            }
            // Announce the in-progress state as one element (the spinner alone says
            // nothing useful), and mark it live so VoiceOver re-reads it — kept separate
            // from the Cancel button so that stays an actionable control.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)

            cancelCaptureButton
        }
    }

    /// Stops a running capture so the user is never trapped waiting out a long
    /// multi-viewport batch (audit). Escape triggers it too.
    private var cancelCaptureButton: some View {
        Button(action: cancelCapture) {
            Text("Cancel")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VitrineTokens.Text.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(VitrineTokens.Chrome.tile))
                .overlay(
                    Capsule().strokeBorder(
                        VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("web-snapshot-cancel-button")
    }

    /// The empty state: a branded placeholder (mark + copy over the signature wash),
    /// matching the editor's empty state. Copy switches on the source mode.
    var emptyView: some View {
        EmptyStateView(
            title: model.mode == .url ? "Capture a webpage" : "Render HTML",
            message: model.mode == .url
                ? "Enter a URL, then Capture to snapshot the page."
                : "Paste HTML, then Render to snapshot it."
        )
    }

    /// The error state: an icon + message centered on the stage (the empty state uses
    /// the branded `EmptyStateView`; an error is not a "nothing here yet" state).
    func messageView(systemImage: String, text: String) -> some View {
        VStack(spacing: VitrineTokens.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(VitrineTokens.Text.tertiary)
            Text(text)
                .font(.system(size: VitrineTokens.FontSize.body))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(VitrineTokens.Spacing.xl)
    }
}
