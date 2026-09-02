import CoreGraphics
import Foundation
import ImageIO
import VitrineDomain

/// Metadata and decode policy for user-supplied images.
///
/// Encoded-byte limits alone do not protect the renderer from a small compressed image that
/// expands into a very large bitmap. This policy inspects ImageIO metadata without creating a
/// bitmap, validates the complete container, then decodes exactly one static frame through the
/// thumbnail API. The resulting surface is constrained to the interactive preview budget before
/// an `NSImage` or SwiftUI image is created.
nonisolated public enum ImageDecodePolicy {
    public struct Metadata: Equatable, Sendable {
        public let frameCount: Int
        public let frameDimensions: [(width: Int, height: Int)]
        public let totalSourcePixels: Int

        public var isAnimated: Bool { frameCount > 1 }

        public static func == (lhs: Metadata, rhs: Metadata) -> Bool {
            lhs.frameCount == rhs.frameCount
                && lhs.totalSourcePixels == rhs.totalSourcePixels
                && lhs.frameDimensions.elementsEqual(rhs.frameDimensions) {
                    $0.width == $1.width && $0.height == $1.height
                }
        }
    }

    public struct Budget: Equatable, Sendable {
        public let maximumDimension: Int
        public let maximumPixelCount: Int

        public static let interactive = Budget(
            maximumDimension: RenderBudget.preview.maximumDimension,
            maximumPixelCount: min(
                RenderBudget.preview.maximumPixelCount,
                RenderBudget.preview.maximumEstimatedBytes
                    / RenderBudget.preview.bytesPerPixel
                    / RenderBudget.preview.concurrentBufferCount))

        public func allows(width: Int, height: Int) -> Bool {
            guard width > 0, height > 0,
                width <= maximumDimension, height <= maximumDimension
            else { return false }
            let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
            return !overflow && pixels <= maximumPixelCount
        }
    }

    public enum Failure: Error, Equatable {
        case invalidImage
        case tooLarge
    }

    /// Reads dimensions and frame status without asking ImageIO to create any decoded surface.
    /// A complete status check rejects truncated containers that expose plausible header metadata.
    public static func metadata(
        in source: CGImageSource,
        maximumFrameCount: Int,
        maximumSourcePixelCount: Int
    ) throws(Failure) -> Metadata {
        guard CGImageSourceGetStatus(source) == .statusComplete else {
            throw .invalidImage
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw .invalidImage }
        guard frameCount <= maximumFrameCount else { throw .tooLarge }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        var dimensions: [(width: Int, height: Int)] = []
        dimensions.reserveCapacity(frameCount)
        var totalPixels = 0

        for index in 0..<frameCount {
            guard CGImageSourceGetStatusAtIndex(source, index) == .statusComplete,
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, options)
                    as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int,
                width > 0, height > 0
            else {
                throw .invalidImage
            }
            let (framePixels, frameOverflow) = width.multipliedReportingOverflow(by: height)
            guard !frameOverflow else { throw .tooLarge }
            let (nextTotal, totalOverflow) = totalPixels.addingReportingOverflow(framePixels)
            guard !totalOverflow, nextTotal <= maximumSourcePixelCount else {
                throw .tooLarge
            }
            totalPixels = nextTotal
            dimensions.append((width: width, height: height))
        }

        return Metadata(
            frameCount: frameCount,
            frameDimensions: dimensions,
            totalSourcePixels: totalPixels)
    }

    /// The ImageIO maximum-dimension hint that preserves aspect ratio while ensuring both the
    /// dimension and pixel-area limits. The short axis is projected with conservative upward
    /// rounding, and the completed decode is checked again before use.
    public static func thumbnailMaximumPixelSize(
        for width: Int,
        height: Int,
        budget: Budget = .interactive
    ) throws(Failure) -> Int {
        guard width > 0, height > 0,
            budget.maximumDimension > 0, budget.maximumPixelCount > 0
        else { throw .invalidImage }
        let (sourcePixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else { throw .tooLarge }

        let longest = max(width, height)
        guard !budget.allows(width: width, height: height) else { return longest }

        let dimensionScale = min(
            Double(budget.maximumDimension) / Double(width),
            Double(budget.maximumDimension) / Double(height))
        let areaScale = sqrt(Double(budget.maximumPixelCount) / Double(sourcePixels))
        let scale = min(1, min(dimensionScale, areaScale))
        guard scale.isFinite, scale > 0 else { throw .tooLarge }

        var maximum = max(1, Int((Double(longest) * scale).rounded(.down)))
        while maximum > 1 {
            let projectedWidth = min(
                width, Int((Double(width) / Double(longest) * Double(maximum)).rounded(.up)))
            let projectedHeight = min(
                height, Int((Double(height) / Double(longest) * Double(maximum)).rounded(.up)))
            if budget.allows(width: projectedWidth, height: projectedHeight) {
                return maximum
            }
            maximum -= 1
        }
        return maximum
    }

    /// Decodes the first frame only, applying EXIF orientation and downsampling before allocating
    /// the bitmap. Animated inputs therefore have an explicit static-image contract instead of
    /// allowing AppKit to retain or advance an arbitrary frame sequence.
    public static func decodeStaticFirstFrame(
        in source: CGImageSource,
        metadata: Metadata,
        budget: Budget = .interactive
    ) throws(Failure) -> CGImage {
        guard let first = metadata.frameDimensions.first else { throw .invalidImage }
        let maximum = try thumbnailMaximumPixelSize(
            for: first.width, height: first.height, budget: budget)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximum,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            budget.allows(width: image.width, height: image.height)
        else {
            throw .invalidImage
        }
        return image
    }
}
