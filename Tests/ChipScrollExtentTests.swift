import CoreGraphics
import Testing

@testable import Vitrine

@Suite("Chip strip scroll cue")
struct ChipScrollExtentTests {
    private let visible: CGFloat = 340
    private let chips: CGFloat = 800
    private var start: CGFloat { -ChipScrollExtent.edgeInset }
    private var end: CGFloat { chips + ChipScrollExtent.fadeWidth - visible }

    private func extent(at offset: CGFloat) -> ChipScrollExtent {
        ChipScrollExtent(offset: offset, visibleWidth: visible, chipsWidth: chips)
    }

    @Test func aStripThatFitsShowsNoCueAnywhere() {
        let exactFit = visible - ChipScrollExtent.edgeInset
        for width in [exactFit, exactFit - 40] {
            let edges = ChipScrollExtent(offset: start, visibleWidth: visible, chipsWidth: width)
                .edges
            #expect(edges == ChipScrollEdges())
        }
    }

    @Test func oneHiddenPointCountsAsOverflow() {
        let width = visible - ChipScrollExtent.edgeInset + 1
        let edges = ChipScrollExtent(offset: start, visibleWidth: visible, chipsWidth: width).edges
        #expect(edges.overflows && edges.hidesTrailing && !edges.hidesLeading)
    }

    @Test func edgesFollowThePosition() {
        #expect(extent(at: start).edges.hidesLeading == false)
        #expect(extent(at: start).edges.hidesTrailing)
        #expect(extent(at: 100).edges.hidesLeading)
        #expect(extent(at: 100).edges.hidesTrailing)
        #expect(extent(at: end).edges.hidesLeading)
        #expect(extent(at: end).edges.hidesTrailing == false)
    }

    @Test func pagingReachesTheEndWithoutSkippingChipsThenReturnsToTheStart() {
        // `scrollTo(x:)` lands at x minus the leading inset, as measured in the running app.
        var offset = start
        var pages = 0
        while extent(at: offset).edges.hidesTrailing {
            let next = extent(at: offset).nextScrollX - ChipScrollExtent.edgeInset
            #expect(next > offset)
            #expect(next - offset <= visible - 2 * ChipScrollExtent.fadeWidth)
            offset = next
            pages += 1
            #expect(pages < 20)
        }
        #expect(offset == end)
        #expect(extent(at: offset).nextScrollX == 0)
    }

    @Test func aRubberBandPastEitherEndKeepsTheEdgesHonest() {
        #expect(extent(at: start - 30).edges.hidesLeading == false)
        #expect(extent(at: end + 30).edges.hidesTrailing == false)
    }
}
