import CoreText
import SwiftUI
import VitrineDomain

/// Where a rendered `SnapshotCanvas` placed its card and code, in the canvas's own
/// points, so the editor can snap marks to the layout it already drew.
public struct CanvasSnapLayout: Equatable {
    public var card: CGRect
    public var code: CGRect?
    /// What the code frame holds; turned into rows and columns only when a drag needs them.
    public var text: CodeText?

    public init(card: CGRect, code: CGRect?, text: CodeText?) {
        self.card = card
        self.code = code
        self.text = text
    }

    /// The inputs the code body was laid out from. Copying them costs a keystroke nothing.
    public struct CodeText: Equatable {
        var code: String
        var fontName: String
        var fontSize: Double
        var ligatures: Bool
        var lineSpacing: CGFloat
        var wrapColumns: Int?
        var isTerminal: Bool
        var usesLineRows: Bool
        var showLineNumbers: Bool
        var firstLineNumber: Int

        init(config: SnapshotConfig, lineSpacing: CGFloat) {
            code = config.code
            fontName = config.fontName
            fontSize = config.fontSize
            ligatures = config.fontLigatures
            self.lineSpacing = lineSpacing
            wrapColumns = config.wrapColumns
            isTerminal = config.language == .terminal
            usesLineRows = config.usesLineRows
            showLineNumbers = config.showLineNumbers
            firstLineNumber = config.firstLineNumber
        }

        /// The row and column metrics, measured from the font the canvas draws with.
        public func metrics() -> CodeMetrics {
            let font = CodeFont.resolved(family: fontName, size: fontSize, ligatures: ligatures)
            var columnInset: CGFloat = 0
            if usesLineRows && showLineNumbers {
                let rows = LineSplitter.lineCount(of: code) + firstLineNumber - 1
                columnInset =
                    GutterMetrics(font: font, lineCount: rows).numberWidth
                    + GutterMetrics.trailingGap
            }
            return CodeMetrics(
                source: mapsRows(in: font) ? code : nil, lineSpacing: lineSpacing,
                rowInset: usesLineRows ? lineSpacing / 2 : 0, columnInset: columnInset,
                advance: font.isFixedPitch ? CodeFont.advance(of: "0", in: font) : nil)
        }

        /// Rows share one pitch only when nothing wraps and no glyph falls back to a taller
        /// font, so wrapped, terminal, non-ASCII and uncovered text reports no rows.
        private func mapsRows(in font: NSFont) -> Bool {
            guard wrapColumns == nil, !isTerminal, !code.isEmpty,
                code.unicodeScalars.allSatisfy(\.isASCII)
            else { return false }
            var characters = Array(Set(code.utf16)).filter { $0 >= 0x20 && $0 != 0x7F }
            guard !characters.isEmpty else { return true }
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            return CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        }
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
            source: String?, lineSpacing: CGFloat, rowInset: CGFloat, columnInset: CGFloat,
            advance: CGFloat?
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
    var text: CanvasSnapLayout.CodeText?

    /// The layout in `proxy`'s coordinate space, once the card has reported.
    public func resolved(in proxy: GeometryProxy) -> CanvasSnapLayout? {
        guard let card else { return nil }
        return CanvasSnapLayout(card: proxy[card], code: code.map { proxy[$0] }, text: text)
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
            value.text = next.text
        }
    }
}

extension View {
    func reportsSnapCard() -> some View {
        transformAnchorPreference(key: CanvasSnapAnchorsKey.self, value: .bounds) { value, anchor in
            value.card = anchor
        }
    }

    func reportsSnapCode(_ config: SnapshotConfig, lineSpacing: CGFloat) -> some View {
        anchorPreference(key: CanvasSnapAnchorsKey.self, value: .bounds) { anchor in
            CanvasSnapAnchors(
                code: anchor,
                text: CanvasSnapLayout.CodeText(config: config, lineSpacing: lineSpacing))
        }
    }
}
