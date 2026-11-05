import Foundation
import VitrineDomain
import VitrineRendering

/// Splits a long snippet into the pages of a carousel export: N slides
/// of consecutive lines, balanced so the last slide never trails with a line or two.
/// Pure and deterministic, so the split is unit-testable and a re-export produces the
/// same slides.
enum CarouselPaginator {
    /// The lines-per-slide bounds offered by the export sheet. The floor keeps a slide
    /// from degenerating into a caption; the ceiling keeps 4:5 slides legible.
    static let linesPerSlideRange: ClosedRange<Int> = 4...30
    /// The default that reads well on a 1080×1350 slide at the default font size.
    static let defaultLinesPerSlide = 12

    /// Splits `code` into slides of at most `maxLinesPerSlide` consecutive lines,
    /// **balanced**: the slide count is fixed by the cap, then lines are distributed
    /// evenly so pages differ by at most one line (a 25-line snippet at 12 becomes
    /// 9 + 8 + 8, never 12 + 12 + 1). Empty input yields no slides.
    static func pages(for code: String, maxLinesPerSlide: Int) -> [String] {
        slides(for: code, maxLinesPerSlide: maxLinesPerSlide).map(\.text)
    }

    /// One slide's text and the 1-based document line it starts at, so line marks can
    /// follow their lines onto the slide.
    struct Slide: Equatable {
        var text: String
        var firstLine: Int
        var lineCount: Int

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

    /// With `preferBlankLineBreaks`, each boundary moves to a nearby blank line and that
    /// separator is left out of both slides, so a snippet without usable blank lines splits
    /// exactly as the balanced default. The cap always holds, and an all-blank slide is dropped.
    static func slides(
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
    private static func blankLineBreak(
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
    /// dropped because they are placed against the whole canvas.
    static func slideConfig(
        _ base: SnapshotConfig, slide: Slide, at index: Int, of count: Int, cues: Cues
    ) -> SnapshotConfig {
        var config = base
        config.clearContentMarks()
        config.code = slide.text
        config.highlightedLineRanges = slide.localRanges(base.highlightedLineRanges)
        config.redactedLineRanges = slide.localRanges(base.redactedLineRanges)
        // Focus dims every row outside a highlight, which is all of them without one.
        config.focusHighlightedLines =
            base.focusHighlightedLines && !config.highlightedLineRanges.isEmpty
        config.fontSize = max(config.fontSize, ExportManager.carouselMinimumFontSize)
        // A diff's stats and context fold describe the whole patch, not one slide.
        config.showDiffStats = false
        config.diffContextLines = nil

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

    /// Two-digit numbering keeps the files sorted everywhere.
    static func outputFilename(forSlideAt index: Int) -> String {
        String(format: "carousel-%02d.png", index + 1)
    }

    /// The names the export will write: the writer's own plan once a folder is chosen, so
    /// the sheet shows `carousel-01-2.png` when `carousel-01.png` is already there.
    static func plannedFilenames(slideCount: Int, in directory: URL?) -> [String] {
        let requested = (0..<slideCount).map(outputFilename(forSlideAt:))
        guard let directory,
            let plan = try? BatchOutputFiles.plan(filenames: requested, in: directory)
        else { return requested }
        return plan.map(\.image.lastPathComponent)
    }

    /// `carousel-01.png … 04.png · ~1.4 MB`; the size is left out until it is known.
    static func outputSummary(filenames: [String], estimatedBytes: Int?) -> String {
        var names = filenames.first ?? ""
        if filenames.count > 1, let last = filenames.last {
            names += " … " + last.replacingOccurrences(of: "carousel-", with: "")
        }
        guard let estimatedBytes else { return names }
        return "\(names) · ~\(Int64(estimatedBytes).formatted(.byteCount(style: .file)))"
    }

    /// A chosen folder as the user reads it, with their home folder shortened to `~`.
    static func displayPath(_ directory: URL, home: String?) -> String {
        let path = directory.path
        guard let home, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
