import SwiftUI

/// The SwiftUI view that becomes the exported PNG (CS-005). WYSIWYG: what you see
/// here is exactly what `ImageRenderer` exports.
///
/// The card hugs its content (like ray.so) with a subtle border and an offset
/// shadow. Highlighting is computed synchronously in `body` (not via `.task`)
/// because `ImageRenderer` does not run async view lifecycle, so the exported
/// image must be fully highlighted at render time.
struct SnapshotCanvas: View {
    let config: SnapshotConfig

    /// When set, the canvas is rendered at this exact logical size instead of
    /// hugging its content. Fixed-size destination presets (e.g. OpenGraph
    /// 1200×630) use this so the exported image has guaranteed dimensions; the
    /// card is centered and the background fills the frame (CS-020).
    var fixedSize: CGSize?

    var body: some View {
        // The default (no annotations) path is left byte-for-byte unchanged so every
        // golden render is unaffected; annotations only restructure the canvas when
        // the user has actually added one (CS-083).
        if config.annotations.isEmpty {
            plainCanvas
        } else {
            annotatedCanvas
        }
    }

    /// The original canvas: background filling the frame with the code card centered
    /// (fixed-size) or hugging its content (CS-005/CS-020).
    @ViewBuilder
    private var plainCanvas: some View {
        if let fixedSize {
            // The background fills the whole frame; the code card is centered
            // within it. `.clipped()` guarantees the render never exceeds the
            // requested size even if the card is larger than the frame.
            styledContent
                .frame(width: fixedSize.width, height: fixedSize.height)
                .background(BackgroundView(style: config.background))
                .clipped()
        } else {
            styledContent
                .background(BackgroundView(style: config.background))
                .fixedSize()
        }
    }

    /// The padded code card — the shared content both canvas paths frame and back.
    private var styledContent: some View {
        codeCard.padding(config.padding)
    }

    /// The canvas with annotations composited on top (CS-083): the sharp canvas, a
    /// blurred copy of it masked to the blur boxes (so each redaction box shows the
    /// content beneath it softened), and the arrow/text marks last. The blurred copy
    /// is the same view value, so it lays out identically and aligns exactly.
    @ViewBuilder
    private var annotatedCanvas: some View {
        let composite = ZStack {
            framedCanvas
            if hasBlurAnnotations {
                framedCanvas
                    .blur(radius: Self.blurRadius)
                    .mask { blurMask }
            }
        }
        .overlay { annotationMarks }

        if fixedSize != nil {
            composite.clipped()
        } else {
            composite.fixedSize()
        }
    }

    /// The framed-and-backed canvas (sharp), reused for the blurred copy so both
    /// layers share one layout.
    @ViewBuilder
    private var framedCanvas: some View {
        if let fixedSize {
            styledContent
                .frame(width: fixedSize.width, height: fixedSize.height)
                .background(BackgroundView(style: config.background))
        } else {
            styledContent
                .background(BackgroundView(style: config.background))
        }
    }

    /// Whether any annotation is a blur box (drives the extra blurred-copy layer).
    private var hasBlurAnnotations: Bool {
        config.annotations.contains { $0.kind == .blur }
    }

    /// The Gaussian radius applied to the blurred copy behind each redaction box.
    private static let blurRadius: CGFloat = 14

