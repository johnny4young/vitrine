import SwiftUI
import VitrineDomain
import VitrineRendering

/// The slide frames a carousel exports, one per platform's post format.
nonisolated enum CarouselSlideSize: String, CaseIterable, Sendable {
    case linkedIn, instagram, x, story

    var pixels: CGSize {
        switch self {
        case .linkedIn: CGSize(width: 1080, height: 1350)
        case .instagram: CGSize(width: 1080, height: 1080)
        case .x: CGSize(width: 1920, height: 1080)
        case .story: CGSize(width: 1080, height: 1920)
        }
    }
}

/// What a carousel export writes: one PNG per slide, one PDF with a page per slide, or both.
nonisolated enum CarouselOutput: String, CaseIterable, Sendable {
    case pngSet, pdf, both

    var writesPNG: Bool { self != .pdf }
    var writesPDF: Bool { self != .pngSet }
}

extension CarouselPaginator {
    /// Slides shorter than this still size their type as if they held this many lines.
    static let fittedMinimumRows = 8

    /// Clear space kept around the card on each side, as a fraction of the slide's short side.
    static let fittedMargin = 0.05

    /// The one type size every slide shares: the largest at which the widest line and the
    /// tallest slide (at least `fittedMinimumRows` lines) fit the frame. A probe slide is
    /// measured and its type scaled by the room left; layout grows more slowly than the font,
    /// so each step lands below the answer and the steps converge on it.
    static func fittedFontSize(
        _ base: SnapshotConfig, slides: [Slide], cues: Cues, size: CarouselSlideSize
    ) -> Double {
        guard let last = slides.last else { return ExportManager.carouselMinimumFontSize }
        let lines = slides.flatMap { $0.text.components(separatedBy: "\n") }
        // Past this many columns no frame holds the line above the floor, and a longer probe
        // would only cost highlighting time.
        let widest = String((lines.max { columns($0) < columns($1) } ?? "").prefix(320))
        let rows = max(fittedMinimumRows, slides.map(\.lineCount).max() ?? 0)
        let probe = Slide(
            text: ([widest] + Array(repeating: "x", count: rows - 1)).joined(separator: "\n"),
            firstLine: last.firstLine, lineCount: rows)

        func measure(_ fontSize: Double) -> CGSize {
            let config = slideConfig(
                base, slide: probe, at: slides.count - 1, of: slides.count, cues: cues,
                fontSize: fontSize)
            var measured = CGSize.zero
            ImageRenderer(content: SnapshotCanvas(config: config)).render { size, _ in
                measured = size
            }
            return measured
        }
        let frame = size.pixels
        let margin = 2 * fittedMargin * min(frame.width, frame.height)
        func fill(_ fontSize: Double) -> Double {
            let measured = measure(fontSize)
            return max(
                measured.width / (frame.width - margin), measured.height / (frame.height - margin))
        }
        var fontSize = 20.0
        for _ in 0..<8 {
            let ratio = fill(fontSize)
            guard ratio > 0 else { return ExportManager.carouselMinimumFontSize }
            let next = fontSize / ratio
            let settled = abs(next - fontSize) < 0.25
            fontSize = next
            if settled { break }
        }
        return max(ExportManager.carouselMinimumFontSize, fontSize.rounded(.down))
    }

    /// Monospaced width, with a tab as wide as four spaces.
    private static func columns(_ line: String) -> Int {
        line.count + 3 * line.count { $0 == "\t" }
    }
}
