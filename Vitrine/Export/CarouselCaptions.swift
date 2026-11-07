import Foundation
import VitrineDomain
import VitrineRendering

/// The text a carousel adds around its code: a caption per slide, and an optional cover and
/// closing card. Captions are kept by slide index, so a caption past the last slide waits
/// until a split brings that slide back, and an edit that moves lines never moves a caption.
nonisolated struct CarouselExtras: Equatable, Sendable {
    /// One sentence, which three lines of the band hold on every slide size.
    static let textLimit = 120

    var captions: [Int: String] = [:]
    var showsCover = false
    var coverTitle = ""
    var showsOutro = false
    var callToAction = ""
    var handle = ""

    /// A page of the carousel, in the order it is written.
    enum Page: Hashable {
        case cover
        case slide(Int)
        case outro
    }

    static func limited(_ text: String) -> String {
        String(text.replacingOccurrences(of: "\n", with: " ").prefix(textLimit))
    }

    func text(of page: Page) -> String {
        switch page {
        case .cover: coverTitle
        case .outro: callToAction
        case .slide(let index): captions[index] ?? ""
        }
    }

    mutating func setText(_ text: String, of page: Page) {
        switch page {
        case .cover: coverTitle = text
        case .outro: callToAction = text
        case .slide(let index): captions[index] = text.isEmpty ? nil : text
        }
    }

    func caption(at index: Int) -> String? {
        let text = captions[index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    func pageCount(slideCount: Int) -> Int {
        guard slideCount > 0 else { return 0 }
        return slideCount + (showsCover ? 1 : 0) + (showsOutro ? 1 : 0)
    }

    func page(at index: Int, slideCount: Int) -> Page {
        if showsCover, index == 0 { return .cover }
        let slide = index - (showsCover ? 1 : 0)
        return slide < slideCount ? .slide(slide) : .outro
    }

    func pageIndex(ofSlide slide: Int) -> Int { slide + (showsCover ? 1 : 0) }

    /// Whether any slide keeps a caption band, which every slide's type then makes room for.
    func hasCaptions(slideCount: Int) -> Bool {
        captions.keys.contains { $0 < slideCount && caption(at: $0) != nil }
    }

    /// Whether `page` lacks the text it is there for. Slides only count once captions are in use.
    func lacksText(_ page: Page, slideCount: Int) -> Bool {
        switch page {
        case .cover: coverTitle.allSatisfy(\.isWhitespace)
        case .outro: callToAction.allSatisfy(\.isWhitespace)
        case .slide(let index): hasCaptions(slideCount: slideCount) && caption(at: index) == nil
        }
    }

    func missingTextCount(slideCount: Int) -> Int {
        (0..<pageCount(slideCount: slideCount)).count {
            lacksText(page(at: $0, slideCount: slideCount), slideCount: slideCount)
        }
    }
}

extension CarouselPaginator {
    /// Every page the export writes, cover first and closing card last.
    static func pages(
        _ base: SnapshotConfig, slides: [Slide], cues: Cues, fontSize: Double?,
        extras: CarouselExtras
    ) -> [CarouselPage] {
        (0..<extras.pageCount(slideCount: slides.count)).map {
            page(at: $0, base, slides: slides, cues: cues, fontSize: fontSize, extras: extras)
        }
    }

    static func page(
        at index: Int, _ base: SnapshotConfig, slides: [Slide], cues: Cues, fontSize: Double?,
        extras: CarouselExtras
    ) -> CarouselPage {
        // Cover and closing cards are social cards in the capture's theme and background.
        let kind = extras.page(at: index, slideCount: slides.count)
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
            caption: extras.caption(at: slide))
    }
}
