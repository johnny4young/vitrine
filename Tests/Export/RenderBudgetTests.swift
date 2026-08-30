import CoreGraphics
import SwiftUI
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

    @Test("Full-page height clamps to the shared area and buffer ceiling")
    func fullPageHeightClamp() throws {
        let width: CGFloat = 1_200
        let scale: CGFloat = 2
        let height = try RenderBudget.export.clampedLogicalHeight(
            20_000, forLogicalWidth: width, scale: scale)
        let allocation = try RenderBudget.export.allocation(
            for: CGSize(width: width, height: height), scale: scale)

        #expect(height < 20_000)
        #expect(allocation.pixelCount <= RenderBudget.export.maximumPixelCount)
        #expect(allocation.estimatedPeakBytes <= RenderBudget.export.maximumEstimatedBytes)
        #expect(throws: RenderBudgetError.self) {
            try RenderBudget.export.allocation(
                for: CGSize(width: width, height: height + (1 / scale)),
                scale: scale)
        }
    }

    @Test(
        "Full-page height remains bounded at every supported scale",
        arguments: [CGFloat(1), CGFloat(2), CGFloat(3)])
    func fullPageHeightClampAtSupportedScales(scale: CGFloat) throws {
        let height = try RenderBudget.export.clampedLogicalHeight(
            CGFloat.greatestFiniteMagnitude,
            forLogicalWidth: 5_000,
            scale: scale)
        let allocation = try RenderBudget.export.allocation(
            for: CGSize(width: 5_000, height: height), scale: scale)

        #expect(height.isFinite)
        #expect(allocation.pixelWidth == Int(5_000 * scale))
        #expect(allocation.estimatedPeakBytes <= RenderBudget.export.maximumEstimatedBytes)
    }

    @Test("Full-page clamp remains inside a rounded fractional-scale boundary")
    func fullPageHeightClampAtFractionalScale() throws {
        let scale: CGFloat = 1.1
        let height = try RenderBudget.export.clampedLogicalHeight(
            20_000,
            forLogicalWidth: 3_333.3,
            scale: scale)
        let allocation = try RenderBudget.export.allocation(
            for: CGSize(width: 3_333.3, height: height), scale: scale)

        #expect(allocation.pixelCount <= RenderBudget.export.maximumPixelCount)
        #expect(allocation.estimatedPeakBytes <= RenderBudget.export.maximumEstimatedBytes)
    }

    @Test("Full-page clamp rejects invalid scales without trapping")
    func fullPageHeightClampRejectsInvalidScale() {
        for scale in [CGFloat.zero, .infinity, .nan] {
            #expect(throws: RenderBudgetError.tooLarge(.invalidScale)) {
                try RenderBudget.export.clampedLogicalHeight(
                    10_000, forLogicalWidth: 1_200, scale: scale)
            }
        }
    }

    @Test("Full-page clamp rejects invalid widths without trapping")
    func fullPageHeightClampRejectsInvalidWidth() {
        for width in [CGFloat.zero, -1, .infinity, .nan] {
            #expect(throws: RenderBudgetError.tooLarge(.invalidDimensions)) {
                try RenderBudget.export.clampedLogicalHeight(
                    10_000, forLogicalWidth: width, scale: 2)
            }
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

    @Test("Checked snapshot rendering validates layout before bitmap allocation")
    func checkedSnapshotRejectsOversizedLayout() {
        let config = ExportTestFixtures.sampleConfig()
        #expect(
            throws: RenderBudgetError.tooLarge(
                .dimension(actual: 16_385, maximum: 16_384))
        ) {
            try ExportManager.renderCGImageChecked(
                config, scale: 1, fixedSize: CGSize(width: 16_385, height: 1))
        }
    }

    @Test("Checked snapshot rendering preserves exact fixed pixel dimensions")
    func checkedSnapshotPreservesFixedPixels() throws {
        let image = try ExportManager.renderCGImageChecked(
            ExportTestFixtures.sampleConfig(), scale: 2,
            fixedSize: CGSize(width: 320, height: 180))

        #expect(image.width == 640)
        #expect(image.height == 360)
    }

    @Test("Preview rendering applies the stricter preview policy before allocation")
    func checkedPreviewRejectsAnExportSizedCanvas() throws {
        let size = CGSize(width: 5_000, height: 4_000)
        _ = try RenderBudget.export.allocation(for: size, scale: 1)
        #expect(
            throws: RenderBudgetError.tooLarge(
                .pixelCount(actual: 20_000_000, maximum: 16_000_000))
        ) {
            try ExportManager.renderCGImageChecked(
                Color.clear.frame(width: size.width, height: size.height),
                proposedSize: size,
                scale: 1,
                profile: .sRGB,
                budget: .preview)
        }
    }

    @Test("Checked payloads preserve render and encoding failure categories")
    func checkedPayloadFailureCategories() {
        #expect(throws: RenderBudgetError.tooLarge(.invalidDimensions)) {
            try ExportManager.encodedPayloadChecked(
                .png,
                raster: { () throws(RenderBudgetError) -> CGImage in
                    throw .tooLarge(.invalidDimensions)
                },
                pdf: { nil })
        }
        #expect(throws: RenderBudgetError.encodingFailed) {
            try ExportManager.encodedPayloadChecked(
                .pdf,
                raster: { () throws(RenderBudgetError) -> CGImage in
                    throw .allocationFailed
                },
                pdf: { nil })
        }
    }

    @Test("CLI maps renderer failures to actionable stable errors")
    func cliErrorMapping() {
        #expect(CLIError.renderFailure(.tooLarge(.arithmeticOverflow)) == .renderTooLarge)
        #expect(CLIError.renderFailure(.allocationFailed) == .renderAllocationFailed)
        #expect(CLIError.renderFailure(.encodingFailed) == .renderEncodingFailed)
        #expect(CLIError.renderFailure(.cancelled) == .renderCancelled)
        #expect(CLIError.renderTooLarge.exitCode != 0)
        #expect(CLIError.renderTooLarge.message.contains("Reduce"))
    }
}
