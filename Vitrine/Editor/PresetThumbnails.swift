import SwiftUI
import VitrineDomain
import VitrineRendering

/// The per-window thumbnails of the current capture under each style preset.
///
/// Rendering is main-actor work, so it never runs on a keystroke: it reads the preview's
/// debounced code, waits for a further quiet window, renders one tile per frame, stops when
/// the input changes, and skips any tile whose image inputs are unchanged. Tiles show a
/// preset's style on an excerpt, not the exact composition an export would have.
@Observable
final class PresetThumbnailModel {
    struct Tile: Equatable, Identifiable {
        let preset: StylePreset
        let theme: Theme
        var id: String { preset.id }
    }

    /// Two rows of three. The toolbar menu still lists every preset.
    static let maximumTiles = 6
    static let tileAspect: CGFloat = 1.8
    static let pixelSize = CGSize(width: 240, height: 240 / tileAspect)
    /// Undotted, because `@AppStorage` observes through KVO, which reads dots as a key path.
    static let expandedStorageKey = "editorPresetThumbnailsExpanded"
    private static let maximumLines = 6
    private static let maximumColumns = 48
    private static let maximumCharacters = 2_048

    /// Set by the preview synchronizer, so this model sees text only after its debounce.
    var stagedCode: String?
    /// The document generation `stagedCode` was handed off in.
    var stagedGeneration = 0
    /// Counts handoffs, because the text can settle back to what it already was.
    private(set) var stagedHandoffs = 0
    var selectedPresetIDs: Set<String> = []
    private(set) var images: [String: CGImage] = [:]

    @ObservationIgnored private var renderedConfigs: [String: SnapshotConfig] = [:]
    @ObservationIgnored private var shownRedactions: [ClosedRange<Int>] = []
    @ObservationIgnored private var shownMasked = false
    @ObservationIgnored private var shownCrop = TerminalCrop()
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

    func stage(_ code: String, generation: Int) {
        stagedCode = code
        stagedGeneration = generation
        stagedHandoffs += 1
    }

    /// The source for the current style, or `nil` while the staged code still belongs to a
    /// document that was replaced: new marks must never pair with the old text.
    func settledSource(style: SnapshotConfig, documentGeneration: Int) -> SnapshotConfig? {
        guard let stagedCode, stagedGeneration == documentGeneration else { return nil }
        return Self.source(style: style, code: stagedCode)
    }

    /// The fields a preset leaves alone. Equal sources make identical thumbnails, so a slider
    /// tick or a moved arrow doesn't restart anything.
    static func source(style: SnapshotConfig, code: String) -> SnapshotConfig {
        var source = SnapshotConfig()
        source.code = code
        source.language = style.language
        source.terminalColumns = style.terminalColumns
        source.terminalCrop = style.terminalCrop
        source.highlightedLineRanges = style.highlightedLineRanges
        source.redactedLineRanges = style.redactedLineRanges
        source.focusHighlightedLines = style.focusHighlightedLines
        source.diffDecorations = style.diffDecorations
        source.foregroundImage = style.foregroundImage
        source.imageFrame = style.imageFrame
        source.imageFrameAppearance = style.imageFrameAppearance
        // A sticker can cover part of an image. On code it masks nothing, so it isn't kept.
        source.annotations = style.annotations.filter {
            $0.kind == .blur || ($0.kind == .sticker && style.usesImageContent)
        }
        return source
    }

