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

/// The type size every slide of a carousel shares, and whether its lines still overflow
/// the frame at the smallest size allowed.
nonisolated struct CarouselFit: Equatable, Sendable {
    var fontSize: Double
    var overflows = false
}

extension CarouselPaginator {
    /// Slides shorter than this still size their type as if they held this many lines.
    static let fittedMinimumRows = 8

    /// Clear space kept around the card on each side, as a fraction of the slide's short side.
    static let fittedMargin = 0.05

    /// The largest type at which the widest line and the tallest slide (at least
    /// `fittedMinimumRows` rows, wrapped rows included) fit the frame with every cue drawn.
    /// A probe slide is measured and its type scaled by the room left; layout grows more
    /// slowly than the font, so each step lands below the answer and the steps converge.
    static func fit(
        _ base: SnapshotConfig, slides: [Slide], cues: Cues, size: CarouselSlideSize
    ) -> CarouselFit {
        let floor = ExportManager.carouselMinimumFontSize
        guard let last = slides.last else { return CarouselFit(fontSize: floor) }
        let lines = slides.map { $0.text.components(separatedBy: "\n") }
        let cells = cellWidth(
            font: CodeFont.resolved(family: base.fontName, size: 20, ligatures: false))
        let widths = lines.map { $0.map(cells) }
        func rows(_ width: Double) -> Int {
            guard let wrap = base.wrapColumns, wrap > 0 else { return 1 }
            return max(1, Int((width / Double(wrap)).rounded(.up)))
        }
        let widest = zip(lines.joined(), widths.joined()).max { $0.1 < $1.1 }
        let tallest = widths.map { $0.reduce(0) { $0 + rows($1) } }.max() ?? 0
        let filler = max(fittedMinimumRows, tallest) - rows(widest?.1 ?? 0)
        // Past this many characters no frame holds a line above the floor, and a longer
        // probe would only cost highlighting time.
        let probeLines =
            [String((widest?.0 ?? "").prefix(320))] + Array(repeating: "x", count: max(0, filler))
        let probe = Slide(
            text: probeLines.joined(separator: "\n"), firstLine: last.firstLine,
            lineCount: probeLines.count)

        let frame = size.pixels
        let margin = 2 * fittedMargin * min(frame.width, frame.height)
        func fill(_ fontSize: Double) -> Double {
            // The first of several slides carries every cue, the "continues" label included.
            let measured = naturalSize(
                slideConfig(
                    base, slide: probe, at: 0, of: slides.count, cues: cues, fontSize: fontSize))
            return max(
                measured.width / (frame.width - margin), measured.height / (frame.height - margin))
        }
        var fontSize = 20.0
        for _ in 0..<8 {
            let ratio = fill(fontSize)
            guard ratio > 0 else { return CarouselFit(fontSize: floor) }
            let next = fontSize / ratio
            let settled = abs(next - fontSize) < 0.25
            fontSize = next
            if settled { break }
        }
        let fitted = max(floor, fontSize.rounded(.down))
        return CarouselFit(fontSize: fitted, overflows: fitted == floor && fill(floor) > 1)
    }

    /// The canvas at its own size, laid out as the export lays it out before framing it.
    static func naturalSize(_ config: SnapshotConfig) -> CGSize {
        var measured = CGSize.zero
        ImageRenderer(content: SnapshotCanvas(config: config)).render { size, _ in
            measured = size
        }
        return measured
    }

    /// A line's width in cells of `font`. A character the font lacks, such as CJK or emoji,
    /// is drawn by a wider fallback font, so it counts as two cells; a tab as four.
    private static func cellWidth(font: NSFont) -> (String) -> Double {
        let cell = CodeFont.advance(of: "0", in: font)
        var cache: [Character: Double] = ["\t": 4]
        return { line in
            line.reduce(0) { total, character in
                if let width = cache[character] { return total + width }
                var units = Array(String(character).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: units.count)
                let mapped = CTFontGetGlyphsForCharacters(
                    font as CTFont, &units, &glyphs, units.count)
                let width = mapped ? CodeFont.advance(of: character, in: font) / cell : 2
                cache[character] = width
                return total + width
            }
        }
    }
}
