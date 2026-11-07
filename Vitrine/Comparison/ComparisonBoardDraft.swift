import CoreGraphics
import Foundation
import Observation
import VitrineDomain
import VitrineRendering

/// Session-only editing state for a comparison board.
///
/// A draft owns finished capture pixels, user-visible captions, and layout options only.
/// It is never encoded into defaults or Recents, and closing its window releases the
/// entire value.
@Observable
final class ComparisonBoardDraft {
    struct Item: Identifiable, Sendable {
        let id: UUID
        let asset: RenderedAsset
        var label: String
        var detail: String
    }

    /// One theme of a single capture, rendered when the board opened. Only these pixels and
    /// captions stay, so adding a variant back never re-reads the source.
    struct Variant: Identifiable {
        let id: UUID
        let theme: Theme
        let asset: RenderedAsset
        /// The caption it had when it last left the board.
        var label: String
        var detail: String
    }

    enum CreationError: Error, Equatable {
        case invalidSelection(Int)
        case invalidRenderScale(CGFloat)
        case renderFailure(index: Int, RenderBudgetError)
    }

    struct PreviewKey: Hashable {
        let layout: ComparisonBoard.Layout
        let size: ComparisonBoard.Size
        let gap: CGFloat
        let background: ComparisonBoard.Background
        let showsFooter: Bool
        let dividerPercent: Int
        let itemIDs: [Item.ID]
        let captions: [String]
        let profile: ColorProfile
    }

    var items: [Item]
    var layout: ComparisonBoard.Layout = .automatic
    var size: ComparisonBoard.Size = .automatic
    var gap: CGFloat = ComparisonBoard.defaultGap
    var background: ComparisonBoard.Background = .vitrine
    var showsFooter = false
    var dividerPercent = ComparisonBoard.defaultDividerPercent
    let exportScale: CGFloat
    /// Empty unless the board was made from one capture's theme variants.
    private(set) var variants: [Variant] = []

    init(
        captures: [Capture],
        baseConfig: SnapshotConfig,
        themes: ThemeLookup = Theme.theme(withID:),
        profile: ColorProfile,
        renderScale: CGFloat = 1,
        render: (SnapshotConfig, CGFloat, ColorProfile) throws(RenderBudgetError) -> CGImage = {
            config, scale, profile in
            try ExportManager.renderCGImageChecked(config, scale: scale, profile: profile)
        }
    ) throws {
        guard ComparisonBoard.itemCountRange.contains(captures.count) else {
            throw CreationError.invalidSelection(captures.count)
        }
        exportScale = try Self.validated(renderScale)
        items = try captures.enumerated().map { index, capture in
            let config = capture.applying(to: baseConfig, themes: themes)
            return Item(
                id: UUID(),
                asset: try Self.render(config, at: index, renderScale, profile, render),
                label: Self.defaultLabel(index: index, count: captures.count),
                detail: "\(capture.language.displayName) · \(config.theme.displayName)")
        }
    }

    /// Renders one capture in each theme up front and puts the first four on the board.
    init(
        variantsOf config: SnapshotConfig,
        themes: [Theme],
        profile: ColorProfile,
        renderScale: CGFloat = 1,
        render: (SnapshotConfig, CGFloat, ColorProfile) throws(RenderBudgetError) -> CGImage = {
            config, scale, profile in
            try ExportManager.renderCGImageChecked(config, scale: scale, profile: profile)
        }
    ) throws {
        var seen = Set<String>()
        let unique = themes.filter { seen.insert($0.id).inserted }
        guard unique.count >= ComparisonBoard.itemCountRange.lowerBound else {
            throw CreationError.invalidSelection(unique.count)
        }
        exportScale = try Self.validated(renderScale)
        let detail = config.language.displayName
        let rendered = try unique.enumerated().map { index, theme in
            var themed = config
            themed.theme = theme
            return Variant(
                id: UUID(), theme: theme,
                asset: try Self.render(themed, at: index, renderScale, profile, render),
                label: Self.label(for: theme), detail: detail)
        }
        items = rendered.prefix(ComparisonBoard.itemCountRange.upperBound).map(Self.item)
        variants = rendered
    }

    /// The capture's own theme leads, then a fixed dark and light spread to compare it with.
    static func variantThemes(startingWith source: Theme) -> [Theme] {
        [source]
            + [Theme.oneDark, .oneLight, .dracula, .github, .githubDark].filter {
                $0.id != source.id
            }
    }

    private static func validated(_ scale: CGFloat) throws -> CGFloat {
        guard scale.isFinite, (1...3).contains(scale) else {
            throw CreationError.invalidRenderScale(scale)
        }
        return scale
    }

    private static func render(
        _ config: SnapshotConfig, at index: Int, _ scale: CGFloat, _ profile: ColorProfile,
        _ render: (SnapshotConfig, CGFloat, ColorProfile) throws(RenderBudgetError) -> CGImage
    ) throws -> RenderedAsset {
        do throws(RenderBudgetError) {
            return RenderedAsset(cgImage: try render(config, scale, profile), profile: profile)
        } catch let error {
            throw CreationError.renderFailure(index: index, error)
        }
    }

