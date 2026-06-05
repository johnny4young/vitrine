import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The pixel-diff engine behind the golden-image suite (CS-025).
///
/// Both the in-process comparison suite (`GoldenImageTests`) and the standalone
/// CLI comparator (`scripts/compare-goldens.swift`) compare two PNGs the same way,
/// so the rule is defined once here and the standalone script mirrors it byte for
/// byte. `GoldenComparatorContractTests` pins the documented tolerance constants so
/// the two copies cannot silently drift.
///
/// ## Why a tolerance, not exact byte equality
///
/// Text rasterization is not bit-identical across runs and machines: sub-pixel
/// anti-aliasing along glyph edges can move a channel by a value or two even when
/// the image is visually identical. Asserting exact byte equality would make the
/// suite flap on noise. Instead the comparison allows a **small per-channel
/// threshold** (`channelTolerance`) to absorb that anti-aliasing, and tolerates a
/// **tiny fraction of pixels** (`pixelFractionTolerance`) exceeding it, so a few
/// stray edge pixels never fail a run while a real visual change — a wrong color,
/// a shifted layout, a missing element — moves far more than that and fails.
enum GoldenComparator {
    /// Maximum allowed absolute difference per 8-bit channel (0...255) before a
    /// pixel counts as "changed". Two units absorbs sub-pixel anti-aliasing along
    /// glyph edges without hiding a real color or layout change, which moves whole
    /// regions far past this.
    static let channelTolerance: UInt8 = 2

    /// Maximum allowed fraction of pixels (0...1) that may exceed
    /// `channelTolerance` before the images are considered different. A real
    /// regression changes a large, contiguous region — far more than this floor —
    /// while a handful of stray anti-aliased edge pixels stays under it.
    static let pixelFractionTolerance: Double = 0.001

    /// The outcome of comparing two images: whether they matched under tolerance,
    /// plus the measured statistics for logging and artifact triage.
    struct Result: Equatable {
        /// Whether the images are considered equal under the documented tolerance.
        var matches: Bool
        /// Total pixels compared (the shared `width × height`).
        var pixelCount: Int
        /// How many pixels exceeded `channelTolerance` on any channel.
        var differingPixels: Int
        /// The largest single-channel absolute difference seen anywhere.
        var maxChannelDelta: Int
        /// The fraction of pixels that differed (`differingPixels / pixelCount`).
        var differingFraction: Double {
            pixelCount == 0 ? 0 : Double(differingPixels) / Double(pixelCount)
        }
    }

    /// Why a comparison could not even be attempted (as opposed to a pixel
    /// mismatch, which is a `Result` with `matches == false`).
    enum Failure: Error, Equatable {
        /// A file could not be decoded into a `CGImage`.
        case unreadable(path: String)
        /// The two images have different pixel dimensions, so no per-pixel
        /// comparison is meaningful — a dimension change is itself a regression.
        case sizeMismatch(CGSize, CGSize)
    }

    /// Compares two already-decoded images under the documented tolerance.
    ///
    /// Both images are redrawn into a canonical straight-alpha RGBA8 buffer first,
    /// so the comparison is independent of each source's bytes-per-row padding,
    /// alpha layout, or color space — only the visible pixels are compared.
    /// Differing dimensions are a hard `sizeMismatch` failure rather than a soft
    /// mismatch, because an export changing size is unambiguously a regression.
    static func compare(_ lhs: CGImage, _ rhs: CGImage) -> Swift.Result<Result, Failure> {
        let lhsSize = CGSize(width: lhs.width, height: lhs.height)
        let rhsSize = CGSize(width: rhs.width, height: rhs.height)
        guard lhs.width == rhs.width, lhs.height == rhs.height else {
            return .failure(.sizeMismatch(lhsSize, rhsSize))
        }
        guard
            let lhsBytes = rgba8Bytes(lhs),
            let rhsBytes = rgba8Bytes(rhs)
        else {
            return .failure(.unreadable(path: "<in-memory>"))
        }

        let pixelCount = lhs.width * lhs.height
        var differingPixels = 0
        var maxChannelDelta = 0
        let tolerance = Int(channelTolerance)
        // Walk the two buffers a pixel (4 bytes) at a time; a pixel "differs" when
        // any one of its channels moves past the tolerance.
        var index = 0
        let byteCount = pixelCount * 4
        while index < byteCount {
            var pixelDiffers = false
            for channel in 0..<4 {
                let delta = abs(Int(lhsBytes[index + channel]) - Int(rhsBytes[index + channel]))
                if delta > maxChannelDelta { maxChannelDelta = delta }
                if delta > tolerance { pixelDiffers = true }
            }
            if pixelDiffers { differingPixels += 1 }
            index += 4
        }

        let fraction = pixelCount == 0 ? 0 : Double(differingPixels) / Double(pixelCount)
        let matches = fraction <= pixelFractionTolerance
        return .success(
            Result(
                matches: matches,
                pixelCount: pixelCount,
                differingPixels: differingPixels,
                maxChannelDelta: maxChannelDelta))
    }

    /// Decodes a PNG (or any ImageIO-readable image) at `url` into a `CGImage`,
    /// returning `nil` for a missing/unreadable file or an undecodable image.
    static func loadImage(at url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Compares two image files by path under the documented tolerance, returning a
    /// hard `Failure` if either file cannot be read or the dimensions differ.
    static func compareFiles(_ lhsURL: URL, _ rhsURL: URL) -> Swift.Result<Result, Failure> {
        guard let lhs = loadImage(at: lhsURL) else {
            return .failure(.unreadable(path: lhsURL.path))
        }
        guard let rhs = loadImage(at: rhsURL) else {
            return .failure(.unreadable(path: rhsURL.path))
        }
        return compare(lhs, rhs)
    }

    /// Redraws `image` into a tightly packed, straight-alpha RGBA8 buffer so two
    /// images can be compared channel-for-channel regardless of their original
    /// byte layout or color space. Returns `nil` only if the (system-constant)
    /// sRGB context cannot be created.
    static func rgba8Bytes(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let success = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return success ? buffer : nil
    }
}
