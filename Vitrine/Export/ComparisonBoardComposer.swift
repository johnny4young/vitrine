import CoreGraphics
import SwiftUI
import VitrineDomain
import VitrineRendering

/// Deterministically arranges a validated comparison board into one color-managed
/// rendered asset.
///
/// Every item receives the same card bounds and aspect-fit image area, so captures with
/// different dimensions remain comparable without cropping. Layout metrics are resolved
/// before SwiftUI renders, which keeps output dimensions stable and directly testable.
enum ComparisonBoardComposer {
    static let cardWidth: CGFloat = 520
    static let imageAreaHeight: CGFloat = 360
    static let captionHeight: CGFloat = 64
    static let cardPadding: CGFloat = 18
    static let captionGap: CGFloat = 12
    static let boardPadding: CGFloat = 48
    static let cornerRadius: CGFloat = 20
    static let footerHeight: CGFloat = 40
    /// Below this the captions stop being legible, so a tight cell shrinks the image instead.
    static let minimumUnit: CGFloat = 0.4

    enum CompositionError: Error, Equatable {
        case invalidScale
        case renderFailure(RenderBudgetError)
    }

    struct Metrics: Equatable {
        let columns: Int
        let rows: Int
        let pointSize: CGSize
        /// Scales the card's inner measurements and type against the 1× card.
        let unit: CGFloat
        let cardFrames: [CGRect]
        let footerFrame: CGRect?

        /// Rendering and the inline caption editor share this rectangle, so a caption
        /// stays under the pointer whatever the board size, gap, or layout.
        func captionFrame(at index: Int) -> CGRect {
            let card = cardFrames[index]
            let inset = cardPadding * unit
            let height = captionHeight * unit
            return CGRect(
                x: card.minX + inset,
                y: card.maxY - inset - height,
                width: card.width - inset * 2,
                height: height)
        }
    }

    static var cardHeight: CGFloat {
        cardPadding * 2 + imageAreaHeight + captionGap + captionHeight
    }

    static func metrics(for board: ComparisonBoard) -> Metrics {
        metrics(
            itemCount: board.items.count,
            layout: board.layout,
            size: board.size,
            gap: board.gap,
            showsFooter: board.showsFooter)
    }

    static func metrics(
        itemCount: Int,
        layout: ComparisonBoard.Layout,
        size: ComparisonBoard.Size,
        gap: CGFloat,
        showsFooter: Bool
    ) -> Metrics {
        let gap = ComparisonBoard.clampedGap(gap)
        let columns = resolvedColumnCount(itemCount: itemCount, layout: layout)
        let rows = Int(ceil(Double(itemCount) / Double(columns)))
        let footer = showsFooter ? footerHeight : 0
        let columnGaps = gap * CGFloat(max(columns - 1, 0))
        let rowGaps = gap * CGFloat(max(rows - 1, 0))

        let canvas: CGSize
        let card: CGSize
        let unit: CGFloat
        if let fixed = size.fixedPointSize {
            let cell = CGSize(
                width: (fixed.width - boardPadding * 2 - columnGaps) / CGFloat(columns),
                height: (fixed.height - boardPadding * 2 - footer - rowGaps) / CGFloat(rows))
            let fit = min(cell.width / cardWidth, cell.height / cardHeight)
            canvas = fixed
            unit = max(fit, minimumUnit)
            card =
                fit >= minimumUnit
                ? CGSize(width: cardWidth * fit, height: cardHeight * fit) : cell
        } else {
            canvas = CGSize(
                width: boardPadding * 2 + cardWidth * CGFloat(columns) + columnGaps,
                height: boardPadding * 2 + footer + cardHeight * CGFloat(rows) + rowGaps)
            unit = 1
            card = CGSize(width: cardWidth, height: cardHeight)
        }

        let blockHeight = card.height * CGFloat(rows) + rowGaps
        let top = boardPadding + (canvas.height - boardPadding * 2 - footer - blockHeight) / 2
        let frames = (0..<itemCount).map { index in
            let row = index / columns
            let inRow = min(columns, itemCount - row * columns)
            let rowWidth = card.width * CGFloat(inRow) + gap * CGFloat(inRow - 1)
            return CGRect(
                x: (canvas.width - rowWidth) / 2
                    + CGFloat(index % columns) * (card.width + gap),
                y: top + CGFloat(row) * (card.height + gap),
                width: card.width,
                height: card.height)
        }
        let footerFrame =
            showsFooter
            ? CGRect(
                x: boardPadding,
                y: canvas.height - boardPadding - footerHeight,
                width: canvas.width - boardPadding * 2,
                height: footerHeight)
            : nil
        return Metrics(
            columns: columns, rows: rows, pointSize: canvas, unit: unit,
            cardFrames: frames, footerFrame: footerFrame)
    }

