import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import VitrineDomain

/// Stores and resolves image-background files inside the app container.
///
/// Vitrine never uploads a background and never asks for a broad file
/// entitlement. The user picks an image through an `NSOpenPanel` (covered by the
/// existing `com.apple.security.files.user-selected.read-write` entitlement); the
/// store reads it under a security-scoped resource access and copies the bytes
/// into a private directory under Application Support. Persistence then stores
/// only the in-container file name (`ImageReference`), so a saved background:
///
/// - resolves back to a readable file on relaunch without re-prompting, and
/// - degrades gracefully when the copied file is missing/relocated — `url(for:)`
///   returns `nil` and callers fall back to a safe default background.
///
/// The base directory is injectable so the import/resolve/missing-file behavior
/// is unit-testable without touching the real container.
nonisolated public struct BackgroundImageStore: Sendable {
    public init(directory: URL) {
        self.directory = directory
    }

    /// Errors surfaced while importing an image.
    nonisolated public enum ImportError: Error, Equatable {
        /// The chosen source was not a supported image with valid dimensions.
        case notAnImage
        /// The bytes could not be read or written into the container.
        case copyFailed
        /// A remote image could not be downloaded — an unsupported URL scheme, a
        /// network failure, or a non-success HTTP status.
        case downloadFailed
        /// An import exceeded the encoded-byte, frame-count, or decoded-pixel budget.
        case tooLarge

        /// A short, localized explanation suitable for picker and drop feedback.
        public var message: String {
            switch self {
            case .notAnImage:
                String(localized: "That source didn't contain a supported image.")
            case .copyFailed:
                String(localized: "Vitrine couldn't read or save that image.")
            case .downloadFailed:
                String(localized: "Vitrine couldn't download an image from that URL.")
            case .tooLarge:
                String(
                    localized:
                        "That image is too large. Choose one up to 25 MB and 64 total megapixels."
                )
            }
        }
    }

    /// The largest encoded image accepted from any source. 25 MB comfortably covers
    /// a high-resolution photo while bounding read, hash, and disk allocations.
    nonisolated public static let maxImportBytes = 25 * 1024 * 1024

    /// The remote loader shares the universal import limit. Keep this name as the
    /// streaming API's explicit contract and for source compatibility with callers.
    nonisolated public static let maxRemoteImageBytes = maxImportBytes

    /// The cumulative source-pixel ceiling across every frame. This protects metadata
    /// inspection from decompression bombs; the actual static first-frame decode is
    /// independently downsampled to `RenderBudget.preview` by `ImageDecodePolicy`.
    nonisolated public static let maxDecodedPixelCount = 64_000_000

    /// A separate metadata/frame ceiling prevents a tiny-frame animation from carrying
    /// an effectively unbounded frame table while still allowing normal animated images.
    nonisolated public static let maxImageFrameCount = 256

    /// Bounded local reads grow in modest increments and stop one byte past the limit,
    /// rather than allocating an entire file that changed after its metadata check.
    nonisolated private static let localImageReadChunkBytes = 256 * 1024

    /// Keep the direct remote fetch from lingering forever on a slow or stalled
    /// host. The cap still comes from `maxRemoteImageBytes`; this only bounds the
    /// request's wall-clock time.
    nonisolated private static let remoteImageRequestTimeout: TimeInterval = 20

    /// The directory holding copied background images. Created on demand.
    public let directory: URL

    /// The store rooted at the app's Application Support container — the path used
    /// in the running app. Falls back to a temporary directory if Application
    /// Support is somehow unavailable, so the store is always usable.
    public static var container: BackgroundImageStore {
        appContainer(subdirectory: "Backgrounds")
    }

    /// The store for **foreground** images — the "beautify any image" content. Same
    /// content-addressed import/resolve machinery as backgrounds, rooted at a separate
    /// directory so foreground captures and background photos never collide.
    public static var foregroundContainer: BackgroundImageStore {
        appContainer(subdirectory: "Foregrounds")
    }

    /// A store rooted at `Application Support/<subdirectory>`, falling back to a temporary
    /// directory if Application Support is unavailable so the store is always usable.
    private static func appContainer(subdirectory: String) -> BackgroundImageStore {
        let base =
            debugIsolatedContainerRoot()
            ?? (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return BackgroundImageStore(
            directory: base.appendingPathComponent(subdirectory, isDirectory: true))
    }

    /// A per-launch temporary root for the opt-in dynamic image-memory journey.
    ///
    /// The override exists only in Debug and requires the same isolated-defaults marker
    /// used by UI/memory automation. A normal app launch — including every Release build
    /// — therefore continues to use Application Support. Hashing the suite produces a
    /// plain path component without trusting environment text as a filesystem path.
    public static func debugIsolatedContainerRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> URL? {
        #if DEBUG
            guard environment["VITRINE_MEMORY_IMAGE_STORE_ISOLATED"] == "1",
                let suite = environment["VITRINE_USER_DEFAULTS_SUITE"], !suite.isEmpty
            else { return nil }
            let digest = SHA256.hash(data: Data(suite.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            return temporaryDirectory.appendingPathComponent(
                "vitrine-memory-images-\(digest)", isDirectory: true)
        #else
            return nil
        #endif
    }

    /// Copies the user-selected image at `sourceURL` into the container and
    /// returns a stable reference to the copy.
    ///
    /// `sourceURL` is a user-chosen file: access is bracketed by
    /// `startAccessingSecurityScopedResource()` so the read works under the
    /// sandbox without a broad entitlement. The bytes and decoded dimensions are
    /// bounded before being written, and the destination name is content-addressed
    /// (a hash of the bytes) so re-importing the same image reuses one file
    /// instead of accumulating duplicates.
    public func importImage(from sourceURL: URL) throws -> ImageReference {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let data = try Self.readBoundedImageData(from: sourceURL)
        return try store(data, preferredExtension: sanitizedExtension(for: sourceURL))
    }

    /// Imports already-in-memory image `data` — a clipboard paste or an in-app drag that
    /// carries the image directly rather than as a file. Validates the encoded bytes and
    /// decoded dimensions, then writes them through the same content-addressed store as the
    /// file path, so identical bytes from any source dedupe to one file.
    public func importImage(
        data: Data, preferredExtension ext: String = ""
    ) throws -> ImageReference {
        try store(data, preferredExtension: sanitizedExtension(ext))
    }

    /// Performs bounded local read, metadata validation, hashing, and atomic persistence on the
    /// concurrent executor. UI import surfaces use this path so large encoded files never block
    /// the main actor; synchronous CLI and test callers retain the direct API above.
    @concurrent
    public func importImageConcurrently(from sourceURL: URL) async throws -> ImageReference {
        try Task.checkCancellation()
        let reference = try importImage(from: sourceURL)
        try Task.checkCancellation()
        return reference
    }

    /// Concurrent sibling for clipboard and drag providers that already delivered the bytes.
    @concurrent
    public func importImageConcurrently(
        data: Data, preferredExtension ext: String = ""
    ) async throws -> ImageReference {
        try Task.checkCancellation()
        let reference = try importImage(data: data, preferredExtension: ext)
        try Task.checkCancellation()
        return reference
    }

    /// Downloads the image at a remote `url` and imports it into the container,
    /// returning a stable reference to the copy (image-input polish).
    ///
    /// This is the network sibling of `importImage(from:)`: the user types an image
    /// URL into the background editor and Vitrine fetches it **directly from that
    /// host** — nothing is uploaded and nothing routes through a Vitrine service.
    /// The fetch is only ever reachable from a build that carries
    /// `com.apple.security.network.client`; without it the App Sandbox blocks the
    /// connection outright, so the entitlement is the real boundary (the editor also
    /// hides the field). The `load` closure is injectable so the fetch → validate →
    /// store path is unit-testable without a live network.
    ///
    /// The bytes and decoded dimensions are validated and capped before being written
    /// through the same content-addressed
    /// store as a user-picked file, so an identical remote and local image dedupe to
    /// one file.
    public func importImage(
        downloadedFrom url: URL,
        using load: (URL) async throws -> (Data, URLResponse) = { url in
            try await BackgroundImageStore.loadBoundedRemoteImage(from: url)
        }
    ) async throws -> ImageReference {
        guard Self.isAllowedRemoteImageDownloadURL(url) else {
            throw ImportError.downloadFailed
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await load(url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let importError as ImportError {
            try Task.checkCancellation()
            throw importError
        } catch {
            try Task.checkCancellation()
            throw ImportError.downloadFailed
        }

        // The production loader blocks private-host redirects before following them. Keep
        // this response check as a defense-in-depth guard for injected loaders and any future
        // URLSession path.
        if !Self.isAllowedRemoteImageDownloadURL(response.url ?? url) {
            throw ImportError.downloadFailed
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ImportError.downloadFailed
        }
        return try await persistImageConcurrently(
            data,
            preferredExtension: sanitizedExtension(for: url, mimeType: response.mimeType))
    }

    /// Moves post-download validation, hashing, and disk persistence off the caller's actor.
    @concurrent
    private func persistImageConcurrently(
        _ data: Data, preferredExtension ext: String
    ) async throws -> ImageReference {
        try Task.checkCancellation()
        let reference = try store(data, preferredExtension: ext)
        try Task.checkCancellation()
        return reference
    }

    /// Loads a remote background image without ever accumulating more than
    /// `maxBytes` in memory. This is the default production loader behind
    /// `importImage(downloadedFrom:)`; tests can inject a tiny cap and local URL protocol to
    /// exercise the transport boundary without a live network.
    nonisolated public static func loadBoundedRemoteImage(
        from url: URL,
        maxBytes: Int = maxRemoteImageBytes
    ) async throws -> (Data, URLResponse) {
        try await loadBoundedRemoteImage(
            from: url,
            maxBytes: maxBytes,
            configuration: remoteImageSessionConfiguration())
    }

    /// The lower-level chunk loader accepts a session configuration so focused tests can use a
    /// local `URLProtocol`. Production supplies an ephemeral configuration; the purpose-built
    /// session never shares cookies or cache state and is cancelled after the request completes.
    nonisolated public static func loadBoundedRemoteImage(
        from url: URL,
        maxBytes: Int,
        configuration: URLSessionConfiguration
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = remoteImageRequestTimeout

        let delegate = BoundedRemoteImageSessionDelegate(maxBytes: maxBytes)
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.johnny4young.vitrine.remote-image"
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .utility
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue)
        defer { session.invalidateAndCancel() }
        return try await delegate.load(request, in: session)
    }

    /// Whether a URL is safe to request for a remote background image. This mirrors
    /// URL capture's scheme and private-host policy and is shared by initial validation,
    /// redirect filtering, and response re-checking.
    nonisolated public static func isAllowedRemoteImageDownloadURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host, !host.isEmpty
        else {
            return false
        }
        return !PrivateHostPolicy.isPrivateLocalhost(host: host)
    }

    /// Builds the privacy-preserving production session for direct image downloads:
    /// ephemeral storage avoids sending/reading shared website cookies, and the redirect
    /// delegate refuses private/local targets before `URLSession` follows them.
    nonisolated private static func remoteImageSessionConfiguration()
        -> URLSessionConfiguration
    {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = remoteImageRequestTimeout
        configuration.timeoutIntervalForResource = remoteImageRequestTimeout
        return configuration
    }

    /// Reads a regular local file without ever retaining more than `maxBytes + 1`.
    /// The metadata check rejects known-large inputs before opening them; the bounded
    /// chunk loop remains authoritative if the file grows between that check and read.
    nonisolated public static func readBoundedImageData(
        from url: URL,
        maxBytes: Int = maxImportBytes
    ) throws -> Data {
        let limit = max(0, maxBytes)
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw ImportError.copyFailed
        }

        guard values.isRegularFile == true else { throw ImportError.copyFailed }
        if let fileSize = values.fileSize, fileSize > limit {
            throw ImportError.tooLarge
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ImportError.copyFailed
        }
        defer { try? handle.close() }

        var data = Data()
        data.reserveCapacity(max(0, min(values.fileSize ?? 0, limit)))

        do {
            while true {
                let remaining = limit - data.count
                let nextRead =
                    remaining >= localImageReadChunkBytes
                    ? localImageReadChunkBytes : remaining + 1
                guard let chunk = try handle.read(upToCount: nextRead), !chunk.isEmpty else {
                    break
                }
                data.append(chunk)
                guard data.count <= limit else { throw ImportError.tooLarge }
            }
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.copyFailed
        }
        return data
    }

    /// Reads and validates one local image for callers that need the original bytes
    /// rather than a stored reference (for example a CLI watermark logo).
    nonisolated public static func readValidatedImageData(from url: URL) throws -> Data {
        let data = try readBoundedImageData(from: url)
        try validateImageData(data)
        return data
    }

    /// Recognizes image bytes through ImageIO without decoding their full surfaces,
    /// then applies cumulative geometry limits before AppKit ever creates an image.
    /// `kCGImageSourceShouldCache: false` keeps this metadata pass from eagerly caching
    /// a full-resolution frame.
    nonisolated public static func validateImageData(_ data: Data) throws {
        guard data.count <= maxImportBytes else { throw ImportError.tooLarge }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            throw ImportError.notAnImage
        }

        _ = try validatedImageMetadata(in: source)
    }

    /// Pure geometry validation shared with focused boundary tests. The cumulative
    /// budget matters for animated images: individually small frames can otherwise
    /// expand to an unbounded decoded sequence.
    @discardableResult
    nonisolated public static func validateImageDimensions(
        _ dimensions: [(width: Int, height: Int)]
    ) throws -> Int {
        guard !dimensions.isEmpty else { throw ImportError.notAnImage }
        guard dimensions.count <= maxImageFrameCount else { throw ImportError.tooLarge }

        var totalPixels = 0
        for dimension in dimensions {
            guard dimension.width > 0, dimension.height > 0 else {
                throw ImportError.notAnImage
            }
            let (framePixels, frameOverflow) = dimension.width.multipliedReportingOverflow(
                by: dimension.height)
            guard !frameOverflow else { throw ImportError.tooLarge }
            let (nextTotal, totalOverflow) = totalPixels.addingReportingOverflow(framePixels)
            guard !totalOverflow, nextTotal <= maxDecodedPixelCount else {
                throw ImportError.tooLarge
            }
            totalPixels = nextTotal
        }
        return totalPixels
    }

    /// Extracts and validates complete metadata without decoding any frame. ImageIO's source and
    /// per-frame status checks reject truncated inputs; the first and only bitmap allocation then
    /// happens through the bounded thumbnail path when the image is actually needed.
    nonisolated private static func validatedImageMetadata(
        in source: CGImageSource
    ) throws -> ImageDecodePolicy.Metadata {
        do {
            return try ImageDecodePolicy.metadata(
                in: source,
                maximumFrameCount: maxImageFrameCount,
                maximumSourcePixelCount: maxDecodedPixelCount)
        } catch ImageDecodePolicy.Failure.invalidImage {
            throw ImportError.notAnImage
        } catch ImageDecodePolicy.Failure.tooLarge {
            throw ImportError.tooLarge
        }
    }

    /// Validates and writes image `data` into the container under a content-addressed
    /// name and returns its reference. Shared by the file-picker and URL-download
    /// import paths, so identical bytes always collapse to a single stored file.
    private func store(_ data: Data, preferredExtension ext: String) throws -> ImageReference {
        try Self.validateImageData(data)
        let ext = ext.isEmpty ? inferredExtension(from: data) : ext
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let fileName = ext.isEmpty ? digest : "\(digest).\(ext)"
        let destination = directory.appendingPathComponent(fileName, isDirectory: false)

        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            // Re-importing identical bytes is a no-op: the content-addressed name
            // already points at the same image.
            if !FileManager.default.fileExists(atPath: destination.path) {
                try data.write(to: destination, options: .atomic)
            }
        } catch {
            RenderingLog.export.error("Image copy failed; not storing the file")
            throw ImportError.copyFailed
        }

        RenderingLog.export.info("Imported a bounded static-image source into the container")
        return ImageReference(fileName: fileName)
    }

    /// Resolves a reference to the on-disk image URL, or `nil` when the file is
    /// missing or the name is unsafe — the signal callers use to fall back to a
    /// safe default background (graceful degradation).
    public func url(for reference: ImageReference) -> URL? {
        // Reject any name that is not a plain, visible file component — path separators
        // (`/` and `\`) and any dot-prefixed name (`.`, `..`, hidden files) — so a
        // hand-edited or synced store cannot escape the backgrounds directory. Legit
        // names are content-addressed SHA-256 hex (+ extension), which never start with a
        // dot or contain a separator.
        let name = reference.fileName
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), !name.hasPrefix(".")
        else { return nil }
        let candidate = directory.appendingPathComponent(name, isDirectory: false)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

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
    /// `maxImportBytes`; even after the ImageIO downsample, one image can occupy up to
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

    /// Loads the referenced image, or `nil` if it cannot be resolved or decoded.
    /// Served from `imageCache` on a hit so an unchanged background/foreground never
    /// re-touches the disk during a live preview.
    @MainActor public func image(for reference: ImageReference) -> NSImage? {
        guard let url = url(for: reference) else { return nil }
        let key = url.path as NSString
        if let cached = Self.imageCache.object(forKey: key) { return cached }
        guard let decoded = Self.decodeStaticImage(at: url) else { return nil }
        return Self.cache(decoded, forKey: key)
    }

    /// Preloads a newly imported image without blocking the main actor. UI surfaces await this
    /// before publishing the reference, so their first SwiftUI body pass is a cache hit. Existing
    /// references retain the synchronous bounded fallback above for launch and CLI compatibility.
    @MainActor public func preloadImage(for reference: ImageReference) async -> NSImage? {
        guard let url = url(for: reference) else { return nil }
        let key = url.path as NSString
        if let cached = Self.imageCache.object(forKey: key) { return cached }
        guard let decoded = await Self.decodeStaticImageConcurrently(at: url) else { return nil }
        guard !Task.isCancelled else { return nil }
        return Self.cache(decoded, forKey: key)
    }

    /// Produces the same bounded static representation for validated in-memory callers such as
    /// the CLI watermark option. The metadata pass is intentionally repeated as defense in depth:
    /// this API must stay safe if a future caller skips `readValidatedImageData(from:)`.
    @MainActor public static func staticImage(from data: Data) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard data.count <= maxImportBytes,
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
        guard let data = try? readBoundedImageData(from: url) else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        return decodeStaticImage(in: source)
    }

    private static func decodeStaticImage(in source: CGImageSource) -> DecodedStaticImage? {
        guard let metadata = try? validatedImageMetadata(in: source),
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

    /// Sanitizes a raw extension into a lowercased, image-only destination suffix, or
    /// returns an empty string when the caller-provided value is not safe to append.
    private func sanitizedExtension(_ ext: String) -> String {
        let ext = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowedCharacters = CharacterSet.alphanumerics
        guard !ext.isEmpty,
            ext.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }),
            let type = UTType(filenameExtension: ext),
            type.conforms(to: .image)
        else { return "" }
        return ext
    }

    /// Reads the actual image container type from in-memory bytes so clipboard/drag imports
    /// can keep a tidy extension even when the provider-supplied suffix is unusable.
    private func inferredExtension(from data: Data) -> String {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let identifier = CGImageSourceGetType(source) as String?,
            let type = UTType(identifier),
            type.conforms(to: .image),
            let ext = type.preferredFilenameExtension
        else { return "" }
        return sanitizedExtension(ext)
    }

    /// Extracts and sanitizes the source URL's image extension for the destination name.
    private func sanitizedExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return sanitizedExtension(ext)
    }

    /// Like `sanitizedExtension(for:)` but falls back to the response MIME type when
    /// the URL has no usable image path extension — common for endpoints that serve
    /// an image from a query (e.g. `…/avatar?id=7`).
    private func sanitizedExtension(for url: URL, mimeType: String?) -> String {
        let fromPath = sanitizedExtension(for: url)
        if !fromPath.isEmpty { return fromPath }
        guard let mimeType,
            let type = UTType(mimeType: mimeType),
            type.conforms(to: .image),
            let ext = type.preferredFilenameExtension
        else { return "" }
        return ext
    }
}

