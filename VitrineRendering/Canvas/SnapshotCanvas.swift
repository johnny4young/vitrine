import SwiftUI
import VitrineDomain

/// The SwiftUI view that becomes the exported PNG. WYSIWYG: what you see
/// here is exactly what `ImageRenderer` exports.
///
/// The card hugs its content (like ray.so) with a subtle border and an offset
/// shadow. Highlighting is computed synchronously in `body` (not via `.task`)
/// because `ImageRenderer` does not run async view lifecycle, so the exported
/// image must be fully highlighted at render time.
public struct SnapshotCanvas: View, Equatable {
    public let config: SnapshotConfig

    /// When set, the canvas is rendered at this exact logical size instead of
    /// hugging its content. Fixed-size destination presets (e.g. OpenGraph
    /// 1200×630) use this so the exported image has guaranteed dimensions; the
    /// card is centered and the background fills the frame.
    public var fixedSize: CGSize?

    /// The stage's step change in flight, drawn in place of the plain code text.
    public var codeStepAnimation: CodeStepAnimation?

    public init(
        config: SnapshotConfig, fixedSize: CGSize? = nil,
        codeStepAnimation: CodeStepAnimation? = nil
    ) {
        self.config = config
        self.fixedSize = fixedSize
        self.codeStepAnimation = codeStepAnimation
    }

