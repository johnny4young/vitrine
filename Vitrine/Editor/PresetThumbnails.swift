import SwiftUI
import VitrineDomain
import VitrineRendering

/// The per-window thumbnails of the current capture under each style preset.
///
/// Rendering is main-actor work, so it never runs on a keystroke: it reads the preview's
/// debounced code, waits for a further quiet window, renders one tile per frame, stops when
/// the input changes, and skips any tile whose image inputs are unchanged.
@Observable
final class PresetThumbnailModel {
    struct Tile: Equatable, Identifiable {
        let preset: StylePreset
        let theme: Theme
        var id: String { preset.id }
    }

    /// The most tiles rendered per settle: the built-ins and the first saved presets. The
    /// toolbar menu still lists every preset.
    static let maximumTiles = 8
    static let tileAspect: CGFloat = 1.8
    static let pixelSize = CGSize(width: 320, height: 320 / tileAspect)
    private static let maximumLines = 6
    private static let maximumColumns = 48
    private static let maximumCharacters = 2_048

    /// Set by the preview synchronizer, so this model sees text only after its debounce.
    var stagedCode: String?
    var selectedPresetIDs: Set<String> = []
    private(set) var images: [String: CGImage] = [:]

    @ObservationIgnored private var renderedConfigs: [String: SnapshotConfig] = [:]
    @ObservationIgnored private var shownRedactions: [ClosedRange<Int>]?
    @ObservationIgnored private var shownMasked = false
    @ObservationIgnored var quietWindow: Duration
    private let frameGap: Duration
    private let render: (SnapshotConfig) -> CGImage?

    init(
        quietWindow: Duration = .milliseconds(300), frameGap: Duration = .milliseconds(16),
        render: @escaping (SnapshotConfig) -> CGImage? = {
            ExportManager.renderThumbnail($0, pixels: PresetThumbnailModel.pixelSize)
        }
    ) {
        self.quietWindow = quietWindow
        self.frameGap = frameGap
        self.render = render
    }

    /// The fields a preset leaves alone. Equal sources make identical thumbnails, so a slider
    /// tick or a moved arrow doesn't restart anything.
    static func source(style: SnapshotConfig, code: String) -> SnapshotConfig {
        var source = SnapshotConfig()
        source.code = code
        source.language = style.language
        source.terminalColumns = style.terminalColumns
        source.highlightedLineRanges = style.highlightedLineRanges
        source.redactedLineRanges = style.redactedLineRanges
        source.focusHighlightedLines = style.focusHighlightedLines
        source.diffDecorations = style.diffDecorations
        source.foregroundImage = style.foregroundImage
        source.imageFrame = style.imageFrame
        source.imageFrameAppearance = style.imageFrameAppearance
        source.annotations = style.annotations.filter { $0.kind == .blur }
        return source
    }

    /// A bounded excerpt that can't show what the capture hides. Redacted rows lose their text
    /// here as well as in the canvas. A blur box's position depends on layout, which a preset
    /// changes, so any blur box masks every row. An empty document shows the stage's sample.
    static func excerpt(of source: SnapshotConfig) -> SnapshotConfig {
        var excerpt = source
        excerpt.annotations = []
        let isTerminal = source.language == .terminal
        if !source.annotations.isEmpty
            || (isTerminal && source.code.utf8.count > HighlightPolicy.maximumCacheableByteCount)
        {
            excerpt.foregroundImage = nil
            excerpt.language = .plaintext
            excerpt.terminalColumns = nil
            excerpt.highlightedLineRanges = []
            excerpt.focusHighlightedLines = false
            excerpt.diffDecorations = false
            excerpt.redactedLineRanges = [1...3]
            excerpt.code = Array(repeating: SnapshotConfig.redactedLinePlaceholder, count: 3)
                .joined(separator: "\n")
            return excerpt
        }
        if source.usesImageContent {
            excerpt.code = ""
            excerpt.highlightedLineRanges = []
            excerpt.redactedLineRanges = []
            return excerpt
        }
        var bounded = EditorPreview.configForPreview(source)
        if !isTerminal { bounded.code = String(bounded.code.prefix(maximumCharacters)) }
        let rows = bounded.sidecarText.components(separatedBy: "\n").prefix(maximumLines)
            .map { $0.replacingOccurrences(of: "\r", with: "").prefix(maximumColumns) }
        func clip(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
            ranges.filter { $0.overlaps(1...rows.count) }.map { $0.clamped(to: 1...rows.count) }
        }
        excerpt.code = rows.joined(separator: "\n")
        excerpt.highlightedLineRanges = clip(source.highlightedLineRanges)
        excerpt.redactedLineRanges = clip(LineHighlight.normalize(source.redactedLineRanges))
        return excerpt
    }

