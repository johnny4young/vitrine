import CoreGraphics
import Testing

@testable import Vitrine

@Suite("Export · render budget")
struct RenderBudgetTests {
    @Test("Fixed preset dimensions resolve to exact scaled pixels")
    func fixedPresetAllocation() throws {
        let allocation = try RenderBudget.export.allocation(
            for: CGSize(width: 1_200, height: 630), scale: 2)

        #expect(allocation.pixelWidth == 2_400)
        #expect(allocation.pixelHeight == 1_260)
        #expect(allocation.pixelCount == 3_024_000)
        #expect(allocation.estimatedPeakBytes == 48_384_000)
        #expect(allocation.pixelSize == CGSize(width: 2_400, height: 1_260))
    }

    @Test("Fractional scaled dimensions round up")
    func fractionalDimensionsRoundUp() throws {
        let allocation = try RenderBudget.preview.allocation(
            for: CGSize(width: 100.1, height: 50.1), scale: 1.5)

        #expect(allocation.pixelWidth == 151)
        #expect(allocation.pixelHeight == 76)
        #expect(allocation.pixelCount == 11_476)
    }

    @Test(
        "Invalid dimensions are rejected",
        arguments: [
            CGSize(width: 0, height: 100),
            CGSize(width: -1, height: 100),
            CGSize(width: CGFloat.nan, height: 100),
            CGSize(width: 100, height: CGFloat.infinity),
        ])
    func invalidDimensions(size: CGSize) {
        #expect(throws: RenderBudgetError.tooLarge(.invalidDimensions)) {
            try RenderBudget.export.allocation(for: size, scale: 1)
        }
    }

    @Test(
        "Invalid scales are rejected",
        arguments: [CGFloat(0), CGFloat(-1), CGFloat.nan, CGFloat.infinity])
    func invalidScale(scale: CGFloat) {
        #expect(throws: RenderBudgetError.tooLarge(.invalidScale)) {
            try RenderBudget.export.allocation(
                for: CGSize(width: 100, height: 100), scale: scale)
        }
    }

    @Test("Either scaled axis must fit the dimension ceiling")
    func dimensionCeiling() {
        #expect(
            throws: RenderBudgetError.tooLarge(
                .dimension(actual: 16_385, maximum: 16_384))
        ) {
            try RenderBudget.export.allocation(
                for: CGSize(width: 16_385, height: 1), scale: 1)
        }
    }

    @Test("Total pixels are checked with overflow-safe multiplication")
    func pixelCountCeiling() {
        #expect(
            throws: RenderBudgetError.tooLarge(
                .pixelCount(actual: 40_008_000, maximum: 40_000_000))
        ) {
            try RenderBudget.export.allocation(
                for: CGSize(width: 8_000, height: 5_001), scale: 1)
        }
    }

    @Test("Peak concurrent buffers have an independent byte ceiling")
    func estimatedByteCeiling() {
        #expect(
            throws: RenderBudgetError.tooLarge(
                .estimatedBytes(actual: 576_000_000, maximum: 536_870_912))
        ) {
            try RenderBudget.export.allocation(
                for: CGSize(width: 6_000, height: 6_000), scale: 1)
        }
    }

    @Test("Overflowing scaled dimensions fail without trapping")
    func scaledDimensionOverflow() {
        #expect(throws: RenderBudgetError.tooLarge(.arithmeticOverflow)) {
            try RenderBudget.export.allocation(
                for: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 1), scale: 3)
        }
    }

    @Test("Every built-in destination preset fits the export budget")
    func builtInPresetsFit() throws {
        for preset in ExportPreset.all {
            guard let size = preset.sizing.fixedSize else { continue }
            _ = try RenderBudget.export.allocation(
                for: size, scale: CGFloat(preset.scale))
        }
    }
}
