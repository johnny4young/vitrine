import AppKit
import Testing

@testable import VitrineRendering

// MARK: - Image cache memory bound

@MainActor
@Suite("Image cache memory bound")
struct BackgroundImageCostTests {
    /// The decode-time cache cost must charge the surface's real backing bytes.
    /// A 16-bit-per-channel or row-padded bitmap holds more than 4 bytes per
    /// pixel; assuming RGBA8 would let the byte-bounded cache retain far more
    /// decoded memory than its limit reports.
    @Test func decodedSurfaceCostChargesActualBackingBytes() {
        // RGBA8, tightly packed: identical to the old 4-bytes-per-pixel figure.
        #expect(
            DecodedImageCache.decodedSurfaceCost(bytesPerRow: 200 * 4, height: 100)
                == 200 * 100 * 4)
        // RGBA16: twice the bytes the pixel-count formula assumed.
        #expect(
            DecodedImageCache.decodedSurfaceCost(bytesPerRow: 200 * 8, height: 100)
                == 200 * 100 * 8)
        // Row padding counts: the allocation is bytesPerRow-wide, not width-wide.
        #expect(
            DecodedImageCache.decodedSurfaceCost(bytesPerRow: 832, height: 100) == 83_200)
        // Degenerate surfaces still cost at least 1, so the count limit applies.
        #expect(DecodedImageCache.decodedSurfaceCost(bytesPerRow: 0, height: 100) == 1)
        // Overflow saturates instead of trapping.
        #expect(
            DecodedImageCache.decodedSurfaceCost(bytesPerRow: Int.max, height: 2) == Int.max)
    }
}
