import AppKit
import ImageIO
import VitrineDomain

/// The process-wide cache of decoded images, and the ImageIO decode path that fills it.
///
/// Split from `BackgroundImageStore` because the two answer different questions. The store
/// answers "where do these bytes live" — copying a user-selected file into a
/// content-addressed directory and resolving a reference back to a URL. This answers "what
/// does that file look like in memory, and how much of that may we keep" — bounded
/// decoding, a byte-costed LRU, and the deterministic bitmap the renderer draws from.
///
/// The cache is keyed by resolved absolute path. Filenames are content-addressed (SHA-256
/// of the bytes), so a path is immutable and one cache safely serves every store instance
/// and both the background and foreground directories.
nonisolated public enum DecodedImageCache {
    /// Process-wide cache of decoded images, keyed by the resolved absolute path.
    /// Filenames are content-addressed (SHA-256 of the bytes), so a given path is
    /// immutable — the cached image can never go stale — and one cache safely serves
    /// every store instance and both the background and foreground directories. This
    /// is what keeps a photo background/foreground from being re-read and re-decoded
    /// on every SwiftUI `body` pass (a keystroke or a slider tick re-runs the canvas
    /// body); it mirrors the decoded-thumbnail cache `RecentsStore` already has.
    /// Touched only from the main actor, like every `image(for:)`
    /// caller (the canvas/editor views).
    /// The cache's memory ceiling, in bytes of decoded bitmap.
    ///
    /// A count limit alone does not bound memory: imports accept files up to
    /// `BackgroundImageStore.maxImportBytes`; even after the ImageIO downsample, one image can occupy up to
    /// the 64-MiB interactive surface budget, so a count limit alone could still pin excessive
    /// memory before an export allocates its own canvas buffers. The cost limit turns the cache
    /// into a memory-bounded LRU: browsing a folder of large photos evicts the oldest
    /// instead of growing without limit, while the common case (a handful of ordinary
    /// backgrounds) never evicts at all.
    private static let cacheCostLimit = 256 * 1024 * 1024

    @MainActor private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        cache.totalCostLimit = cacheCostLimit
        return cache
    }()

    /// The decoded byte cost of an in-memory `image`, used as a safe fallback when
    /// source metadata is unavailable.
    ///
    /// Measured from the largest bitmap representation rather than `size` (which is in
    /// points, so a 2× asset would be under-counted fourfold) and assumes 4 bytes per
    /// pixel — the RGBA form the renderer draws from. A vector-only image with no
    /// bitmap representation reports the minimum cost of 1: it is cheap to hold, and a
    /// zero cost would exempt it from the limit entirely.
    @MainActor static func decodedByteCost(of image: NSImage) -> Int {
        let pixels = image.representations.reduce(0) { largest, representation in
            let (count, overflow) = representation.pixelsWide.multipliedReportingOverflow(
                by: representation.pixelsHigh)
            return overflow ? Int.max : max(largest, count)
        }
        let (cost, overflow) = pixels.multipliedReportingOverflow(by: 4)
        return overflow ? Int.max : max(1, cost)
    }

    /// Returns the decoded image for an already-resolved store URL, decoding and caching
    /// it on a miss. The caller resolves the reference to a URL first, which is what keeps
    /// the directory-escape check in the store that owns the directory.
    @MainActor public static func image(at url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let decoded = decodeStaticImage(at: url) else { return nil }
        return cache(decoded, forKey: key)
    }

    /// Cache-or-decode without blocking the main actor, so a freshly imported image is a
    /// cache hit by the time a SwiftUI body first asks for it.
    @MainActor public static func preloadImage(at url: URL) async -> NSImage? {
        let key = url.path as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let decoded = await decodeStaticImageConcurrently(at: url) else { return nil }
        guard !Task.isCancelled else { return nil }
        return cache(decoded, forKey: key)
    }

    /// Produces the same bounded static representation for validated in-memory callers such as
    /// the CLI watermark option. The metadata pass is intentionally repeated as defense in depth:
    /// this API must stay safe if a future caller skips `readValidatedImageData(from:)`.
    @MainActor public static func staticImage(from data: Data) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard data.count <= BackgroundImageStore.maxImportBytes,
            let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
            let decoded = decodeStaticImage(in: source)
        else { return nil }
        return makeNSImage(from: decoded.cgImage)
    }

    private struct DecodedStaticImage: Sendable {
        let cgImage: CGImage
        let cost: Int
    }

    @concurrent
    private static func decodeStaticImageConcurrently(
        at url: URL
    ) async -> DecodedStaticImage? {
        guard !Task.isCancelled else { return nil }
        return decodeStaticImage(at: url)
    }

    /// Resolves legacy/current stored bytes through ImageIO, validates metadata again, and creates
    /// one transformed/downsampled first frame. `NSImage(contentsOf:)` is deliberately avoided: it
    /// can retain full-resolution or animated representations that bypass the renderer's budget.
    private static func decodeStaticImage(at url: URL) -> DecodedStaticImage? {
        guard let data = try? BackgroundImageStore.readBoundedImageData(from: url) else {
            return nil
        }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        return decodeStaticImage(in: source)
    }

    private static func decodeStaticImage(in source: CGImageSource) -> DecodedStaticImage? {
        guard let metadata = try? BackgroundImageStore.validatedImageMetadata(in: source),
            let cgImage = try? ImageDecodePolicy.decodeStaticFirstFrame(
                in: source, metadata: metadata)
        else { return nil }
        let cost = decodedSurfaceCost(
            bytesPerRow: cgImage.bytesPerRow, height: cgImage.height)
        return DecodedStaticImage(cgImage: cgImage, cost: cost)
    }

    /// The cache cost of a decoded surface: its actual backing bytes
    /// (`bytesPerRow × height`), never an assumed 4 bytes per pixel — a
    /// 16-bit-per-channel or row-padded surface would otherwise be under-counted
    /// and the cache's byte bound would retain substantially more decoded memory
    /// than it reports. Floors at 1 so no surface is exempt from the count limit.
    public static func decodedSurfaceCost(bytesPerRow: Int, height: Int) -> Int {
        let (cost, overflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        return overflow ? Int.max : max(1, cost)
    }

    @MainActor private static func cache(
        _ decoded: DecodedStaticImage, forKey key: NSString
    ) -> NSImage {
        let image = makeNSImage(from: decoded.cgImage)
        imageCache.setObject(image, forKey: key, cost: decoded.cost)
        return image
    }

    /// Wraps the bounded CGImage as one explicit bitmap representation. Constructing an NSImage
    /// directly from a CGImage can synthesize a backing-scale-dependent representation on a Retina
    /// display; the explicit bitmap keeps the decoded pixel dimensions deterministic.
    @MainActor private static func makeNSImage(from cgImage: CGImage) -> NSImage {
        let image = NSImage(size: NSSize(width: cgImage.width, height: cgImage.height))
        image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        return image
    }
}
