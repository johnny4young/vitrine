import Foundation

/// A validated, path-free description of a board made from two to four finished
/// captures.
///
/// Items carry only rendered pixels and user-visible captions. They do not retain the
/// source document, a file URL, a bookmark, or a reference into Recents. That keeps the
/// composition portable in memory and makes opening or exporting a board incapable of
/// causing an implicit file read.
nonisolated struct ComparisonBoard: Sendable {
    static let itemCountRange = 2...4
    static let maximumLabelLength = 48
    static let maximumDetailLength = 80

    enum Layout: String, CaseIterable, Sendable {
        /// Before/after stays side by side, three items form one row, and four items use
        /// a balanced two-by-two grid.
        case automatic
        case horizontal
        case vertical
        case grid
    }

    enum ValidationError: Error, Equatable, Sendable {
        case itemCount(Int)
        case emptyLabel(index: Int)
        case labelTooLong(index: Int)
        case detailTooLong(index: Int)
        case multilineCaption(index: Int)
    }

    struct Item: Sendable {
        let asset: RenderedAsset
        let label: String
        let detail: String?

        init(asset: RenderedAsset, label: String, detail: String? = nil) {
            self.asset = asset
            self.label = label
            self.detail = detail
        }
    }

    let items: [Item]
    let layout: Layout

    init(items: [Item], layout: Layout = .automatic) throws {
        guard Self.itemCountRange.contains(items.count) else {
            throw ValidationError.itemCount(items.count)
        }

        self.items = try items.enumerated().map { index, item in
            let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { throw ValidationError.emptyLabel(index: index) }
            guard !Self.containsLineBreak(label) else {
                throw ValidationError.multilineCaption(index: index)
            }
            guard label.count <= Self.maximumLabelLength else {
                throw ValidationError.labelTooLong(index: index)
            }

            let trimmedDetail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedDetail {
                guard !Self.containsLineBreak(trimmedDetail) else {
                    throw ValidationError.multilineCaption(index: index)
                }
                guard trimmedDetail.count <= Self.maximumDetailLength else {
                    throw ValidationError.detailTooLong(index: index)
                }
            }

            return Item(
                asset: item.asset,
                label: label,
                detail: trimmedDetail?.isEmpty == true ? nil : trimmedDetail)
        }
        self.layout = layout
    }

    private static func containsLineBreak(_ value: String) -> Bool {
        value.contains(where: { $0.isNewline })
    }
}
