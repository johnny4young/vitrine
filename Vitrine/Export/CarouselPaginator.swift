import Foundation
import VitrineDomain
import VitrineRendering

/// How a document splits into slides. The sheet, the filmstrip, the editor's dividers and
/// the export all ask this value, so they can't disagree about where a slide breaks.
nonisolated struct CarouselSplit: Equatable, Sendable {
    /// The default reads well on a 1080×1350 slide at the default font size.
    var linesPerSlide = 12
    var prefersBlankLineBreaks = true

    func slides(of code: String) -> [CarouselPaginator.Slide] {
        CarouselPaginator.slides(
            for: code, maxLinesPerSlide: linesPerSlide,
            preferBlankLineBreaks: prefersBlankLineBreaks)
    }

    /// Off the main actor: a pass over a long document outlasts a frame.
    @concurrent func outcome(of code: String) async -> CarouselPaginator.Outcome {
        CarouselPaginator.Outcome(split: self, code: code)
    }

    @concurrent func dividers(in code: String) async -> [SlideDivider] {
        CarouselPaginator.dividers(for: slides(of: code), in: code)
    }
}

/// A boundary drawn in the code editor: the character that opens a slide and how to name it.
nonisolated struct SlideDivider: Equatable, Sendable {
    /// In UTF-16, the text view's unit.
    var offset: Int
    var slideNumber: Int
    var lineRange: String
    var isSingleLine = false

    /// Where this divider belongs after an edit, until the settled split replaces it. `nil`
    /// when the edit removed its position. Text typed at a slide's start stays on its line.
    func shifted(replacing range: NSRange, with replacement: String) -> SlideDivider? {
        let inserted = (replacement as NSString).length
        var moved = self
        if offset >= range.upperBound {
            if offset == range.location, !replacement.contains("\n") { return self }
            moved.offset += inserted - range.length
        } else if offset > range.location {
            return nil
        }
        return moved
    }
}

/// One settled split for the editor, and the text its offsets are true for. A `nil` source
/// means no dividers, whatever the text.
nonisolated struct SlideDividerLayout: Equatable, Sendable {
    var revision = 0
    var source: String?
    var dividers: [SlideDivider] = []
}

/// Splits a long snippet into the pages of a carousel export: N slides
/// of consecutive lines, balanced so the last slide never trails with a line or two.
/// Pure and deterministic, so the split is unit-testable and a re-export produces the
/// same slides.
enum CarouselPaginator {
    /// The lines-per-slide bounds offered by the export sheet. The floor keeps a slide
    /// from degenerating into a caption; the ceiling keeps 4:5 slides legible.
    static let linesPerSlideRange: ClosedRange<Int> = 4...30

    /// Splits `code` into slides of at most `maxLinesPerSlide` consecutive lines,
    /// **balanced**: the slide count is fixed by the cap, then lines are distributed
    /// evenly so pages differ by at most one line (a 25-line snippet at 12 becomes
    /// 9 + 8 + 8, never 12 + 12 + 1). Empty input yields no slides.
    static func pages(for code: String, maxLinesPerSlide: Int) -> [String] {
        slides(for: code, maxLinesPerSlide: maxLinesPerSlide).map(\.text)
    }

