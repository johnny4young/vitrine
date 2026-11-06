import SwiftUI
import VitrineDomain

/// Where a rendered `SnapshotCanvas` placed its card and code, in the canvas's own
/// points, so the editor can snap marks to the layout it already drew.
public struct CanvasSnapLayout: Equatable, Sendable {
    public var card: CGRect
    public var code: CGRect?
    public var metrics: CodeMetrics?

    public init(card: CGRect, code: CGRect? = nil, metrics: CodeMetrics? = nil) {
        self.card = card
        self.code = code
        self.metrics = metrics
    }

    /// How the code frame divides into rows and columns.
    public struct CodeMetrics: Equatable, Sendable {
        /// The source, one line per laid-out row; `nil` when rows do not map to lines.
        public var source: String?
        /// The gap between rows, which the last row does not have.
        public var lineSpacing: CGFloat
        /// The text's offset inside its row band (row layouts pad each row).
        public var rowInset: CGFloat
        /// The gutter width ahead of the first code column.
        public var columnInset: CGFloat
        /// One column's width; `nil` for a proportional font.
        public var advance: CGFloat?

        public init(
            source: String?, lineSpacing: CGFloat, rowInset: CGFloat = 0,
            columnInset: CGFloat = 0, advance: CGFloat?
        ) {
            self.source = source
            self.lineSpacing = lineSpacing
            self.rowInset = rowInset
            self.columnInset = columnInset
            self.advance = advance
        }
    }
}

/// The anchors behind a `CanvasSnapLayout`. A preference only: emitting it draws nothing.
public struct CanvasSnapAnchors {
    var card: Anchor<CGRect>?
    var code: Anchor<CGRect>?
    var metrics: CanvasSnapLayout.CodeMetrics?

    /// The layout in `proxy`'s coordinate space, once the card has reported.
    public func resolved(in proxy: GeometryProxy) -> CanvasSnapLayout? {
        guard let card else { return nil }
        return CanvasSnapLayout(card: proxy[card], code: code.map { proxy[$0] }, metrics: metrics)
    }
}

public struct CanvasSnapAnchorsKey: PreferenceKey {
    public static let defaultValue = CanvasSnapAnchors()

    // A blurred copy of the canvas reports the same layout again; the first one wins.
    public static func reduce(value: inout CanvasSnapAnchors, nextValue: () -> CanvasSnapAnchors) {
        let next = nextValue()
        if value.card == nil { value.card = next.card }
        if value.code == nil {
            value.code = next.code
            value.metrics = next.metrics
        }
    }
}

extension View {
    func reportsSnapCard() -> some View {
        transformAnchorPreference(key: CanvasSnapAnchorsKey.self, value: .bounds) { value, anchor in
            value.card = anchor
        }
    }

    func reportsSnapCode(_ metrics: @escaping () -> CanvasSnapLayout.CodeMetrics) -> some View {
        anchorPreference(key: CanvasSnapAnchorsKey.self, value: .bounds) { anchor in
            CanvasSnapAnchors(code: anchor, metrics: metrics())
        }
    }
}

extension SnapshotConfig {
    /// The row and column metrics for `font`. Soft-wrapped and terminal rows do not map
    /// one-to-one to source lines, so they report no source.
    func snapCodeMetrics(font: NSFont, lineSpacing: CGFloat) -> CanvasSnapLayout.CodeMetrics {
        let mapsLines = wrapColumns == nil && language != .terminal && !code.isEmpty
        var columnInset: CGFloat = 0
        if usesLineRows && showLineNumbers {
            let rows = LineSplitter.lineCount(of: code) + firstLineNumber - 1
            columnInset =
                GutterMetrics(font: font, lineCount: rows).numberWidth + GutterMetrics.trailingGap
        }
        return CanvasSnapLayout.CodeMetrics(
            source: mapsLines ? code : nil, lineSpacing: lineSpacing,
            rowInset: usesLineRows ? lineSpacing / 2 : 0, columnInset: columnInset,
            advance: font.isFixedPitch ? CodeFont.advance(of: "0", in: font) : nil)
    }
}
