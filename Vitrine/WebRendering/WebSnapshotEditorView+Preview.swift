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
                HStack(spacing: 10) {
                    if model.boardAsset != nil {
                        boardTile
                    }
                    ForEach(model.results) { result in
                        filmstripTile(result)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
        let isSelected = previewedKind == result.kind
        return Button {
            previewedKind = result.kind
            model.renderedAsset = result.asset
        } label: {
            VStack(spacing: 4) {
                Image(nsImage: nsImage(from: result.thumbnailAsset))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 92, height: 58)
                    .background(VitrineTokens.Surface.stage)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? VitrineTokens.Accent.system : VitrineTokens.Line.border,
                                lineWidth: isSelected ? 2 : Brand.Stroke.hairline))
                Text(verbatim: result.label)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        isSelected ? VitrineTokens.Text.primary : VitrineTokens.Text.secondary
                    )
                    .lineLimit(1)
            }
            .frame(width: 96)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(result.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("web-snapshot-result-\(result.kind.rawValue)")
    }

    /// The leading filmstrip tile for the composite responsive board (CS-044). Selected
    /// by default after a multi-size capture; tapping it shows the board in the preview
    /// and makes it the export target.
    @ViewBuilder
    var boardTile: some View {
        if let board = model.boardAsset {
            let isSelected = previewedKind == nil
            Button {
                previewedKind = nil
                model.renderedAsset = board
            } label: {
                VStack(spacing: 4) {
                    Image(nsImage: nsImage(from: model.boardThumbnailAsset ?? board))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 92, height: 58)
                        .background(VitrineTokens.Surface.stage)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    isSelected
                                        ? VitrineTokens.Accent.system : VitrineTokens.Line.border,
                                    lineWidth: isSelected ? 2 : Brand.Stroke.hairline))
                    Text("Board")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(
                            isSelected ? VitrineTokens.Text.primary : VitrineTokens.Text.secondary
                        )
                        .lineLimit(1)
                }
                .frame(width: 96)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Responsive board"))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityIdentifier("web-snapshot-result-board")
        }
    }

    /// The in-flight state: a spinner, a localized "loading locally" line, and — for a
    /// URL — the host shown verbatim, so it is always transparent which page is loading
    /// over the network (the non-invasive in-context network notice).
    var loadingView: some View {
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
        }
        // Announce the in-progress state as one element (the spinner alone says
        // nothing useful), and mark it live so VoiceOver re-reads it.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    var emptyView: some View {
        messageView(
            systemImage: model.mode == .url ? "globe" : "chevron.left.forwardslash.chevron.right",
            text: model.mode == .url
                ? String(localized: "Enter a URL, then Capture to snapshot the page.")
                : String(localized: "Paste HTML, then Render to snapshot it."))
    }

    func messageView(systemImage: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(VitrineTokens.Text.tertiary)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(40)
    }
}