    /// One slide's text and the 1-based document line it starts at, so line marks can
    /// follow their lines onto the slide.
    nonisolated struct Slide: Equatable, Sendable {
        var text: String
        var firstLine: Int
        var lineCount: Int

        /// The document lines this slide holds, as the editor counts them.
        var lineRange: String {
            lineCount > 1 ? "\(firstLine)–\(firstLine + lineCount - 1)" : "\(firstLine)"
        }

        /// Split as `slides` splits: `"\r\n"` is one `Character`, so a `Character` split sees
        /// a CRLF slide as a single line.
        fileprivate var visibleLineCount: Int {
            text.components(separatedBy: "\n").count { !$0.allSatisfy(\.isWhitespace) }
        }

        /// Thirty 80-column lines stay well under this. Highlighting a slide past it would hold
        /// the main actor for several frames, so it isn't rendered until the export asks.
        static let maximumPreviewBytes = 8 * 1_024

        var canPreview: Bool { text.utf8.count <= Self.maximumPreviewBytes }

        /// Document line ranges clipped to this slide and renumbered from 1.
        func localRanges(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
            let lastLine = firstLine + lineCount - 1
            return LineHighlight.normalize(ranges).compactMap { range in
                let lower = max(range.lowerBound, firstLine)
                let upper = min(range.upperBound, lastLine)
                guard lower <= upper else { return nil }
                return (lower - firstLine + 1)...(upper - firstLine + 1)
            }
        }
    }

    /// One split of one document, with what can only be read off all of its slides.
    nonisolated struct Outcome: Equatable, Sendable {
        var split: CarouselSplit
        var code: String
        var slides: [Slide]
        var hasShortTail: Bool

        init(split: CarouselSplit, code: String) {
            self.split = split
            self.code = code
            slides = split.slides(of: code)
            hasShortTail = CarouselPaginator.hasShortTail(slides)
        }

        /// Empty until the split of `code` has finished: another document's slides with this
        /// document's marks could put a redaction on the wrong row.
        func slides(for code: String) -> [Slide] {
            self.code == code ? slides : []
        }
    }

    /// Balancing keeps counts close, but a blank-line break or trailing blank rows can still
    /// leave a last slide with under half the visible lines of the fullest one.
    nonisolated static func hasShortTail(_ slides: [Slide]) -> Bool {
        guard slides.count > 1, let last = slides.last else { return false }
        let fullest = slides.dropLast().map(\.visibleLineCount).max() ?? 0
        return last.visibleLineCount * 2 < fullest
    }

    /// One divider per slide after the first, at the character that opens it.
    nonisolated static func dividers(for slides: [Slide], in code: String) -> [SlideDivider] {
        guard slides.count > 1 else { return [] }
        var dividers: [SlideDivider] = []
        var line = 1
        var pending = slides.dropFirst().enumerated().makeIterator()
        var next = pending.next()
        for (offset, unit) in code.utf16.enumerated() where unit == 0x0A {
            line += 1
            guard let (index, slide) = next, slide.firstLine == line else { continue }
            dividers.append(
                SlideDivider(
                    offset: offset + 1, slideNumber: index + 2, lineRange: slide.lineRange,
                    isSingleLine: slide.lineCount == 1))
            next = pending.next()
        }
        return dividers
    }

    /// With `preferBlankLineBreaks`, each boundary moves to a nearby blank line and that
    /// separator is left out of both slides, so a snippet without usable blank lines splits
    /// exactly as the balanced default. The cap always holds, and an all-blank slide is dropped.
    nonisolated static func slides(
        for code: String, maxLinesPerSlide: Int, preferBlankLineBreaks: Bool = false
    ) -> [Slide] {
        let cap = max(1, maxLinesPerSlide)
        let lines = code.components(separatedBy: "\n")
        // Trailing newline artifact: "a\nb\n" splits into ["a","b",""] — drop the
        // final empty component so it never opens a blank slide.
        let trimmed = lines.last == "" ? Array(lines.dropLast()) : lines
        guard !trimmed.isEmpty, trimmed.contains(where: { !$0.isEmpty }) else { return [] }

        let slideCount = Int((Double(trimmed.count) / Double(cap)).rounded(.up))
        let isBlank =
            preferBlankLineBreaks
            ? trimmed.map { $0.allSatisfy(\.isWhitespace) } : []

        var slides: [Slide] = []
        var index = 0
        for slide in 0..<slideCount {
            // Rebalancing what is left keeps counts within one line of each other.
            let slidesLeft = slideCount - slide
            let balanced = (trimmed.count - index + slidesLeft - 1) / slidesLeft
            let bounds =
                blankLineBreak(
                    from: index, balanced: balanced, slidesAfter: slidesLeft - 1, cap: cap,
                    isBlank: isBlank) ?? (end: index + balanced, next: index + balanced)
            slides.append(
                Slide(
                    text: trimmed[index..<bounds.end].joined(separator: "\n"),
                    firstLine: index + 1, lineCount: bounds.end - index))
            index = bounds.next
        }
        return slides.filter { !$0.text.allSatisfy(\.isWhitespace) }
    }

