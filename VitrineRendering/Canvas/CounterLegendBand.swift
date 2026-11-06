import SwiftUI
import VitrineDomain

/// The strip listing each labeled counter, drawn beneath the capture.
struct CounterLegendBand: View {
    let entries: [CounterLegend.Entry]
    let font: NSFont
    let textColor: Color
    let background: Color
    /// Whether to fill the height offered, past the height of its own text.
    var fillsHeight = false

    var body: some View {
        CounterLegendRows {
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                HStack(alignment: .top, spacing: CounterLegendMetrics.badgeGap) {
                    Text(verbatim: "\(entry.number)")
                        .font(.system(size: font.pointSize * 0.8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(
                            minWidth: CounterLegendMetrics.badgeSide(font),
                            minHeight: CounterLegendMetrics.badgeSide(font)
                        )
                        .background(Capsule().fill(entry.color.color))
                    Text(verbatim: entry.label)
                        .font(Font(font))
                        .foregroundStyle(textColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, CounterLegendMetrics.horizontalInset)
        .padding(.vertical, CounterLegendMetrics.verticalInset)
        .frame(
            maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading
        )
        .background(background)
    }
}

/// What the band reports out of the canvas: its height, so the editor can keep handles on
/// the capture above it, and how many entries a fixed frame left out.
public struct CounterLegendReport: Equatable {
    public var height: CGFloat = 0
    public var dropped = 0
}

public struct CounterLegendReportKey: PreferenceKey {
    public static let defaultValue = CounterLegendReport()
    public static func reduce(
        value: inout CounterLegendReport, nextValue: () -> CounterLegendReport
    ) {
        let next = nextValue()
        value.height = max(value.height, next.height)
        value.dropped = max(value.dropped, next.dropped)
    }
}

/// Stacks the capture and its band. The capture alone decides the width and is measured
/// as if the band weren't there, so a long label can't resize the coordinate space that
/// normalized annotations are placed in.
struct CounterLegendStack: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (capture, band) = sizes(subviews)
        return CGSize(width: capture.width, height: capture.height + band.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let (capture, band) = sizes(subviews)
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(capture))
        subviews.last?.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + capture.height),
            proposal: ProposedViewSize(band))
    }

    private func sizes(_ subviews: Subviews) -> (capture: CGSize, band: CGSize) {
        guard let first = subviews.first, let last = subviews.last else { return (.zero, .zero) }
        let capture = first.sizeThatFits(.unspecified)
        let band = last.sizeThatFits(ProposedViewSize(width: capture.width, height: nil))
        // Whole points, so the capture lands on the same pixels as it does with no band.
        return (capture, CGSize(width: capture.width, height: band.height.rounded(.up)))
    }
}

/// Wraps legend entries, offering each the full row so one long label wraps within the
/// band instead of running past the canvas.
private struct CounterLegendRows: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: subviews, width: proposal.width ?? .infinity)
        return CGSize(
            width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let frames = frames(for: subviews, width: bounds.width)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        CounterLegendMetrics.flow(
            subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) },
            width: width)
    }
}

/// The band's geometry, shared by its layout and the cap a fixed frame applies, which has
/// to be known outside a layout pass to tell the user what was left out.
nonisolated enum CounterLegendMetrics {
    static let horizontalInset: CGFloat = 26
    static let verticalInset: CGFloat = 12
    static let badgeGap: CGFloat = 5
    private static let entrySpacing: CGFloat = 14
    private static let lineSpacing: CGFloat = 6

    static func badgeSide(_ font: NSFont) -> CGFloat { font.pointSize * 1.3 }

    static func flow(_ sizes: [CGSize], width: CGFloat) -> [CGRect] {
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        return sizes.map { size in
            if origin.x > 0, origin.x + size.width > width {
                origin = CGPoint(x: 0, y: origin.y + lineHeight + lineSpacing)
                lineHeight = 0
            }
            defer {
                origin.x += size.width + entrySpacing
                lineHeight = max(lineHeight, size.height)
            }
            return CGRect(origin: origin, size: size)
        }
    }

    /// How many entries, from the top, fit in a third of `frame`'s height.
    static func entriesFitting(
        _ entries: [CounterLegend.Entry], font: NSFont, frame: CGSize
    ) -> Int {
        let width = frame.width - horizontalInset * 2
        let badge = badgeSide(font)
        let labelWidth = max(width - badge - badgeGap, 1)
        let sizes = entries.map { entry in
            let label = NSAttributedString(string: entry.label, attributes: [.font: font])
                .boundingRect(
                    with: CGSize(width: labelWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                ).size
            return CGSize(
                width: label.width.rounded(.up) + badge + badgeGap,
                height: max(label.height.rounded(.up), badge))
        }
        let limit = frame.height / 3 - verticalInset * 2
        return flow(sizes, width: width).prefix { $0.maxY <= limit }.count
    }
}