    /// A bounded excerpt that can't show what the capture hides. Redacted rows lose their text
    /// here as well as in the canvas. A cover's position depends on layout, which a preset
    /// changes, so any kept annotation masks every row. An empty document shows the sample.
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
        // The rows are already cropped, so marks are renumbered to them.
        let crop = source.activeTerminalCrop
        excerpt.code = rows.joined(separator: "\n")
        excerpt.terminalCrop = TerminalCrop()
        excerpt.firstLineNumber = source.firstLineNumber + crop.rowOffset
        excerpt.highlightedLineRanges = clip(crop.localRanges(source.highlightedLineRanges))
        excerpt.redactedLineRanges = clip(
            crop.localRanges(LineHighlight.normalize(source.redactedLineRanges)))
        return excerpt
    }

    func refresh(source: SnapshotConfig, tiles: [Tile]) async {
        // A row just hidden or cropped out must leave the tiles now, not after the quiet window.
        let crop = source.activeTerminalCrop
        let redactions = crop.localRanges(LineHighlight.normalize(source.redactedLineRanges))
            .filter { $0.lowerBound <= Self.maximumLines }
        let isMasked = !source.annotations.isEmpty
        if shownRedactions != redactions || shownMasked != isMasked || shownCrop != crop {
            releaseImages()
            shownCrop = crop
            shownRedactions = redactions
            shownMasked = isMasked
        }
        let live = Set(tiles.map(\.id))
        if images.keys.contains(where: { !live.contains($0) }) {
            images = images.filter { live.contains($0.key) }
        }
        renderedConfigs = renderedConfigs.filter { live.contains($0.key) }

        // The excerpt can parse a whole terminal capture, so it waits for quiet too.
        try? await Task.sleep(for: quietWindow)
        guard !Task.isCancelled else { return }
        let excerpt = Self.excerpt(of: source)
        for tile in tiles {
            var config = excerpt
            tile.preset.style.apply(to: &config) { _ in tile.theme }
            guard renderedConfigs[tile.id] != config else { continue }
            guard !Task.isCancelled else { return }
            images[tile.id] = render(config)
            renderedConfigs[tile.id] = config
            try? await Task.sleep(for: frameGap)
        }
    }

    /// Drops every image, so reopening the section can't show one from before a later redaction.
    func releaseImages() {
        if !images.isEmpty { images = [:] }
        renderedConfigs = [:]
    }

    /// The presets whose style is the current one.
    static func selection(style: SnapshotConfig, presets: [StylePreset]) -> Set<String> {
        let current = StyleSnapshot(capturing: style)
        // Capturing swaps an image background for a gradient, which a preset could then match.
        let selected = presets.filter {
            $0.style == current && $0.style.background == style.background
        }
        return Set(selected.map(\.id))
    }

    /// The built-ins, then the matching saved preset, then the newest saved ones, within the cap.
    static func tilePresets(saved: [StylePreset], selected: Set<String>) -> [StylePreset] {
        let newestFirst = Array(saved.reversed())
        let matching = newestFirst.first { selected.contains($0.id) }
        let others = newestFirst.filter { $0.id != matching?.id }
        let chosen = (matching.map { [$0] } ?? []) + others
        return Array((StylePreset.builtIns + chosen).prefix(maximumTiles))
    }
}

/// The collapsed-by-default Presets row. The grid and its rendering exist only while open.
struct PresetThumbnailSection: View {
    let settings: AppSettings
    let themes: CustomThemeStore
    let presets: PresetStore
    let model: PresetThumbnailModel
    @Binding var isExpanded: Bool

    private var currentPresetName: String? {
        presets.allPresets.first { model.selectedPresetIDs.contains($0.id) }?.name
    }

    var body: some View {
        InspectorDisclosure(
            label: Text("Presets"), summary: currentPresetName,
            identifier: "inspector-disclosure-presets", isExpanded: $isExpanded
        ) {
            PresetThumbnailGrid(settings: settings, themes: themes, presets: presets, model: model)
        }
        .background {
            PresetSelectionTracker(settings: settings, presets: presets, model: model)
        }
    }
}

/// Childless, so style ticks that re-evaluate it cost almost nothing.
private struct PresetSelectionTracker: View {
    let settings: AppSettings
    let presets: PresetStore
    let model: PresetThumbnailModel

    var body: some View {
        let selection = PresetThumbnailModel.selection(
            style: settings.style, presets: presets.allPresets)
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: selection, initial: true) { model.selectedPresetIDs = selection }
            .accessibilityHidden(true)
    }
}

/// Every tile a fixed size, so nothing moves as images arrive.
private struct PresetThumbnailGrid: View {
    let settings: AppSettings
    let themes: CustomThemeStore
    let presets: PresetStore
    let model: PresetThumbnailModel

    private var tiles: [PresetThumbnailModel.Tile] {
        PresetThumbnailModel.tilePresets(
            saved: presets.userPresets, selected: model.selectedPresetIDs
        ).map {
            PresetThumbnailModel.Tile(preset: $0, theme: themes.theme(withID: $0.style.themeID))
        }
    }

    var body: some View {
        let tiles = tiles
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10
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
        .background {
            PresetThumbnailRefresher(settings: settings, model: model, tiles: tiles)
        }
        .onDisappear { model.releaseImages() }
    }
}

/// Childless, so style ticks that re-evaluate it cost almost nothing.
private struct PresetThumbnailRefresher: View {
    let settings: AppSettings
    let model: PresetThumbnailModel
    let tiles: [PresetThumbnailModel.Tile]

    private struct Input: Equatable {
        let source: SnapshotConfig?
        let tiles: [PresetThumbnailModel.Tile]
    }

    var body: some View {
        let source = model.settledSource(
            style: settings.style, documentGeneration: settings.documentGeneration)
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: Input(source: source, tiles: tiles)) {
                guard let source else { return }
                await model.refresh(source: source, tiles: tiles)
            }
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