    /// The blank run nearest the balanced boundary (earliest on a tie): where this slide
    /// ends and where the next starts. A run is only taken within a third of a slide of
    /// the boundary, so the balance survives and no thin slide is left behind.
    nonisolated private static func blankLineBreak(
        from start: Int, balanced: Int, slidesAfter: Int, cap: Int, isBlank: [Bool]
    ) -> (end: Int, next: Int)? {
        guard !isBlank.isEmpty, slidesAfter > 0 else { return nil }
        let tolerance = max(1, balanced / 3)
        let ideal = start + balanced
        let shortest = max(1, balanced - tolerance)
        let lowest = start + shortest
        let highest = min(start + cap, ideal + tolerance)
        guard lowest <= highest else { return nil }

        var best: (end: Int, next: Int)?
        for end in lowest...highest where end < isBlank.count && isBlank[end] && !isBlank[end - 1] {
            var next = end + 1
            while next < isBlank.count, isBlank[next] { next += 1 }
            let linesLeft = isBlank.count - next
            guard linesLeft >= slidesAfter * shortest, linesLeft <= slidesAfter * cap else {
                continue
            }
            if best.map({ abs(end - ideal) < abs($0.end - ideal) }) ?? true {
                best = (end, next)
            }
        }
        return best
    }

    /// The continuation cues the sheet offers. `.none` adds nothing, and a `nil`
    /// `lineNumbers` keeps the document's own gutter choice.
    struct Cues: Equatable {
        enum LineNumbers: Hashable {
            case continuing, restarting, off
        }

        var lineNumbers: LineNumbers?
        var showsPageBadge = false
        var showsContinuation = false
        var continuationLabel = ""

        static let none = Cues()
    }

    /// What one slide renders: `base` with only this page's lines. Highlighted and
    /// redacted lines follow their lines onto the slide; positional annotations are
    /// dropped because they are placed against the whole canvas. Without a `fontSize`,
    /// the document's own size is kept above the carousel floor.
    static func slideConfig(
        _ base: SnapshotConfig, slide: Slide, at index: Int, of count: Int, cues: Cues,
        fontSize: Double? = nil
    ) -> SnapshotConfig {
        var config = base
        config.clearContentMarks()
        config.code = slide.text
        config.highlightedLineRanges = slide.localRanges(base.highlightedLineRanges)
        config.redactedLineRanges = slide.localRanges(base.redactedLineRanges)
        // Focus dims every row outside a highlight, which is all of them without one.
        config.focusHighlightedLines =
            base.focusHighlightedLines && !config.highlightedLineRanges.isEmpty
        config.fontSize = fontSize ?? max(config.fontSize, ExportManager.carouselMinimumFontSize)
        // A diff's stats and context fold describe the whole patch, not one slide.
        config.showDiffStats = false
        config.diffContextLines = nil
        // Slides cut a hunk by source rows, which only the unified layout keeps intact.
        config.diffView = .unified

        switch cues.lineNumbers {
        case nil:
            break
        case .continuing:
            config.showLineNumbers = true
            config.firstLineNumber = slide.firstLine
        case .restarting:
            config.showLineNumbers = true
        case .off:
            config.showLineNumbers = false
        }

        // A lone slide has nothing to continue into.
        guard count > 1, cues.showsPageBadge || cues.showsContinuation else { return config }
        var cue = SlideCue()
        if cues.showsPageBadge { cue.pageLabel = "\(index + 1) / \(count)" }
        if cues.showsContinuation {
            // Matches a visible gutter, which may restart; without one, the document's lines.
            let first = config.showLineNumbers ? config.firstLineNumber : slide.firstLine
            let last = first + slide.lineCount - 1
            cue.rangeLabel = slide.lineCount > 1 ? "\(first)–\(last)" : "\(first)"
            if index < count - 1 { cue.continuationLabel = cues.continuationLabel }
        }
        config.slideCue = cue
        return config
    }