    /// A mask that is opaque only inside the blur boxes, so masking the blurred copy
    /// reveals softened content exactly there. Sized to the canvas via geometry so
    /// the normalized box coordinates denormalize correctly at any output size.
    private var blurMask: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Path { path in
                for annotation in config.annotations where annotation.kind == .blur {
                    path.addRoundedRect(
                        in: annotation.rect(in: size),
                        cornerSize: CGSize(width: 10, height: 10))
                }
            }
            .fill(Color.black)
        }
    }

    /// The arrow and text marks, drawn last so they sit above the code and any blur.
    /// Hit testing is disabled — in the export they are pure visuals, and in the
    /// editor the interactive overlay handles manipulation separately.
    private var annotationMarks: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                ForEach(config.annotations) { annotation in
                    AnnotationMarkView(annotation: annotation, size: size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// The per-line vertical gap, shared by the single-`Text` path
    /// (`.lineSpacing`) and the row-based path (`VStack` spacing) so toggling line
    /// numbers or a highlight never reflows the code (CS-021).
    private static let codeLineSpacing: CGFloat = 4

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            if config.showChrome {
                WindowChrome(
                    title: config.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    titleColor: HighlightManager.shared.gutterForegroundColor(for: config.theme))
            }
            // Optional metadata header (filename/title/caption/language badge),
            // shown only when configured so the default render is unchanged
            // (CS-022). A hairline divider separates it from the code so the
            // header frames the body without crowding it.
            if !config.metadata.isEmpty {
                SnapshotHeader(
                    metadata: config.metadata,
                    language: config.language,
                    theme: config.theme
                )
                Divider()
                    .overlay(
                        HighlightManager.shared.gutterForegroundColor(for: config.theme)
                            .opacity(0.12))
            }
            codeBody
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .frame(minWidth: 360, alignment: .leading)
        .background(HighlightManager.shared.backgroundColor(for: config.theme))
        .clipShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
                .strokeBorder(Brand.Palette.exportedCardBorder, lineWidth: Brand.Stroke.hairline)
        )
        // The elevated recipe, applied as a unit; only the radius is overridden
        // by the per-config "drop shadow" toggle (0 when off).
        .brandShadow(cardShadow)
    }

    /// The code body: a single `Text` for the default look, or a row-by-row layout
    /// when a line-number gutter or a selected-line highlight is enabled (CS-021).
    /// Keeping the plain path untouched means the signature render is unchanged
    /// unless the user opts into the new chrome.
    @ViewBuilder
    private var codeBody: some View {
        if config.usesLineRows {
            CodeLinesView(
                highlighted: highlightedCode,
                showLineNumbers: config.showLineNumbers,
                highlightedRanges: LineHighlight.normalize(config.highlightedLineRanges),
                font: codeFont,
                lineSpacing: Self.codeLineSpacing,
                textColor: HighlightManager.shared.gutterForegroundColor(for: config.theme),
                highlightColor: HighlightManager.shared.lineHighlightColor(for: config.theme),
                dimsUnfocused: config.focusHighlightedLines,
                diffDecorations: config.diffDecorations
            )
            .textSelection(.enabled)
        } else {
            Text(highlightedCode)
                .lineSpacing(Self.codeLineSpacing)
                .textSelection(.enabled)
        }
    }

    /// The exported card's drop shadow: the `Brand.Shadow.elevated` recipe with
    /// its radius driven by the config's effective shadow radius.
    private var cardShadow: Brand.ShadowStyle {
        Brand.ShadowStyle(
            color: Brand.Shadow.elevated.color,
            radius: config.effectiveShadowRadius,
            x: Brand.Shadow.elevated.x,
            y: Brand.Shadow.elevated.y
        )
    }

    /// The resolved code font (the named font, or a monospaced system fallback),
    /// shared by highlighting and the line-number gutter so the gutter column is
    /// measured from the exact font the code is drawn in (CS-021). The opt-in
    /// ligature setting is baked into the font here so the export and editor agree
    /// (CS-052).
    private var codeFont: NSFont {
        CodeFont.resolved(
            family: config.fontName, size: config.fontSize, ligatures: config.fontLigatures)
    }

    private var highlightedCode: AttributedString {
        let placeholder = "// Paste or type code…"
        let source = config.code.isEmpty ? placeholder : config.code
        let attributed = HighlightManager.shared.attributedString(
            for: source,
            language: config.language,
            theme: config.theme,
            font: codeFont
        )
        return AttributedString(attributed)
    }
}
