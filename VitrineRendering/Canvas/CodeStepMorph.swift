import SwiftUI
import VitrineDomain

/// A preview-only change from one code step to the next. Exports never carry one.
public struct CodeStepAnimation: Equatable {
    public static let duration = 0.6

    public let id: Int
    public let from: String
    public let to: String
    /// Whether tokens travel. Off, the steps cross-fade in place.
    public let moves: Bool
    let transition: CodeStepTransition

    /// `nil` when the change can't be drawn token by token: tabs, whose width the
    /// column grid can't place, or steps past the diff's limits.
    public init?(id: Int, from: String, to: String, moves: Bool) {
        guard !from.isEmpty, !to.isEmpty, !from.contains("\t"), !to.contains("\t"),
            let transition = CodeStepTransition.between(from, to)
        else { return nil }
        self.id = id
        self.from = from
        self.to = to
        self.moves = moves
        self.transition = transition
    }

    /// By identity, so comparing canvases never walks the token lists.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Where each token is at the start and end of a step change, in grid cells: x is the
/// column and y the line.
struct CodeStepMorphLayout {
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

    let glyphs: [Glyph]

    init(
        _ animation: CodeStepAnimation, language: Language, theme: VitrineDomain.Theme,
        font: NSFont
    ) {
        let highlighter = HighlightManager.shared
        let old = highlighter.attributedString(
            for: animation.from, language: language, theme: theme, font: font)
        let new = highlighter.attributedString(
            for: animation.to, language: language, theme: theme, font: font)
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
        glyphs = animation.transition.items.flatMap { item -> [Glyph] in
            switch item.change {
            case .moved(let from, let to)
            where animation.moves || (from.line == to.line && from.column == to.column):
                return [glyph(to, in: new, from: from, to: to)]
            case .moved(let from, let to):
                return [
                    glyph(from, in: old, from: from, to: nil),
                    glyph(to, in: new, from: nil, to: to),
                ]
            case .removed(let token):
                return [glyph(token, in: old, from: token, to: nil)]
            case .inserted(let token):
                return [glyph(token, in: new, from: nil, to: token)]
            }
        }
    }

    /// One line's height as SwiftUI lays out the code text, so rows land where it puts them.
    static func lineHeight(of font: Font, in context: GraphicsContext) -> CGFloat {
        context.resolve(Text(verbatim: "0").font(font))
            .measure(in: CGSize(width: CGFloat.infinity, height: .infinity)).height
    }
}

/// Draws a code step change: tokens shared by both steps glide (or stay, cross-fading
/// the rest, under Reduce Motion), removed ones fade out and new ones fade in. The card
/// eases between the two steps' plain text sizes, measured from that text itself.
struct CodeStepMorphView: View {
    let animation: CodeStepAnimation
    let language: Language
    let theme: VitrineDomain.Theme
    let font: NSFont
    let lineSpacing: CGFloat

    @State private var progress = 0.0

    var body: some View {
        CodeStepMorphFrame(progress: progress) {
            plainText(animation.from)
            plainText(animation.to)
            CodeStepMorphGlyphs(
                layout: CodeStepMorphLayout(
                    animation, language: language, theme: theme, font: font),
                font: Font(font), advance: CodeFont.advance(of: "0", in: font),
                lineSpacing: lineSpacing, progress: progress)
        }
        .accessibilityRepresentation { Text(verbatim: animation.to) }
        .onAppear {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: CodeStepAnimation.duration)) {
                progress = 1
            }
        }
    }

    private func plainText(_ code: String) -> some View {
        Text(
            HighlightManager.shared.swiftUIAttributedString(
                for: code, language: language, theme: theme, font: font)
        )
        .lineSpacing(lineSpacing)
        .hidden()
    }
}

/// Sizes itself between its first two subviews and gives the last one that size.
struct CodeStepMorphFrame: Layout {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let from = subviews[0].sizeThatFits(.unspecified)
        let to = subviews[1].sizeThatFits(.unspecified)
        let t = CGFloat(progress)
        return CGSize(
            width: from.width + (to.width - from.width) * t,
            height: from.height + (to.height - from.height) * t)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: bounds.origin,
                proposal: index == 2 ? ProposedViewSize(bounds.size) : .unspecified)
        }
    }
}

private struct CodeStepMorphGlyphs: View, Animatable {
    let layout: CodeStepMorphLayout
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
            let pitch = CodeStepMorphLayout.lineHeight(of: font, in: context) + lineSpacing
            for glyph in layout.glyphs {
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
