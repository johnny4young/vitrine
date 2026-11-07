import SwiftUI
import VitrineDomain

/// A preview-only change from one code step to the next, laid out once. Exports never
/// carry one.
public struct CodeStepAnimation: Equatable {
    /// A token at its start and end grid cells (x is the column, y the line).
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

    public static let duration = 0.6

    public let id: Int
    public let to: String
    let glyphs: [Glyph]

    /// `nil` when the change can't be drawn token by token: tabs, whose width the column
    /// grid can't place, or steps past the diff's token limit.
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
        func glyph(
            _ token: CodeToken, in text: NSAttributedString, from: CodeToken?, to: CodeToken?
        )
            -> Glyph
        {
            let color =
                token.utf16Offset < text.length
                ? text.attribute(.foregroundColor, at: token.utf16Offset, effectiveRange: nil)
                    as? NSColor : nil
            return Glyph(
                text: token.text, color: color.map { Color(nsColor: $0) } ?? fallback,
                from: from.map { CGPoint(x: $0.column, y: $0.line) },
                to: to.map { CGPoint(x: $0.column, y: $0.line) })
        }
        glyphs = transition.changes.map { change in
            switch change {
            case .moved(let from, let to): glyph(to, in: new, from: from, to: to)
            case .removed(let token): glyph(token, in: old, from: token, to: nil)
            case .inserted(let token): glyph(token, in: new, from: nil, to: token)
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
