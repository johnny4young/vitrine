import SwiftUI
import VitrineDomain

/// A diff with the old file on the left and the new one on the right. Each cell is a
/// `CodeLinesView` row, so bands, highlights, focus and redaction match the unified layout,
/// and a context row redacted once is masked on both sides.
struct SplitDiffLinesView: View {
    let lines: CodeLinesView
    let rows: [DiffSplitRow]

    var body: some View {
        let metrics = GutterMetrics(font: lines.font, lineCount: highestNumber)
        SplitColumnsLayout(columnSpacing: Brand.Spacing.lg, rowSpacing: lines.lineSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .spanning(.line(let number)) where lines.rows.indices.contains(number - 1):
                    lines.row(
                        lines.rows[number - 1], lineNumber: number, metrics: metrics,
                        gutterLabel: ""
                    )
                    .layoutValue(key: SplitColumnsLayout.Spans.self, value: true)
                case .spanning(.line):
                    EmptyView()
                case .spanning(.fold):
                    lines.foldMarker(metrics: metrics)
                        .layoutValue(key: SplitColumnsLayout.Spans.self, value: true)
                case .pair(let old, let new):
                    cell(old, metrics: metrics)
                    cell(new, metrics: metrics)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ cell: DiffSplitCell?, metrics: GutterMetrics) -> some View {
        if let cell, lines.rows.indices.contains(cell.row - 1) {
            lines.wrappingEachSide.row(
                lines.rows[cell.row - 1], lineNumber: cell.row, metrics: metrics,
                gutterLabel: cell.number.map { "\($0)" } ?? "", fillsHeight: true)
        } else {
            // The side a change does not reach, shaded so the pair still reads as one row.
            Rectangle()
                .fill(lines.textColor.opacity(0.06))
                .padding(.horizontal, -Brand.Spacing.xs)
                .layoutValue(key: SplitColumnsLayout.Filler.self, value: true)
                .accessibilityHidden(true)
        }
    }

    private var highestNumber: Int {
        rows.reduce(1) { highest, row in
            guard case .pair(let old, let new) = row else { return highest }
            return max(highest, old?.number ?? 0, new?.number ?? 0)
        }
    }
}

extension CodeLinesView {
    /// The same rows wrapped at half the width, so a wrapped split card stays as wide as the
    /// unified one.
    fileprivate var wrappingEachSide: CodeLinesView {
        var copy = self
        copy.codeColumnWidth = codeColumnWidth.map { $0 / 2 }
        return copy
    }
}

/// Two equal columns, each as wide as the widest cell on either side, so the halves line up
/// like a side-by-side diff. Spanning rows take the full width. Subviews arrive in reading
/// order: one per spanning row, two per pair.
struct SplitColumnsLayout: Layout {
    struct Spans: LayoutValueKey { static let defaultValue = false }
    struct Filler: LayoutValueKey { static let defaultValue = false }

    struct Measurement {
        var column: CGFloat = 0
        var width: CGFloat = 0
        /// Each row's subview indices and height.
        var rows: [(indices: [Int], height: CGFloat)] = []
        var height: CGFloat = 0
    }

    var columnSpacing: CGFloat
    var rowSpacing: CGFloat

    func makeCache(subviews: Subviews) -> Measurement {
        var rows: [[Int]] = []
        var index = 0
        while index < subviews.count {
            let count = subviews[index][Spans.self] ? 1 : min(2, subviews.count - index)
            rows.append(Array(index..<(index + count)))
            index += count
        }
        func idealWidth(_ index: Int) -> CGFloat {
            subviews[index][Filler.self] ? 0 : subviews[index].sizeThatFits(.unspecified).width
        }
        var measurement = Measurement()
        var span: CGFloat = 0
        for row in rows {
            if row.count == 1, subviews[row[0]][Spans.self] {
                span = max(span, idealWidth(row[0]))
            } else {
                measurement.column = max(measurement.column, row.map(idealWidth).max() ?? 0)
            }
        }
        measurement.width = max(measurement.column * 2 + columnSpacing, span)
        measurement.column = (measurement.width - columnSpacing) / 2
        measurement.rows = rows.map { row in
            let spans = row.count == 1 && subviews[row[0]][Spans.self]
            let proposal = ProposedViewSize(
                width: spans ? measurement.width : measurement.column, height: nil)
            let height =
                row.filter { !subviews[$0][Filler.self] }
                .map { subviews[$0].sizeThatFits(proposal).height }.max() ?? 0
            return (row, height)
        }
        measurement.height =
            measurement.rows.reduce(0) { $0 + $1.height }
            + rowSpacing * CGFloat(max(measurement.rows.count - 1, 0))
        return measurement
    }

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Measurement
    ) -> CGSize {
        CGSize(width: cache.width, height: cache.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
        cache: inout Measurement
    ) {
        var y = bounds.minY
        for row in cache.rows {
            let spans = row.indices.count == 1 && subviews[row.indices[0]][Spans.self]
            let width = spans ? cache.width : cache.column
            for (offset, index) in row.indices.enumerated() {
                subviews[index].place(
                    at: CGPoint(
                        x: bounds.minX + CGFloat(offset) * (cache.column + columnSpacing), y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: row.height))
            }
            y += row.height + rowSpacing
        }
    }
}
