import Foundation
import VitrineDomain
import VitrineRendering

/// The text a carousel adds around its code: a caption per slide, and an optional cover and
/// closing card. A caption belongs to the document line that opens its slide, so it stays
/// with that slide while another split moves the boundaries, and waits while no slide opens
/// there.
nonisolated struct CarouselExtras: Equatable, Sendable {
    /// One sentence, which three lines of the band hold on every slide size.
    static let textLimit = 120

    /// Keyed by the slide's first document line.
    var captions: [Int: String] = [:]
    var showsCover = false
    var coverTitle = ""
    var showsOutro = false
    var callToAction = ""
    /// Filled by the sheet from the Brand Kit.
    var handle = ""

    /// A page of the carousel, in the order it is written.
    enum Page: Hashable {
        case cover
        case slide(Int)
        case outro
    }

    static func limited(_ text: String) -> String {
        String(text.split(whereSeparator: \.isNewline).joined(separator: " ").prefix(textLimit))
    }

    private static func isBlank(_ text: String) -> Bool { text.allSatisfy(\.isWhitespace) }

    /// A card without its text is a tile to fill in, not a page of the export.
    private func hasCover(tiles: Bool) -> Bool {
        showsCover && (tiles || !Self.isBlank(coverTitle))
    }
    private func hasOutro(tiles: Bool) -> Bool {
        showsOutro && (tiles || !Self.isBlank(callToAction))
    }

    /// Pages written, or with `tiles` the filmstrip's tiles, which keep an empty card.
    func pageCount(slideCount: Int, tiles: Bool = false) -> Int {
        guard slideCount > 0 else { return 0 }
        return slideCount + (hasCover(tiles: tiles) ? 1 : 0) + (hasOutro(tiles: tiles) ? 1 : 0)
    }

    func page(at index: Int, slideCount: Int, tiles: Bool = false) -> Page {
        let cover = hasCover(tiles: tiles)
        if cover, index == 0 { return .cover }
        let slide = index - (cover ? 1 : 0)
        return slide < slideCount ? .slide(slide) : .outro
    }

    func pages(slideCount: Int, tiles: Bool = false) -> [Page] {
        (0..<pageCount(slideCount: slideCount, tiles: tiles)).map {
            page(at: $0, slideCount: slideCount, tiles: tiles)
        }
    }

    func text(of page: Page, slides: [CarouselPaginator.Slide]) -> String {
        switch page {
        case .cover: coverTitle
        case .outro: callToAction
        case .slide(let index): captions[slides[index].firstLine] ?? ""
        }
    }

    mutating func setText(_ text: String, of page: Page, slides: [CarouselPaginator.Slide]) {
        switch page {
        case .cover: coverTitle = text
        case .outro: callToAction = text
        case .slide(let index): captions[slides[index].firstLine] = text.isEmpty ? nil : text
        }
    }

    func caption(for slide: CarouselPaginator.Slide) -> String? {
        let text = captions[slide.firstLine]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// Whether any slide shows a caption, which gives every slide the band.
    func hasCaptions(_ slides: [CarouselPaginator.Slide]) -> Bool {
        slides.contains { caption(for: $0) != nil }
    }

    /// Captions whose line opens no slide in this split.
    func hiddenCaptionCount(_ slides: [CarouselPaginator.Slide]) -> Int {
        let openers = Set(slides.map(\.firstLine))
        return captions.count { !openers.contains($0.key) && !Self.isBlank($0.value) }
    }

    /// Tiles still waiting for their text, counted in one pass over the slides.
    func missingTextCount(_ slides: [CarouselPaginator.Slide]) -> Int {
        guard !slides.isEmpty else { return 0 }
        let cards =
            (showsCover && Self.isBlank(coverTitle) ? 1 : 0)
            + (showsOutro && Self.isBlank(callToAction) ? 1 : 0)
        guard hasCaptions(slides) else { return cards }
        return cards + slides.count { caption(for: $0) == nil }
    }

    /// Whether `page` lacks the text it is there for. Slides only count once captions are in use.
    func lacksText(_ page: Page, slides: [CarouselPaginator.Slide]) -> Bool {
        switch page {
        case .cover: Self.isBlank(coverTitle)
        case .outro: Self.isBlank(callToAction)
        case .slide(let index): hasCaptions(slides) && caption(for: slides[index]) == nil
        }
    }
}

extension CarouselPaginator {
    /// Every page the export writes, cover first and closing card last.
    static func pages(
        _ base: SnapshotConfig, slides: [Slide], cues: Cues, fontSize: Double?,
        extras: CarouselExtras
    ) -> [CarouselPage] {
        let banded = extras.hasCaptions(slides)
        return extras.pages(slideCount: slides.count).map {
            page(
                $0, base, slides: slides, cues: cues, fontSize: fontSize, extras: extras,
                banded: banded)
        }
    }

    /// With `banded`, every slide keeps the caption band, empty or not, so the card sits at
    /// the same place on each.
    static func page(
        _ kind: CarouselExtras.Page, _ base: SnapshotConfig, slides: [Slide], cues: Cues,
        fontSize: Double?, extras: CarouselExtras, banded: Bool
    ) -> CarouselPage {
        // Cover and closing cards are social cards in the capture's theme and background.
        guard case .slide(let slide) = kind else {
            return .card(
                SocialCardModel(
                    title: kind == .cover ? extras.coverTitle : extras.callToAction,
                    author: extras.handle, template: .headline, theme: base.theme,
                    background: base.background, fontName: base.fontName))
        }
        return .slide(
            slideConfig(
                base, slide: slides[slide], at: slide, of: slides.count, cues: cues,
                fontSize: fontSize),
            caption: banded ? extras.caption(for: slides[slide]) ?? "" : nil)
    }
}