    /// `1080 × 1350`, read off the frame the export renders.
    static func slideSizeLabel(_ size: CGSize) -> String {
        "\(Int(size.width)) × \(Int(size.height))"
    }

    /// The text a capture may split: none for one the carousel refuses, so nothing of it can
    /// reach a tile, an estimate or a file.
    static func splittableCode(of config: SnapshotConfig) -> String {
        EditorView.carouselAccepts(config) ? config.code : ""
    }

    /// Two-digit numbering keeps the files sorted everywhere.
    static func outputFilename(forSlideAt index: Int) -> String {
        String(format: "carousel-%02d.png", index + 1)
    }

    static let pdfFilename = "carousel.pdf"

    /// The files `output` asks for, slide PNGs first and the PDF last.
    static func requestedFilenames(slideCount: Int, output: CarouselOutput) -> [String] {
        guard slideCount > 0 else { return [] }
        let images = output.writesPNG ? (0..<slideCount).map(outputFilename(forSlideAt:)) : []
        return images + (output.writesPDF ? [pdfFilename] : [])
    }

    /// The names the export will write: the writer's own plan once a folder is chosen, so
    /// the sheet shows `carousel-01-2.png` when `carousel-01.png` is already there.
    static func plannedFilenames(
        slideCount: Int, output: CarouselOutput = .pngSet, in directory: URL?
    ) -> [String] {
        let requested = requestedFilenames(slideCount: slideCount, output: output)
        guard let directory,
            let plan = try? BatchOutputFiles.plan(filenames: requested, in: directory)
        else { return requested }
        return plan.map(\.image.lastPathComponent)
    }

    /// `carousel-01.png … 04.png + carousel.pdf · ~1.4 MB`; the size is left out until known.
    static func outputSummary(filenames: [String], estimatedBytes: Int?) -> String {
        let (images, others) = splitImages(filenames)
        var names = images.first ?? ""
        if let last = lastFilenameSuffix(images) { names += " … " + last }
        names = ([names] + others).filter { !$0.isEmpty }.joined(separator: " + ")
        guard let estimatedBytes else { return names }
        return "\(names) · \(ExportSizeEstimate.shown(estimatedBytes))"
    }

    /// The same summary as VoiceOver should read it, without the ellipsis and the tilde.
    static func spokenOutputSummary(
        filenames: [String], estimatedBytes: Int?, bundle: Bundle = .main
    ) -> String {
        let (images, others) = splitImages(filenames)
        var names = images.first ?? ""
        if let last = lastFilenameSuffix(images) {
            names = String(localized: "\(names) to \(last)", bundle: bundle)
        }
        names = ([names] + others).filter { !$0.isEmpty }.joined(separator: ", ")
        guard let estimatedBytes else { return names }
        return "\(names), \(ExportSizeEstimate.spoken(estimatedBytes, bundle: bundle))"
    }

    private static func splitImages(_ filenames: [String]) -> ([String], [String]) {
        let isImage = { (name: String) in name.hasSuffix(".png") }
        return (filenames.filter(isImage), filenames.filter { !isImage($0) })
    }

    private static func lastFilenameSuffix(_ filenames: [String]) -> String? {
        guard filenames.count > 1 else { return nil }
        return filenames.last?.replacingOccurrences(of: "carousel-", with: "")
    }

    /// A chosen folder as the user reads it, with their home folder shortened to `~`.
    static func displayPath(_ directory: URL, home: String?) -> String {
        let path = directory.path
        guard let home, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