/// Owns one bounded remote-image data task.
///
/// `URLSession.AsyncBytes` exposes a byte-at-a-time sequence even though the transport delivers
/// chunks. Collecting inside `didReceive data` preserves those chunks, rejects a response before
/// appending the chunk that would cross the cap, and cancels the task immediately. The lock covers
/// the only cross-executor races: task cancellation versus serial URLSession delegate callbacks.
nonisolated private final class BoundedRemoteImageSessionDelegate: NSObject,
    URLSessionDataDelegate, @unchecked Sendable
{
    private typealias Output = (Data, URLResponse)

    private struct State {
        var collector: BoundedDataCollector
        var response: URLResponse?
        var continuation: CheckedContinuation<Output, Error>?
        var task: URLSessionDataTask?
        var isFinished = false
    }

    private let lock = NSLock()
    private var state: State

    public init(maxBytes: Int) {
        state = State(collector: BoundedDataCollector(limit: maxBytes))
    }

    public func load(
        _ request: URLRequest, in session: URLSession
    ) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Output, Error>) in
                let task = session.dataTask(with: request)
                let shouldCancel = withLockedState { state in
                    guard !state.isFinished, !Task.isCancelled else {
                        state.isFinished = true
                        return true
                    }
                    state.continuation = continuation
                    state.task = task
                    return false
                }

                guard !shouldCancel else {
                    task.cancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        let completion = withLockedState {
            state -> (
                CheckedContinuation<Output, Error>?, URLSessionDataTask?
            ) in
            guard !state.isFinished else { return (nil, nil) }
            state.isFinished = true
            defer {
                state.continuation = nil
                state.task = nil
            }
            return (state.continuation, state.task)
        }
        completion.1?.cancel()
        completion.0?.resume(throwing: CancellationError())
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let expectedLength = response.expectedContentLength
        var continuation: CheckedContinuation<Output, Error>?
        let disposition = withLockedState { state -> URLSession.ResponseDisposition in
            guard !state.isFinished else { return .cancel }
            if expectedLength > Int64(state.collector.limit) {
                state.isFinished = true
                continuation = state.continuation
                state.continuation = nil
                state.task = nil
                return .cancel
            }
            state.response = response
            return .allow
        }

        completionHandler(disposition)
        if let continuation {
            dataTask.cancel()
            continuation.resume(throwing: BackgroundImageStore.ImportError.tooLarge)
        }
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        var continuation: CheckedContinuation<Output, Error>?
        let exceededLimit = withLockedState { state -> Bool in
            guard !state.isFinished else { return false }
            do {
                try state.collector.append(data)
                return false
            } catch {
                state.isFinished = true
                continuation = state.continuation
                state.continuation = nil
                state.task = nil
                return true
            }
        }

        guard exceededLimit else { return }
        dataTask.cancel()
        continuation?.resume(throwing: BackgroundImageStore.ImportError.tooLarge)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let completion = withLockedState {
            state -> (
                CheckedContinuation<Output, Error>?, Result<Output, Error>?
            ) in
            guard !state.isFinished else { return (nil, nil) }
            state.isFinished = true
            let continuation = state.continuation
            state.continuation = nil
            state.task = nil

            if let error {
                return (continuation, .failure(error))
            }
            guard let response = state.response ?? task.response else {
                return (
                    continuation,
                    .failure(BackgroundImageStore.ImportError.downloadFailed)
                )
            }
            return (continuation, .success((state.collector.data, response)))
        }
        guard let continuation = completion.0, let result = completion.1 else { return }
        continuation.resume(with: result)
    }

    /// Refuses private/local redirects before URLSession follows them. The entry URL and final
    /// response remain checked by `BackgroundImageStore`; this closes the mid-flight redirect gap.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let redirectedURL = request.url,
            BackgroundImageStore.isAllowedRemoteImageDownloadURL(redirectedURL)
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private func withLockedState<Result>(_ body: (inout State) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
