import CoreGraphics
import SwiftUI

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
    static let spacing: CGFloat = 28
    static let boardPadding: CGFloat = 48
    static let cornerRadius: CGFloat = 20

    enum CompositionError: Error, Equatable {
        case invalidScale
        case renderFailure(RenderBudgetError)
    }

    struct Metrics: Equatable {
        let columns: Int
        let rows: Int
        let pointSize: CGSize
    }

    static var cardHeight: CGFloat {
        cardPadding * 2 + imageAreaHeight + captionGap + captionHeight
    }

    static func metrics(for board: ComparisonBoard) -> Metrics {
        let columns = resolvedColumnCount(for: board)
        let rows = Int(ceil(Double(board.items.count) / Double(columns)))
        let width =
            boardPadding * 2 + cardWidth * CGFloat(columns)
            + spacing * CGFloat(max(columns - 1, 0))
        let height =
            boardPadding * 2 + cardHeight * CGFloat(rows)
            + spacing * CGFloat(max(rows - 1, 0))
        return Metrics(
            columns: columns, rows: rows, pointSize: CGSize(width: width, height: height))
    }

    /// Produces a board at 1×, 2×, or 3×. The images are already rendered inputs, so
    /// composition performs no source-file access and no network work.
    @MainActor
    static func compose(
        _ board: ComparisonBoard,
        scale: CGFloat = 2,
        profile: ColorProfile = .sRGB
    ) throws -> RenderedAsset {
        guard scale.isFinite, scale >= 1, scale <= 3 else {
            throw CompositionError.invalidScale
        }

        let metrics = metrics(for: board)
        let content = BoardView(board: board, columns: metrics.columns)
            .frame(width: metrics.pointSize.width, height: metrics.pointSize.height)
        do {
            let image = try ExportManager.renderCGImageChecked(
                content, proposedSize: metrics.pointSize, scale: scale,
                profile: profile, isOpaque: true)
            return RenderedAsset(cgImage: image, profile: profile)
        } catch let error {
            throw CompositionError.renderFailure(error)
        }
    }

    private static func resolvedColumnCount(for board: ComparisonBoard) -> Int {
        switch board.layout {
        case .automatic:
            board.items.count == 4 ? 2 : board.items.count
        case .horizontal:
            board.items.count
        case .vertical:
            1
        case .grid:
            2
        }
    }

    private struct BoardView: View {
        let board: ComparisonBoard
        let columns: Int

        private var rows: [[ComparisonBoard.Item]] {
            stride(from: 0, to: board.items.count, by: columns).map { start in
                Array(board.items[start..<min(start + columns, board.items.count)])
            }
        }

        var body: some View {
            VStack(spacing: ComparisonBoardComposer.spacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: ComparisonBoardComposer.spacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                            CardView(item: item)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(ComparisonBoardComposer.boardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.055, green: 0.047, blue: 0.11),
                        Color(red: 0.13, green: 0.08, blue: 0.24),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
        }
    }

    private struct CardView: View {
        let item: ComparisonBoard.Item

        var body: some View {
            VStack(spacing: ComparisonBoardComposer.captionGap) {
                Image(decorative: item.asset.cgImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: ComparisonBoardComposer.imageAreaHeight
                    )
                    .frame(height: ComparisonBoardComposer.imageAreaHeight)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: ComparisonBoardComposer.cornerRadius - 6,
                            style: .continuous))

                VStack(spacing: 4) {
                    Text(verbatim: item.label)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                    if let detail = item.detail {
                        Text(verbatim: detail)
                            .font(.system(size: 13, weight: .regular).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: ComparisonBoardComposer.captionHeight)
            }
            .padding(ComparisonBoardComposer.cardPadding)
            .frame(
                width: ComparisonBoardComposer.cardWidth,
                height: ComparisonBoardComposer.cardHeight
            )
            .background(.white.opacity(0.075))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: ComparisonBoardComposer.cornerRadius,
                    style: .continuous)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: ComparisonBoardComposer.cornerRadius,
                    style: .continuous
                )
                .strokeBorder(.white.opacity(0.11), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.34), radius: 20, y: 12)
        }
    }
}
