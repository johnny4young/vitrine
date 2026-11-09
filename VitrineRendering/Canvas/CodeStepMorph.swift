import CoreText
import SwiftUI
import VitrineDomain

/// A preview-only change from one code step to the next, laid out once. Exports never
/// carry one.
public struct CodeStepAnimation: Equatable {
    /// A token at its start and end cells (x is its measured advance, y the line).
    struct Glyph {
        let text: String
        let color: Color
        let from: CGPoint?
        let to: CGPoint?

        /// Leaving tokens are gone by halfway and entering ones start there.
        func state(at progress: Double) -> (cell: CGPoint, opacity: Double)? {
            switch (from, to) {
            case (let from?, let to?):
                let t = CGFloat(progress)
                return (
                    CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), 1
                )
            case (let from?, nil): return (from, max(0, 1 - progress * 2))
            case (nil, let to?): return (to, max(0, progress * 2 - 1))
            case (nil, nil): return nil
            }
        }
    }

    /// Resolves each source line once. A Character column is not a glyph advance: emoji,
    /// CJK and font fallbacks can occupy more than one monospaced cell.
    struct TokenLayout {
        let text: NSAttributedString
        let advance: CGFloat
        private let usesUniformASCIIGrid: Bool
        private var lines: [Int: (start: Int, line: CTLine)] = [:]

        init?(text: NSAttributedString, source: String, font: NSFont) {
            // HTML-backed themes can normalize newlines or Unicode. Source token offsets
            // must never index a different UTF-16 sequence, even canonically equal text.
            guard text.string.utf16.elementsEqual(source.utf16) else { return nil }
            self.text = text
            advance = CodeFont.advance(of: "0", in: font)
            usesUniformASCIIGrid =
                font.isFixedPitch
                && source.utf8.allSatisfy {
                    (0x20...0x7E).contains($0) || $0 == 0x0A || $0 == 0x0D
                }
        }

        mutating func cell(for token: CodeToken) -> CGPoint {
            // Keep the original constant-time grid for ordinary monospaced ASCII code.
            if usesUniformASCIIGrid { return CGPoint(x: token.column, y: token.line) }
            let layout: (start: Int, line: CTLine)
            if let cached = lines[token.line] {
                layout = cached
            } else {
                let range = (text.string as NSString).lineRange(
                    for: NSRange(location: token.utf16Offset, length: 0))
                layout = (
                    range.location,
                    CTLineCreateWithAttributedString(text.attributedSubstring(from: range))
                )
                lines[token.line] = layout
            }
            let offset = token.utf16Offset - layout.start
            let start = CTLineGetOffsetForStringIndex(layout.line, offset, nil)
            let end = CTLineGetOffsetForStringIndex(
                layout.line, offset + token.text.utf16.count, nil)
            return CGPoint(x: min(start, end) / advance, y: CGFloat(token.line))
        }
    }

    public static let duration = 0.6

    public let id: Int
    public let to: String
    let glyphs: [Glyph]

    /// `nil` when the change can't be drawn token by token: tabs, whose width the column
    /// grid can't place, steps past the diff's token limit, or highlighting that changes
    /// the source's UTF-16 sequence.
    public init?(
        id: Int, from: String, to: String, language: Language, theme: VitrineDomain.Theme,
        font: NSFont
    ) {
        guard !from.isEmpty, !to.isEmpty, !from.contains("\t"), !to.contains("\t"),
            let transition = CodeStepTransition.between(from, to)
        else { return nil }
        let highlighter = HighlightManager.shared
        let old = highlighter.attributedString(
            for: from, language: language, theme: theme, font: font)
        let new = highlighter.attributedString(
            for: to, language: language, theme: theme, font: font)
        let fallback = highlighter.gutterForegroundColor(for: theme)
        guard var oldLayout = TokenLayout(text: old, source: from, font: font),
            var newLayout = TokenLayout(text: new, source: to, font: font)
        else { return nil }
        func glyph(
            _ token: CodeToken, in text: NSAttributedString, from: CGPoint?, to: CGPoint?
        )
            -> Glyph
        {
            let color =
                token.utf16Offset < text.length
                ? text.attribute(.foregroundColor, at: token.utf16Offset, effectiveRange: nil)
                    as? NSColor : nil
            return Glyph(
                text: token.text, color: color.map { Color(nsColor: $0) } ?? fallback,
                from: from, to: to)
        }
        glyphs = transition.changes.map { change in
            switch change {
            case .moved(let from, let to):
                glyph(
                    to, in: new, from: oldLayout.cell(for: from), to: newLayout.cell(for: to))
            case .removed(let token):
                glyph(token, in: old, from: oldLayout.cell(for: token), to: nil)
            case .inserted(let token):
                glyph(token, in: new, from: nil, to: newLayout.cell(for: token))
            }
        }
        self.id = id
        self.to = to
    }

    /// By identity, so comparing canvases never walks the glyphs.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    /// One line's height as SwiftUI lays out the code text, so rows land where it puts them.
    static func lineHeight(of font: Font, in context: GraphicsContext) -> CGFloat {
        context.resolve(Text(verbatim: "0").font(font))
            .measure(in: CGSize(width: CGFloat.infinity, height: .infinity)).height
    }
}

/// Draws a step change over the new step's plain text, which sizes the card: shared tokens
/// glide, removed ones fade out and new ones fade in.
struct CodeStepMorphView: View {
    let animation: CodeStepAnimation
    let text: AttributedString
    let font: NSFont
    let lineSpacing: CGFloat

    @State private var progress = 0.0

    var body: some View {
        Text(text)
            .lineSpacing(lineSpacing)
            .hidden()
            .overlay(alignment: .topLeading) {
                CodeStepMorphGlyphs(
                    glyphs: animation.glyphs, font: Font(font),
                    advance: CodeFont.advance(of: "0", in: font), lineSpacing: lineSpacing,
                    progress: progress)
            }
            .accessibilityRepresentation { Text(verbatim: animation.to) }
            .onAppear {
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: CodeStepAnimation.duration))
                {
                    progress = 1
                }
            }
    }
}

struct CodeStepMorphGlyphs: View, Animatable {
    let glyphs: [CodeStepAnimation.Glyph]
    let font: Font
    let advance: CGFloat
    let lineSpacing: CGFloat
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            let pitch = CodeStepAnimation.lineHeight(of: font, in: context) + lineSpacing
            for glyph in glyphs {
                guard let state = glyph.state(at: progress), state.opacity > 0 else { continue }
                var layer = context
                layer.opacity = state.opacity
                layer.draw(
                    Text(verbatim: glyph.text).font(font).foregroundStyle(glyph.color),
                    at: CGPoint(x: state.cell.x * advance, y: state.cell.y * pitch),
                    anchor: .topLeading)
            }
        }
    }
}