    private static func item(_ variant: Variant) -> Item {
        Item(id: variant.id, asset: variant.asset, label: variant.label, detail: variant.detail)
    }

    /// A custom theme's name can be any length, but a caption must pass board validation.
    static func label(for theme: Theme) -> String {
        let name = theme.displayName.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return String((name.isEmpty ? theme.id : name).prefix(ComparisonBoard.maximumLabelLength))
    }

    func isOnBoard(_ variant: Variant) -> Bool {
        items.contains { $0.id == variant.id }
    }

    /// A variant joins or leaves within the board's two-to-four range.
    func canToggle(_ variant: Variant) -> Bool {
        isOnBoard(variant)
            ? items.count > ComparisonBoard.itemCountRange.lowerBound
            : items.count < ComparisonBoard.itemCountRange.upperBound
    }

    func toggleVariant(id: Variant.ID) {
        guard let variant = variants.first(where: { $0.id == id }), canToggle(variant) else {
            return
        }
        if isOnBoard(variant) {
            removeItem(id: id)
        } else {
            let order = { (id: Item.ID) in self.variants.firstIndex { $0.id == id } ?? .max }
            let rank = order(id)
            let slot = items.firstIndex { order($0.id) > rank } ?? items.count
            items.insert(Self.item(variant), at: slot)
            // The slider compares exactly two, so a third capture returns to Auto.
            if layout == .slider { layout = .automatic }
        }
    }

    func previewKey(profile: ColorProfile) -> PreviewKey {
        PreviewKey(
            layout: layout,
            size: size,
            gap: gap,
            background: background,
            showsFooter: showsFooter,
            dividerPercent: dividerPercent,
            itemIDs: items.map(\.id),
            captions: items.flatMap { [$0.label, $0.detail] },
            profile: profile)
    }

    var isValid: Bool {
        (try? board()) != nil
    }

    /// Removing cannot drop below two and adding a variant leaves the slider, so a chosen
    /// slider stays valid.
    var availableLayouts: [ComparisonBoard.Layout] {
        ComparisonBoard.Layout.allCases.filter {
            $0 != .slider || $0.wipes(itemCount: items.count)
        }
    }

    func board() throws -> ComparisonBoard {
        try ComparisonBoard(
            items: items.map {
                ComparisonBoard.Item(
                    asset: $0.asset,
                    label: $0.label,
                    detail: $0.detail)
            },
            layout: layout,
            size: size,
            gap: gap,
            background: background,
            showsFooter: showsFooter,
            dividerPercent: dividerPercent)
    }

    /// The scale exports use. OG is an exact pixel contract, like the OpenGraph export preset.
    var resolvedExportScale: CGFloat {
        size == .openGraph ? CGFloat(ExportPreset.openGraph.scale) : exportScale
    }

    /// Available while a caption is being retyped and the board itself is not valid yet.
    var metrics: ComparisonBoardComposer.Metrics {
        ComparisonBoardComposer.metrics(
            itemCount: items.count,
            layout: layout,
            size: size,
            gap: gap,
            showsFooter: showsFooter)
    }

    var captionFrames: [Item.ID: CGRect] {
        let metrics = metrics
        return Dictionary(
            uniqueKeysWithValues: items.enumerated().map { index, item in
                (item.id, metrics.captionFrame(at: index))
            })
    }

    var wipe: ComparisonBoardComposer.Wipe? {
        metrics.wipe(
            captureSizes: items.map(\.asset.pixelSize),
            dividerPercent: dividerPercent)
    }

    func compose(
        scale: CGFloat, profile: ColorProfile, budget: RenderBudget = .export
    ) throws -> RenderedAsset {
        try ComparisonBoardComposer.compose(
            board(), scale: scale, profile: profile, budget: budget)
    }

    /// What the stage shows: the export's composition at 1×, under the interactive budget.
    func composePreview(profile: ColorProfile) throws -> RenderedAsset {
        try compose(scale: 1, profile: profile, budget: .preview)
    }

    func moveItem(id: Item.ID, offset: Int) {
        guard let source = items.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard items.indices.contains(destination) else { return }
        items.swapAt(source, destination)
    }

    func removeItem(id: Item.ID) {
        guard items.count > ComparisonBoard.itemCountRange.lowerBound else { return }
        if let item = items.first(where: { $0.id == id }),
            let index = variants.firstIndex(where: { $0.id == id })
        {
            variants[index].label = item.label
            variants[index].detail = item.detail
        }
        items.removeAll { $0.id == id }
    }

    private static func defaultLabel(index: Int, count: Int) -> String {
        if count == 2 {
            return index == 0 ? String(localized: "Before") : String(localized: "After")
        }
        return String(localized: "Capture \(index + 1)")
    }
}
