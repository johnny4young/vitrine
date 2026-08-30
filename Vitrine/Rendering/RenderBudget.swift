import CoreGraphics

/// A pre-allocation safety policy for raster rendering.
///
/// File-size limits do not bound the size of a laid-out canvas: a small text file can
/// still produce a very tall image, and scale multiplies both axes. Callers evaluate the
/// resolved logical size before asking SwiftUI, WebKit, or Core Graphics for a bitmap.
/// The peak estimate deliberately includes concurrent full-size buffers rather than
/// treating the final RGBA image as the whole allocation cost.
nonisolated struct RenderBudget: Equatable, Sendable {
    nonisolated struct Allocation: Equatable, Sendable {
        let pixelWidth: Int
        let pixelHeight: Int
        let pixelCount: Int
        let estimatedPeakBytes: Int

        var pixelSize: CGSize {
            CGSize(width: pixelWidth, height: pixelHeight)
        }
    }

    nonisolated enum Rejection: Equatable, Sendable {
        case invalidDimensions
        case invalidScale
        case dimension(actual: Int, maximum: Int)
        case pixelCount(actual: Int, maximum: Int)
        case estimatedBytes(actual: Int, maximum: Int)
        case arithmeticOverflow
    }

    /// Preview keeps interactive edits responsive even on an 8 GB Mac. Three buffers
    /// cover the rendered image plus the common display/conversion copies.
    static let preview = RenderBudget(
        maximumDimension: 8_192,
        maximumPixelCount: 16_000_000,
        maximumEstimatedBytes: 256 * 1_024 * 1_024,
        bytesPerPixel: 4,
        concurrentBufferCount: 3)

    /// Export allows substantially larger artifacts while bounding the worst common
    /// path: ImageRenderer output, color normalization, opaque compositing, and encoder
    /// input. The byte ceiling becomes stricter than the pixel ceiling when all four
    /// buffers are required.
    static let export = RenderBudget(
        maximumDimension: 16_384,
        maximumPixelCount: 40_000_000,
        maximumEstimatedBytes: 512 * 1_024 * 1_024,
        bytesPerPixel: 4,
        concurrentBufferCount: 4)

    let maximumDimension: Int
    let maximumPixelCount: Int
    let maximumEstimatedBytes: Int
    let bytesPerPixel: Int
    let concurrentBufferCount: Int

    private init(
        maximumDimension: Int,
        maximumPixelCount: Int,
        maximumEstimatedBytes: Int,
        bytesPerPixel: Int,
        concurrentBufferCount: Int
    ) {
        self.maximumDimension = maximumDimension
        self.maximumPixelCount = maximumPixelCount
        self.maximumEstimatedBytes = maximumEstimatedBytes
        self.bytesPerPixel = bytesPerPixel
        self.concurrentBufferCount = concurrentBufferCount
    }

    /// Resolves a logical canvas into its bounded raster allocation. Dimensions round
    /// up so the budget never underestimates a fractional point after scaling.
    func allocation(
        for logicalSize: CGSize, scale: CGFloat
    ) throws(RenderBudgetError)
        -> Allocation
    {
        guard logicalSize.width.isFinite, logicalSize.height.isFinite,
            logicalSize.width > 0, logicalSize.height > 0
        else {
            throw .tooLarge(.invalidDimensions)
        }
        guard scale.isFinite, scale > 0 else {
            throw .tooLarge(.invalidScale)
        }

        let pixelWidth = try pixelDimension(for: logicalSize.width, scale: scale)
        let pixelHeight = try pixelDimension(for: logicalSize.height, scale: scale)
        let (pixelCount, pixelOverflow) = pixelWidth.multipliedReportingOverflow(by: pixelHeight)
        guard !pixelOverflow else { throw .tooLarge(.arithmeticOverflow) }
        guard pixelCount <= maximumPixelCount else {
            throw .tooLarge(.pixelCount(actual: pixelCount, maximum: maximumPixelCount))
        }

        let (bytesPerBuffer, byteOverflow) = pixelCount.multipliedReportingOverflow(
            by: bytesPerPixel)
        guard !byteOverflow else { throw .tooLarge(.arithmeticOverflow) }
        let (estimatedPeakBytes, peakOverflow) = bytesPerBuffer.multipliedReportingOverflow(
            by: concurrentBufferCount)
        guard !peakOverflow else { throw .tooLarge(.arithmeticOverflow) }
        guard estimatedPeakBytes <= maximumEstimatedBytes else {
            throw .tooLarge(
                .estimatedBytes(
                    actual: estimatedPeakBytes, maximum: maximumEstimatedBytes))
        }

        return Allocation(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            pixelCount: pixelCount,
            estimatedPeakBytes: estimatedPeakBytes)
    }

    private func pixelDimension(
        for logicalDimension: CGFloat, scale: CGFloat
    ) throws(RenderBudgetError) -> Int {
        let scaled = logicalDimension * scale
        guard scaled.isFinite, scaled > 0 else {
            throw .tooLarge(.arithmeticOverflow)
        }
        guard scaled <= CGFloat(maximumDimension) else {
            let actual =
                if scaled < CGFloat(Int.max) {
                    Int(scaled.rounded(.up))
                } else {
                    Int.max
                }
            throw .tooLarge(.dimension(actual: actual, maximum: maximumDimension))
        }
        return Int(scaled.rounded(.up))
    }
}

/// Typed failures shared by raster rendering surfaces. The budget currently produces
/// only `tooLarge`; the remaining cases let the next pipeline layer preserve allocation,
/// encoding, and cancellation failures instead of collapsing them into `nil`.
nonisolated enum RenderBudgetError: Error, Equatable, Sendable {
    case tooLarge(RenderBudget.Rejection)
    case allocationFailed
    case encodingFailed
    case cancelled
}
