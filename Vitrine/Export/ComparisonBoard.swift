import CoreGraphics
import Foundation
import VitrineDomain
import VitrineRendering

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
    static let gapRange: ClosedRange<CGFloat> = 0...40
    static let defaultGap: CGFloat = 28
    /// A share of the width both captures have, so each always shows some of itself.
    static let dividerRange = 10...90
    static let defaultDividerPercent = 50

    enum Layout: String, CaseIterable, Sendable {
        /// Before/after stays side by side, three items form one row, and four items use
        /// a balanced two-by-two grid.
        case automatic
        case horizontal
        case vertical
        case grid
        /// Two captures in one frame, split at a divider. A still image cannot be dragged, so
        /// its result is the position chosen in the editor.
        case slider

        /// A wipe compares exactly two captures; any other count draws as `automatic`.
        func wipes(itemCount: Int) -> Bool {
            self == .slider && itemCount == 2
        }
    }

    enum Size: String, CaseIterable, Sendable {
        /// Hugs the cards, so the board grows with its layout.
        case automatic
        case widescreen
        case openGraph
        case square

        var fixedPointSize: CGSize? {
            switch self {
            case .automatic: nil
            case .widescreen: CGSize(width: 1600, height: 1000)
            case .openGraph: ExportPreset.openGraph.sizing.fixedSize
            case .square: CGSize(width: 1080, height: 1080)
            }
        }
    }

    enum Background: String, CaseIterable, Sendable {
        case vitrine
        case card
        case aurora
        case transparent
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
    let size: Size
    let gap: CGFloat
    let background: Background
    let showsFooter: Bool
    let dividerPercent: Int

    init(
        items: [Item],
        layout: Layout = .automatic,
        size: Size = .automatic,
        gap: CGFloat = defaultGap,
        background: Background = .vitrine,
        showsFooter: Bool = false,
        dividerPercent: Int = defaultDividerPercent
    ) throws {
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
        self.size = size
        self.gap = Self.clampedGap(gap)
        self.background = background
        self.showsFooter = showsFooter
        self.dividerPercent = Self.clampedDivider(dividerPercent)
    }

    /// The footer is generated from the count alone: a board keeps no file name or source
    /// text, so nothing hidden in a capture can come back through this line.
    var footerText: String? {
        showsFooter ? Self.footerText(captureCount: items.count) : nil
    }

    static func footerText(captureCount: Int) -> String {
        String(localized: "\(captureCount) captures · made with Vitrine")
    }

    static func clampedGap(_ gap: CGFloat) -> CGFloat {
        guard gap.isFinite else { return defaultGap }
        return min(max(gap, gapRange.lowerBound), gapRange.upperBound)
    }

    static func clampedDivider(_ percent: Int) -> Int {
        min(max(percent, dividerRange.lowerBound), dividerRange.upperBound)
    }

    private static func containsLineBreak(_ value: String) -> Bool {
        value.contains(where: { $0.isNewline })
    }
}