    func refresh(source: SnapshotConfig, tiles: [Tile]) async {
        let excerpt = Self.excerpt(of: source)
        // A row just hidden must leave the tiles now, not after the quiet window.
        let isMasked = !source.annotations.isEmpty
        if shownRedactions != excerpt.redactedLineRanges || shownMasked != isMasked {
            images = [:]
            renderedConfigs = [:]
            shownRedactions = excerpt.redactedLineRanges
            shownMasked = isMasked
        }
        let live = Set(tiles.map(\.id))
        images = images.filter { live.contains($0.key) }
        renderedConfigs = renderedConfigs.filter { live.contains($0.key) }

        let planned = tiles.map { tile in
            var config = excerpt
            tile.preset.style.apply(to: &config) { _ in tile.theme }
            return (id: tile.id, config: config)
        }
        guard planned.contains(where: { renderedConfigs[$0.id] != $0.config }) else { return }
        try? await Task.sleep(for: quietWindow)
        for tile in planned where renderedConfigs[tile.id] != tile.config {
            guard !Task.isCancelled else { return }
            images[tile.id] = render(tile.config)
            renderedConfigs[tile.id] = tile.config
            try? await Task.sleep(for: frameGap)
        }
    }

    static func selection(style: SnapshotConfig, tiles: [Tile]) -> Set<String> {
        let current = StyleSnapshot(capturing: style)
        // Capturing swaps an image background for a gradient, which a preset could then match.
        let selected = tiles.filter {
            $0.preset.style == current && $0.preset.style.background == style.background
        }
        return Set(selected.map(\.id))
    }
}

/// The inspector's preset grid: every tile a fixed size, so nothing moves as images arrive.
struct PresetThumbnailSection: View {
    let settings: AppSettings
    let themes: CustomThemeStore
    let presets: PresetStore
    let model: PresetThumbnailModel

    private var tiles: [PresetThumbnailModel.Tile] {
        presets.allPresets.prefix(PresetThumbnailModel.maximumTiles).map {
            PresetThumbnailModel.Tile(preset: $0, theme: themes.theme(withID: $0.style.themeID))
        }
    }

    var body: some View {
        let tiles = tiles
        InspectorSection(title: Text("Presets")) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10
            ) {
                ForEach(tiles) { tile in
                    PresetThumbnailTile(
                        name: tile.preset.name, image: model.images[tile.id],
                        isSelected: model.selectedPresetIDs.contains(tile.id)
                    ) {
                        settings.applyStylePreset(tile.preset, themes: themes)
                    }
                    .accessibilityIdentifier("preset-thumbnail-\(tile.id)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inspector-preset-thumbnails")
        }
        .background {
            PresetThumbnailRefresher(settings: settings, model: model, tiles: tiles)
        }
    }
}

/// A childless view, so style ticks that re-evaluate it cost almost nothing.
private struct PresetThumbnailRefresher: View {
    let settings: AppSettings
    let model: PresetThumbnailModel
    let tiles: [PresetThumbnailModel.Tile]

    private struct Input: Equatable {
        let source: SnapshotConfig?
        let tiles: [PresetThumbnailModel.Tile]
    }

    var body: some View {
        let style = settings.style
        let source = model.stagedCode.map { PresetThumbnailModel.source(style: style, code: $0) }
        let selection = PresetThumbnailModel.selection(style: style, tiles: tiles)
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: Input(source: source, tiles: tiles)) {
                guard let source else { return }
                await model.refresh(source: source, tiles: tiles)
            }
            .onChange(of: selection, initial: true) { model.selectedPresetIDs = selection }
            .accessibilityHidden(true)
    }
}

private struct PresetThumbnailTile: View {
    let name: String
    let image: CGImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Color.clear
                    .aspectRatio(PresetThumbnailModel.tileAspect, contentMode: .fit)
                    .background(VitrineTokens.Surface.inset)
                    .overlay {
                        if let image {
                            Image(decorative: image, scale: 2)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? VitrineTokens.Accent.system : VitrineTokens.Line.border,
                                lineWidth: isSelected ? 2 : Brand.Stroke.hairline)
                    )
                Text(verbatim: name)
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(
                        isSelected ? VitrineTokens.Accent.systemText : VitrineTokens.Text.secondary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: name))
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