    /// Produces a board at 1×, 2×, or 3×. The images are already rendered inputs, so
    /// composition performs no source-file access and no network work.
    static func compose(
        _ board: ComparisonBoard,
        scale: CGFloat = 2,
        profile: ColorProfile = .sRGB,
        budget: RenderBudget = .export
    ) throws -> RenderedAsset {
        guard scale.isFinite, scale >= 1, scale <= 3 else {
            throw CompositionError.invalidScale
        }

        let metrics = metrics(for: board)
        let content = BoardView(board: board, metrics: metrics)
            .frame(width: metrics.pointSize.width, height: metrics.pointSize.height)
        do {
            let image = try ExportManager.renderCGImageChecked(
                content, proposedSize: metrics.pointSize, scale: scale,
                profile: profile, budget: budget,
                isOpaque: board.background != .transparent)
            return RenderedAsset(cgImage: image, profile: profile)
        } catch let error {
            throw CompositionError.renderFailure(error)
        }
    }

    private static func resolvedColumnCount(
        itemCount: Int, layout: ComparisonBoard.Layout
    ) -> Int {
        switch layout {
        case .automatic:
            itemCount == 4 ? 2 : itemCount
        case .horizontal:
            itemCount
        case .vertical:
            1
        case .grid:
            2
        }
    }

    /// The board's backdrop, shared with the inspector swatches so they cannot drift.
    struct BackgroundFill: View {
        let background: ComparisonBoard.Background

        var body: some View {
            switch background {
            case .vitrine:
                LinearGradient(
                    colors: [
                        Color(red: 0.055, green: 0.047, blue: 0.11),
                        Color(red: 0.13, green: 0.08, blue: 0.24),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            case .card:
                Color(red: 0.133, green: 0.137, blue: 0.169)
            case .aurora:
                LinearGradient(
                    colors: [
                        Color(red: 0.31, green: 0.275, blue: 0.898),
                        Color(red: 0.024, green: 0.714, blue: 0.831),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            case .transparent:
                Color.clear
            }
        }
    }

    private struct BoardView: View {
        let board: ComparisonBoard
        let metrics: Metrics

        var body: some View {
            ZStack(alignment: .topLeading) {
                BackgroundFill(background: board.background)
                ForEach(Array(board.items.enumerated()), id: \.offset) { index, item in
                    let frame = metrics.cardFrames[index]
                    CardView(
                        item: item,
                        size: frame.size,
                        unit: metrics.unit,
                        fill: board.background.cardFill
                    )
                    .position(x: frame.midX, y: frame.midY)
                }
                if let footer = board.footerText, let frame = metrics.footerFrame {
                    Text(verbatim: footer)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        // Mid gray stays legible on whatever a transparent board lands on.
                        .foregroundStyle(
                            board.background == .transparent
                                ? Color(white: 0.5) : Color.white.opacity(0.7)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: frame.width, height: frame.height, alignment: .bottom)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
    }

    private struct CardView: View {
        let item: ComparisonBoard.Item
        let size: CGSize
        let unit: CGFloat
        let fill: Color

        private var cardShape: RoundedRectangle {
            RoundedRectangle(
                cornerRadius: ComparisonBoardComposer.cornerRadius * unit, style: .continuous)
        }

        private var imageHeight: CGFloat {
            let chrome =
                (ComparisonBoardComposer.cardPadding * 2 + ComparisonBoardComposer.captionGap
                    + ComparisonBoardComposer.captionHeight) * unit
            return max(size.height - chrome, 1)
        }

        var body: some View {
            VStack(spacing: ComparisonBoardComposer.captionGap * unit) {
                Image(decorative: item.asset.cgImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: imageHeight)
                    .frame(height: imageHeight)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: (ComparisonBoardComposer.cornerRadius - 6) * unit,
                            style: .continuous))

                VStack(spacing: 4 * unit) {
                    Text(verbatim: item.label)
                        .font(.system(size: 18 * unit, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                    if let detail = item.detail {
                        Text(verbatim: detail)
                            .font(.system(size: 13 * unit, weight: .regular).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ComparisonBoardComposer.captionHeight * unit)
            }
            .padding(ComparisonBoardComposer.cardPadding * unit)
            .frame(width: size.width, height: size.height)
            .background(fill)
            .clipShape(cardShape)
            .overlay(cardShape.strokeBorder(.white.opacity(0.11), lineWidth: 1))
            .shadow(color: .black.opacity(0.34), radius: 20 * unit, y: 12 * unit)
        }
    }
}

extension ComparisonBoard.Background {
    /// Captions are white, so a bright or absent backdrop needs a darker card behind them.
    fileprivate var cardFill: Color {
        switch self {
        case .vitrine, .card: .white.opacity(0.075)
        case .aurora: .black.opacity(0.32)
        case .transparent: Color(red: 0.133, green: 0.137, blue: 0.169)
        }
    }
}