    public var body: some View {
        let fit = config.counterLegendFit(in: fixedSize)
        if fit.entries.isEmpty && fit.dropped == 0 {
            watermarkedCanvas
        } else if fixedSize != nil {
            // A fixed frame can't grow, so the band covers its bottom edge. The capture
            // keeps the whole frame, which keeps marks on their content.
            watermarkedCanvas
                .overlay(alignment: .bottom) {
                    if !fit.entries.isEmpty { legendBand(fit.entries) }
                }
                .clipped()
                .preference(
                    key: CounterLegendReportKey.self,
                    value: CounterLegendReport(dropped: fit.dropped))
        } else {
            CounterLegendStack {
                watermarkedCanvas
                legendBand(fit.entries, fillsHeight: true)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: CounterLegendReportKey.self,
                                value: CounterLegendReport(height: proxy.size.height))
                        }
                    }
            }
            .fixedSize()
        }
    }

    private func legendBand(
        _ entries: [CounterLegend.Entry], fillsHeight: Bool = false
    ) -> some View {
        CounterLegendBand(
            entries: entries,
            font: config.counterLegendFont,
            textColor: HighlightManager.shared.gutterForegroundColor(for: config.theme),
            background: cardBackgroundColor,
            fillsHeight: fillsHeight)
    }

    private var watermarkedCanvas: some View {
        // The optional brand watermark composites onto the finished canvas.
        // `WatermarkOverlay` is a no-op when `config.watermark` is nil — it returns the
        // content unchanged — so the default render and every golden stay byte-for-byte
        // identical; only an explicitly resolved watermark adds the corner mark.
        canvasContent
            .modifier(SlidePageBadgeOverlay(cue: config.slideCue, watermark: config.watermark))
            .modifier(WatermarkOverlay(watermark: config.watermark))
    }

    /// The canvas itself, before any watermark. The default (no annotations) path is
    /// left byte-for-byte unchanged so every golden render is unaffected; annotations
    /// only restructure the canvas when the user has actually added one.
    @ViewBuilder
    private var canvasContent: some View {
        if config.annotations.isEmpty {
            plainCanvas
        } else {
            annotatedCanvas
        }
    }

    /// The original canvas: background filling the frame with the code card centered
    /// (fixed-size) or hugging its content.
    @ViewBuilder
    private var plainCanvas: some View {
        if let fixedSize {
            // The background fills the whole frame; the code card is centered
            // within it. `.clipped()` guarantees the render never exceeds the
            // requested size even if the card is larger than the frame.
            styledContent
                .frame(
                    width: fixedSize.width, height: fixedSize.height,
                    alignment: config.canvasAlignment
                )
                .background(BackgroundView(style: config.background))
                .clipped()
        } else {
            styledContent
                .background(BackgroundView(style: config.background))
                .fixedSize()
        }
    }

    /// The padded content card — the shared unit both canvas paths frame and back.
    private var styledContent: some View {
        contentCard.canvasPart(.card).padding(config.canvasInsets)
    }

    /// The card body: a beautified framed image ("beautify any image"), or the code card.
    /// Both receive identical padding / background / shadow framing from the canvas paths.
    @ViewBuilder
    private var contentCard: some View {
        if config.usesImageContent, let reference = config.foregroundImage {
            imageCard(reference).reportsSnapCard()
        } else {
            codeCard.reportsSnapCard()
        }
    }

    private func imageCard(_ reference: ImageReference) -> some View {
        ImageCard(
            framed: FramedImageView(
                reference: reference,
                frame: config.imageFrame,
                appearance: config.imageFrameAppearance,
                title: config.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            cornerRadius: config.cornerRadius,
            shadow: cardShadow)
    }

    /// The canvas with annotations composited on top: the sharp canvas, a
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
            if hasSpotlightAnnotations {
                spotlightDim
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
                .frame(
                    width: fixedSize.width, height: fixedSize.height,
                    alignment: config.canvasAlignment
                )
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

    /// Whether any annotation is a spotlight region (drives the dim overlay).
    private var hasSpotlightAnnotations: Bool {
        config.annotations.contains { $0.kind == .spotlight }
    }

    /// The scrim a spotlight leaves over everything else.
    private static let spotlightDimOpacity: Double = 0.55

    /// Darkens the whole canvas except the spotlight regions: one
    /// even-odd-filled path — the full canvas rect minus every spotlight's rounded
    /// rect — so multiple spotlights punch multiple holes in a single scrim rather
    /// than stacking scrims. Sits above the content and any blur, below the marks,
    /// so arrows and callouts stay at full brightness.
    private var spotlightDim: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                for annotation in config.annotations where annotation.kind == .spotlight {
                    path.addRoundedRect(
                        in: annotation.rect(in: size),
                        cornerSize: CGSize(width: 10, height: 10))
                }
            }
            .fill(Color.black.opacity(Self.spotlightDimOpacity), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
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
    /// numbers or a highlight never reflows the code.
    private static let codeLineSpacing: CGFloat = 4

    private var codeCard: some View {
        let diff = config.diffDocument
        return VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            if config.showChrome {
                WindowChrome(
                    title: config.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    titleColor: HighlightManager.shared.gutterForegroundColor(for: config.theme)
                )
                .canvasPart(.chrome)
            }
            // Optional metadata header (filename/title/caption/language badge),
            // shown only when configured so the default render is unchanged.
            // A hairline divider separates it from the code so the
            // header frames the body without crowding it.
            if !config.metadata.isEmpty {
                SnapshotHeader(
                    metadata: config.metadata,
                    language: config.language,
                    theme: config.theme
                )
                .canvasPart(.header)
                Divider()
                    .overlay(
                        HighlightManager.shared.gutterForegroundColor(for: config.theme)
                            .opacity(0.12))
            }
            if config.showDiffStats, let diff {
                DiffStatsHeader(
                    document: diff,
                    path: diff.singleFilePath(redacting: config.redactedLineRanges),
                    font: CodeFont.resolved(
                        family: config.fontName, size: DiffStatsHeader.fontSize, ligatures: false),
                    textColor: HighlightManager.shared.gutterForegroundColor(for: config.theme))
            }
            codeBody(diff: diff).canvasPart(.code)
                .reportsSnapCode(config, lineSpacing: Self.codeLineSpacing)
            if let cue = config.slideCue, cue.rangeLabel != nil || cue.continuationLabel != nil {
                slideCueFooter(cue)
            }
        }
        .padding(.horizontal, Self.cardHorizontalInset)
        .padding(.vertical, Self.cardVerticalInset)
        .frame(minWidth: 360, alignment: .leading)
        // Pinned here so the card keeps hugging its code: a Spacer in the footer row
        // would stretch a fixed-size card to the whole slide.
        .overlay(alignment: .bottomTrailing) {
            if let continuation = config.slideCue?.continuationLabel {
                slideCueLabel(continuation)
                    .padding(.trailing, Self.cardHorizontalInset)
                    .padding(.bottom, Self.cardVerticalInset)
            }
        }
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
                .strokeBorder(Brand.Palette.exportedCardBorder, lineWidth: Brand.Stroke.hairline)
        )
        .modifier(
            CardShadow(
                cornerRadius: config.cornerRadius,
                opaqueFill: NSColor(cardBackgroundColor).alphaComponent < 1
                    ? nil : cardBackgroundColor,
                shadow: cardShadow))
    }

    private static let cardHorizontalInset: CGFloat = 26
    private static let cardVerticalInset: CGFloat = 22

    /// Reserves the row's height and both labels' width; the continuation itself is drawn
    /// by the card's trailing overlay.
    private func slideCueFooter(_ cue: SlideCue) -> some View {
        HStack(spacing: 24) {
            if let range = cue.rangeLabel { slideCueLabel(range) }
            if let continuation = cue.continuationLabel { slideCueLabel(continuation).hidden() }
        }
    }

    private func slideCueLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(
                Font(
                    CodeFont.resolved(
                        family: config.fontName, size: config.fontSize * 0.8, ligatures: false))
            )
            .foregroundStyle(
                HighlightManager.shared.gutterForegroundColor(for: config.theme).opacity(0.6)
            )
            .lineLimit(1)
            .fixedSize()
    }

    /// The code body, soft-wrapped to `wrapWidth` when the user enabled line wrapping
    /// (Style pane). Off — the default — `codeRows` renders at its natural width so the
    /// signature size-to-content card is byte-for-byte unchanged (the goldens). With wrap
    /// on, the card sizes to the wrap width and long lines wrap; in the gutter path the
    /// continuation hangs under the code column (the line number stays on the first row).
    @ViewBuilder
    private func codeBody(diff: DiffDocument?) -> some View {
        if config.usesLineRows {
            codeRows(diff: diff)
        } else if let wrapWidth {
            codeRows(diff: diff).frame(width: wrapWidth, alignment: .leading)
        } else {
            codeRows(diff: diff)
        }
    }

    /// The code itself: a single `Text` for the default look, or a row-by-row layout
    /// when a line-number gutter or a selected-line highlight is enabled.
    /// Keeping the plain path untouched means the signature render is unchanged
    /// unless the user opts into the new chrome.
    @ViewBuilder
    private func codeRows(diff: DiffDocument?) -> some View {
        if config.usesLineRows {
            let displayRows = config.diffContextLines.flatMap {
                diff?.displayRows(contextLines: $0, keeping: config.highlightedLineRanges)
            }
            let rows = highlightedCodeLines
            let lines = CodeLinesView(
                rows: rows,
                displayRows: displayRows,
                showLineNumbers: config.showLineNumbers,
                firstLineNumber: config.firstLineNumber + terminalCrop.rowOffset,
                highlightedRanges: terminalCrop.localRanges(
                    LineHighlight.normalize(config.highlightedLineRanges)),
                redactedRanges: terminalCrop.localRanges(
                    LineHighlight.normalize(config.redactedLineRanges)),
                font: codeFont,
                lineSpacing: Self.codeLineSpacing,
                codeColumnWidth: wrapWidth,
                textColor: HighlightManager.shared.gutterForegroundColor(for: config.theme),
                highlightColor: HighlightManager.shared.lineHighlightColor(for: config.theme),
                dimsUnfocused: config.focusHighlightedLines,
                diffDecorations: config.diffDecorations,
                wordMarks: wordMarks(rows: rows, diff: diff)
            )
            // An empty capture's placeholder is not a diff, so it shows once, full width.
            if config.diffUsesSplitView, !config.code.isEmpty, let diff {
                SplitDiffLinesView(
                    lines: lines,
                    rows: diff.splitRows(
                        displayRows ?? diff.rowKinds.indices.map { .line($0 + 1) },
                        firstLineNumber: config.firstLineNumber,
                        redacting: config.redactedLineRanges)
                )
                .textSelection(.enabled)
            } else {
                lines.textSelection(.enabled)
            }
        } else if let animation = codeStepAnimation, animation.to == config.code,
            config.language != .terminal, wrapWidth == nil
        {
            CodeStepMorphView(
                animation: animation, text: highlightedCode, font: codeFont,
                lineSpacing: Self.codeLineSpacing
            )
            .id(animation.id)
        } else {
            let code = highlightedCode
            Text(code)
                .lineSpacing(Self.codeLineSpacing)
                .textSelection(.enabled)
                // Keep selection's internal bridge out of the accessibility tree,
                // while retaining the current visible characters as real text.
                .accessibilityRepresentation {
                    Text(verbatim: String(code.characters))
                }
        }
    }

    /// Computed once per render from the drawn rows, so the offsets match their characters.
    private func wordMarks(rows: [AttributedString], diff: DiffDocument?) -> [Int: [Range<Int>]] {
        guard config.diffUsesWordMarks, !config.code.isEmpty, let diff else { return [:] }
        return diff.wordMarks(
            lines: rows.map { String($0.characters) }, redacting: config.redactedLineRanges)
    }

    private var cardShadow: Brand.ShadowStyle { config.cardShadow }

    /// The resolved code font (the named font, or a monospaced system fallback),
    /// shared by highlighting and the line-number gutter so the gutter column is
    /// measured from the exact font the code is drawn in. The opt-in
    /// ligature setting is baked into the font here so the export and editor agree.
    private var codeFont: NSFont {
        CodeFont.resolved(
            family: config.fontName, size: config.fontSize, ligatures: config.fontLigatures)
    }

    /// The soft-wrap width in points when line wrapping is on: `wrapColumns` columns of
    /// the code font's digit advance, or `nil` to let lines run full width (the default).
    /// A monospaced code font makes this an exact column count; a proportional font
    /// approximates it. Measured from `CodeFont.advance` so it tracks the real glyph
    /// advance of the font the code is drawn in (the same source the gutter column uses).
    private var wrapWidth: CGFloat? {
        guard let columns = config.wrapColumns else { return nil }
        return CGFloat(columns) * CodeFont.advance(of: "0", in: codeFont)
    }

    /// The terminal color palette for the active theme — drives both the ANSI text
    /// colors and the card background when rendering terminal output.
    private var terminalPalette: ANSIPalette {
        ANSIPalette.resolved(for: config.theme, mode: config.terminalPalette)
    }

    /// An empty capture shows the placeholder, which is not output a cursor could follow.
    private var terminalCursor: TerminalCursorStyle {
        config.code.isEmpty ? .hidden : config.terminalCursor
    }

    /// Rows keep their screen numbers, so the gutter and line marks follow the crop.
    private var terminalCrop: TerminalCrop {
        config.code.isEmpty ? TerminalCrop() : config.activeTerminalCrop
    }

    /// The card fill: the syntax theme's background, or the terminal palette's
    /// background (theme-matched) when rendering ANSI terminal output.
    private var cardBackgroundColor: Color {
        config.language == .terminal
            ? Color(nsColor: terminalPalette.defaultBackground)
            : HighlightManager.shared.backgroundColor(for: config.theme)
    }

    private var highlightedCode: AttributedString {
        let placeholder = "// Paste or type code…"
        let source = config.code.isEmpty ? placeholder : config.code
        // Terminal output is colored by its own ANSI escape codes, not by syntax
        // highlighting, so it goes through the ANSI path rather than Highlightr — but
        // the palette still follows the chosen theme (light themes get a light terminal).
        if config.language == .terminal {
            return HighlightManager.shared.terminalAttributedString(
                for: source, theme: config.theme, font: codeFont,
                columns: config.terminalColumns, palette: config.terminalPalette,
                cursor: terminalCursor, crop: terminalCrop)
        }
        return HighlightManager.shared.swiftUIAttributedString(
            for: source,
            language: config.language,
            theme: config.theme,
            font: codeFont
        )
    }

    /// The highlighted code pre-split into rows and cached for the gutter/diff
    /// layout — the same source/placeholder and terminal-vs-code routing as
    /// `highlightedCode`, but returning the cached line array so the split doesn't
    /// rebuild on every `body` pass.
    private var highlightedCodeLines: [AttributedString] {
        let placeholder = "// Paste or type code…"
        let source = config.code.isEmpty ? placeholder : config.code
        if config.language == .terminal {
            var rows = HighlightManager.shared.terminalAttributedLines(
                for: source, theme: config.theme, font: codeFont,
                columns: config.terminalColumns, palette: config.terminalPalette,
                cursor: terminalCursor, crop: terminalCrop)
            guard terminalCursor != .hidden, !config.redactedLineRanges.isEmpty else { return rows }
            // A mask takes its length from its row, so a cursor must not reach a redacted one.
            let bare = HighlightManager.shared.terminalAttributedLines(
                for: source, theme: config.theme, font: codeFont,
                columns: config.terminalColumns, palette: config.terminalPalette,
                crop: terminalCrop)
            let redactions = terminalCrop.localRanges(
                LineHighlight.normalize(config.redactedLineRanges))
            for index in rows.indices where LineHighlight.contains(redactions, line: index + 1) {
                rows[index] = index < bare.count ? bare[index] : AttributedString()
            }
            return rows
        }
        return HighlightManager.shared.swiftUIAttributedLines(
            for: source, language: config.language, theme: config.theme, font: codeFont)
    }
}

