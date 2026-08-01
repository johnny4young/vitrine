import CoreGraphics
import Foundation
import Observation

/// Session-only editing state for a comparison board.
///
/// A draft owns finished capture pixels and user-visible captions only. It is never
/// encoded into defaults or Recents, and closing its window releases the entire value.
@MainActor
@Observable
final class ComparisonBoardDraft {
    struct Item: Identifiable, Sendable {
        let id: UUID
        let asset: RenderedAsset
        var label: String
        var detail: String
    }

    enum CreationError: Error, Equatable {
        case invalidSelection(Int)
        case invalidRenderScale(CGFloat)
        case renderFailed(index: Int)
    }

    struct PreviewKey: Hashable {
        let layout: ComparisonBoard.Layout
        let itemIDs: [Item.ID]
        let captions: [String]
        let profile: ColorProfile
    }

    var items: [Item]
    var layout: ComparisonBoard.Layout = .automatic
    let exportScale: CGFloat

    init(
        captures: [Capture],
        baseConfig: SnapshotConfig,
        profile: ColorProfile,
        renderScale: CGFloat = 1,
        render: (SnapshotConfig, CGFloat, ColorProfile) -> CGImage? = { config, scale, profile in
            ExportManager.renderCGImage(config, scale: scale, profile: profile)
        }
    ) throws {
        guard ComparisonBoard.itemCountRange.contains(captures.count) else {
            throw CreationError.invalidSelection(captures.count)
        }
        guard renderScale.isFinite, (1...3).contains(renderScale) else {
            throw CreationError.invalidRenderScale(renderScale)
        }

        exportScale = renderScale
        items = try captures.enumerated().map { index, capture in
            let config = capture.applying(to: baseConfig)
            guard let image = render(config, renderScale, profile) else {
                throw CreationError.renderFailed(index: index)
            }
            return Item(
                id: UUID(),
                asset: RenderedAsset(cgImage: image, profile: profile),
                label: Self.defaultLabel(index: index, count: captures.count),
                detail: "\(capture.language.displayName) · \(capture.theme.displayName)")
        }
    }

    func previewKey(profile: ColorProfile) -> PreviewKey {
        PreviewKey(
            layout: layout,
            itemIDs: items.map(\.id),
            captions: items.flatMap { [$0.label, $0.detail] },
            profile: profile)
    }

    var isValid: Bool {
        (try? board()) != nil
    }

    func board() throws -> ComparisonBoard {
        try ComparisonBoard(
            items: items.map {
                ComparisonBoard.Item(
                    asset: $0.asset,
                    label: $0.label,
                    detail: $0.detail)
            },
            layout: layout)
    }

    func compose(scale: CGFloat, profile: ColorProfile) throws -> RenderedAsset {
        try ComparisonBoardComposer.compose(board(), scale: scale, profile: profile)
    }

    func moveItem(id: Item.ID, offset: Int) {
        guard let source = items.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard items.indices.contains(destination) else { return }
        items.swapAt(source, destination)
    }

    func removeItem(id: Item.ID) {
        guard items.count > ComparisonBoard.itemCountRange.lowerBound else { return }
        items.removeAll { $0.id == id }
    }

    private static func defaultLabel(index: Int, count: Int) -> String {
        if count == 2 {
            return index == 0 ? String(localized: "Before") : String(localized: "After")
        }
        return String(localized: "Capture \(index + 1)")
    }
}
