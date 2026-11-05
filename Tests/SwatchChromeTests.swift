import AppKit
import SwiftUI
import Testing
import VitrineRendering

@testable import Vitrine

@Suite("Swatch chrome in the light appearance")
struct SwatchChromeTests {
    /// The row of pixels through a 28 pt swatch's center, on a white surface.
    private func centerRow(isSelected: Bool, fill: Color) throws -> [NSColor] {
        let renderer = ImageRenderer(
            content: FillSwatch(
                title: Text(verbatim: "Swatch"), isSelected: isSelected, size: 28, action: {}
            ) { fill }
            .padding(4)
            .background(.white)
            .environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let pixels = NSBitmapImageRep(cgImage: image)
        return try (0..<pixels.pixelsWide).map { x in
            try #require(pixels.colorAt(x: x, y: pixels.pixelsHigh / 2))
        }
    }

    @Test func aWhiteSwatchKeepsAVisibleEdgeOnWhite() throws {
        let darkest = try centerRow(isSelected: false, fill: .white)
            .map { Brand.Contrast.ratio(Color(nsColor: $0), on: .white) }
            .max()
        #expect(try #require(darkest) > 1.2)
    }

    /// Ring, surface, fill, surface, ring: the ring must not merge into a fill of its color.
    @Test func theSelectedRingStaysApartFromAFillOfItsOwnColor() throws {
        let row = try centerRow(isSelected: true, fill: Color(hex: "#4F46E5"))
        let isInk = row.map { Brand.Contrast.ratio(Color(nsColor: $0), on: .white) > 3 }
        let runs = zip([false] + isInk, isInk).filter { !$0 && $1 }.count
        #expect(runs == 3)
    }
}
