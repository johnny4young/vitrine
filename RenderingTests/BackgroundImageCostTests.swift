import AppKit
import Testing

@testable import VitrineRendering

// MARK: - Image cache memory bound

@MainActor
@Suite("Image cache memory bound")
struct BackgroundImageCostTests {
    /// The decoded-byte cost drives the cache's `totalCostLimit`, so it must track the
    /// real bitmap size (pixels × 4), not the point size — a 2× asset would otherwise
    /// be under-counted fourfold and the memory bound would be meaningless.
    @Test func decodedByteCostMeasuresPixelsNotPoints() {
        let image = NSImage(size: NSSize(width: 100, height: 50))
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        image.addRepresentation(bitmap)
        // 200 × 100 pixels × 4 bytes, from the bitmap rep — not 100 × 50 points.
        #expect(BackgroundImageStore.decodedByteCost(of: image) == 200 * 100 * 4)
    }

    /// The decode-time cache cost must charge the surface's real backing bytes.
    /// A 16-bit-per-channel or row-padded bitmap holds more than 4 bytes per
    /// pixel; assuming RGBA8 would let the byte-bounded cache retain far more
    /// decoded memory than its limit reports.
    @Test func decodedSurfaceCostChargesActualBackingBytes() {
        // RGBA8, tightly packed: identical to the old 4-bytes-per-pixel figure.
        #expect(
            BackgroundImageStore.decodedSurfaceCost(bytesPerRow: 200 * 4, height: 100)
                == 200 * 100 * 4)
        // RGBA16: twice the bytes the pixel-count formula assumed.
        #expect(
            BackgroundImageStore.decodedSurfaceCost(bytesPerRow: 200 * 8, height: 100)
                == 200 * 100 * 8)
        // Row padding counts: the allocation is bytesPerRow-wide, not width-wide.
        #expect(
            BackgroundImageStore.decodedSurfaceCost(bytesPerRow: 832, height: 100) == 83_200)
        // Degenerate surfaces still cost at least 1, so the count limit applies.
        #expect(BackgroundImageStore.decodedSurfaceCost(bytesPerRow: 0, height: 100) == 1)
        // Overflow saturates instead of trapping.
        #expect(
            BackgroundImageStore.decodedSurfaceCost(bytesPerRow: Int.max, height: 2) == Int.max)
    }

    /// A vector-only image (no bitmap representation) reports the minimum cost of 1, so
    /// it is still subject to the count limit rather than being exempt at zero cost.
    @Test func decodedByteCostFloorsAtOneForAVectorImage() {
        let empty = NSImage(size: NSSize(width: 10, height: 10))
        #expect(BackgroundImageStore.decodedByteCost(of: empty) == 1)
    }
}
