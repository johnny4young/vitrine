import Foundation

/// Splits a long snippet into the pages of a carousel export (feature #15): N slides
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
    /// 13 + 12, never 12 + 12 + 1). Empty input yields no slides.
    static func pages(for code: String, maxLinesPerSlide: Int) -> [String] {
        let cap = max(1, maxLinesPerSlide)
        let lines = code.components(separatedBy: "\n")
        // Trailing newline artifact: "a\nb\n" splits into ["a","b",""] — drop the
        // final empty component so it never opens a blank slide.
        let trimmed = lines.last == "" ? Array(lines.dropLast()) : lines
        guard !trimmed.isEmpty, trimmed.contains(where: { !$0.isEmpty }) else { return [] }

        let slideCount = Int((Double(trimmed.count) / Double(cap)).rounded(.up))
        let base = trimmed.count / slideCount
        let remainder = trimmed.count % slideCount

        var pages: [String] = []
        var index = 0
        for slide in 0..<slideCount {
            // The first `remainder` slides take one extra line, so counts differ by ≤1.
            let length = base + (slide < remainder ? 1 : 0)
            pages.append(trimmed[index..<(index + length)].joined(separator: "\n"))
            index += length
        }
        return pages
    }
}