/// The framed image as a card, elevated with the code card's shadow. The treatment is
/// frame-aware so each frame reads as one object:
/// - a **device** mockup defines its own silhouette, so it gets only the shadow;
/// - a **window/browser** frame is its own edge, so it is rounded with no hairline;
/// - a **plain** image keeps the rounded clip and hairline for a crisp edge.
private struct ImageCard: View {
    let framed: FramedImageView
    let cornerRadius: CGFloat
    let shadow: Brand.ShadowStyle

    @Environment(\.foregroundImageStore) private var store

    var body: some View {
        let rounded = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch framed.frame {
        case .macBook, .iPhone:
            framed.brandShadow(shadow)
        case .macOSWindow, .browser:
            framed.clipShape(rounded).modifier(cardShadow)
        case .none:
            framed
                .clipShape(rounded)
                .overlay(
                    rounded.strokeBorder(
                        Brand.Palette.exportedCardBorder, lineWidth: Brand.Stroke.hairline)
                )
                .modifier(cardShadow)
        }
    }

    private var cardShadow: CardShadow {
        CardShadow(
            cornerRadius: cornerRadius, opaqueFill: framed.opaqueFill(in: store), shadow: shadow)
    }
}

/// Casts the card's shadow from a plain rounded rectangle behind it, so RenderBox does not
/// rasterize and blur the whole card. Only a card that paints `opaqueFill` edge to edge can
/// hide that rectangle; any other card, or an unblurred shadow, stays on the card itself.
private struct CardShadow: ViewModifier {
    let cornerRadius: CGFloat
    let opaqueFill: Color?
    let shadow: Brand.ShadowStyle

    func body(content: Content) -> some View {
        if let opaqueFill, shadow.radius > 0 {
            content.background {
                // Inset so the fill stays out of the card's anti-aliased edge.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .inset(by: 0.5)
                    .fill(opaqueFill)
                    .brandShadow(shadow)
            }
        } else {
            content.brandShadow(shadow)
        }
    }
}
