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
    /// Keeps labels at 12.6 pt and details at 9.1 pt at 1×; a tight cell shrinks the image instead.
    static let minimumUnit: CGFloat = 0.7
    /// A fixed-size column whose images would be smaller than this draws as a grid.
    static let minimumImageHeight: CGFloat = 100

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

        var imageHeight: CGFloat {
            max(cardFrames[0].height - chromeHeight(unit: unit), 1)
        }

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

    static func chromeHeight(unit: CGFloat) -> CGFloat {
        (cardPadding * 2 + captionGap + captionHeight) * unit
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
        var columns = resolvedColumnCount(itemCount: itemCount, layout: layout)
        let footer = showsFooter ? footerHeight : 0

        let canvas: CGSize
        let card: CGSize
        let unit: CGFloat
        if let fixed = size.fixedPointSize {
            var fitted = fittedCard(
                itemCount: itemCount, columns: columns, canvas: fixed, gap: gap, footer: footer)
            if columns == 1, itemCount > 2,
                fitted.card.height - chromeHeight(unit: fitted.unit) < minimumImageHeight
            {
                columns = 2
                fitted = fittedCard(
                    itemCount: itemCount, columns: columns, canvas: fixed, gap: gap, footer: footer)
            }
            canvas = fixed
            unit = fitted.unit
            card = fitted.card
        } else {
            let rows = rowCount(itemCount: itemCount, columns: columns)
            canvas = CGSize(
                width: boardPadding * 2 + cardWidth * CGFloat(columns)
                    + gap * CGFloat(columns - 1),
                height: boardPadding * 2 + footer + cardHeight * CGFloat(rows)
                    + gap * CGFloat(rows - 1))
            unit = 1
            card = CGSize(width: cardWidth, height: cardHeight)
        }

        let rows = rowCount(itemCount: itemCount, columns: columns)
        let rowGaps = gap * CGFloat(rows - 1)
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

    private static func rowCount(itemCount: Int, columns: Int) -> Int {
        Int(ceil(Double(itemCount) / Double(columns)))
    }

    private static func fittedCard(
        itemCount: Int, columns: Int, canvas: CGSize, gap: CGFloat, footer: CGFloat
    ) -> (card: CGSize, unit: CGFloat) {
        let rows = rowCount(itemCount: itemCount, columns: columns)
        let cell = CGSize(
            width: (canvas.width - boardPadding * 2 - gap * CGFloat(columns - 1))
                / CGFloat(columns),
            height: (canvas.height - boardPadding * 2 - footer - gap * CGFloat(rows - 1))
                / CGFloat(rows))
        let fit = min(cell.width / cardWidth, cell.height / cardHeight)
        guard fit < minimumUnit else {
            return (CGSize(width: cardWidth * fit, height: cardHeight * fit), fit)
        }
        // Captions hold their size, so the card takes the cell's width and the image gives way.
        let imageWidth = cell.width - cardPadding * 2 * minimumUnit
        let imageHeight = imageWidth * imageAreaHeight / (cardWidth - cardPadding * 2)
        let height = min(cell.height, imageHeight + chromeHeight(unit: minimumUnit))
        return (CGSize(width: cell.width, height: height), minimumUnit)
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
                GradientPreset.aurora.gradient
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
                        imageHeight: metrics.imageHeight,
                        unit: metrics.unit,
                        fill: board.background.cardFill
                    )
                    .position(x: frame.midX, y: frame.midY)
                    .mask { outsideOtherCards(than: index) }
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

        /// A card's shadow stays on the backdrop: on a neighbour it would darken one side only.
        private func outsideOtherCards(than index: Int) -> some View {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: metrics.pointSize))
                for (other, frame) in metrics.cardFrames.enumerated() where other != index {
                    let radius = ComparisonBoardComposer.cornerRadius * metrics.unit
                    path.addRoundedRect(
                        in: frame, cornerSize: CGSize(width: radius, height: radius),
                        style: .continuous)
                }
            }
            .fill(style: FillStyle(eoFill: true))
        }
    }

    private struct CardView: View {
        let item: ComparisonBoard.Item
        let size: CGSize
        let imageHeight: CGFloat
        let unit: CGFloat
        let fill: Color

        private var cardShape: RoundedRectangle {
            RoundedRectangle(
                cornerRadius: ComparisonBoardComposer.cornerRadius * unit, style: .continuous)
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
