import AppKit
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

/// Stores and resolves image-background files inside the app container (CS-051).
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
struct BackgroundImageStore {
    /// Errors surfaced while importing an image.
    enum ImportError: Error, Equatable {
        /// The chosen file or downloaded bytes were not a decodable image.
        case notAnImage
        /// The bytes could not be read or written into the container.
        case copyFailed
        /// A remote image could not be downloaded — an unsupported URL scheme, a
        /// network failure, or a non-success HTTP status.
        case downloadFailed
        /// A downloaded image exceeded `maxRemoteImageBytes`.
        case tooLarge
    }

    /// The largest remote image Vitrine will download as a background, guarding
    /// against a pathological or hostile URL. 25 MB comfortably covers a
    /// high-resolution photo while bounding memory and disk use.
    nonisolated static let maxRemoteImageBytes = 25 * 1024 * 1024

    /// Keep the direct remote fetch from lingering forever on a slow or stalled
    /// host. The cap still comes from `maxRemoteImageBytes`; this only bounds the
    /// request's wall-clock time.
    nonisolated private static let remoteImageRequestTimeout: TimeInterval = 20

    /// Avoid preallocating the whole 25 MB ceiling for the common case of a small
    /// avatar/screenshot while still reducing reallocations during streaming.
    nonisolated private static let remoteImageInitialCapacity = 256 * 1024

    /// The directory holding copied background images. Created on demand.
    let directory: URL

    /// The store rooted at the app's Application Support container — the path used
    /// in the running app. Falls back to a temporary directory if Application
    /// Support is somehow unavailable, so the store is always usable.
    static var container: BackgroundImageStore {
        appContainer(subdirectory: "Backgrounds")
    }

    /// The store for **foreground** images — the "beautify any image" content. Same
    /// content-addressed import/resolve machinery as backgrounds, rooted at a separate
    /// directory so foreground captures and background photos never collide.
    static var foregroundContainer: BackgroundImageStore {
        appContainer(subdirectory: "Foregrounds")
    }

    /// A store rooted at `Application Support/<subdirectory>`, falling back to a temporary
    /// directory if Application Support is unavailable so the store is always usable.
    private static func appContainer(subdirectory: String) -> BackgroundImageStore {
        let base =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return BackgroundImageStore(
            directory: base.appendingPathComponent(subdirectory, isDirectory: true))
    }

    /// Copies the user-selected image at `sourceURL` into the container and
    /// returns a stable reference to the copy (CS-051).
    ///
    /// `sourceURL` is a user-chosen file: access is bracketed by
    /// `startAccessingSecurityScopedResource()` so the read works under the
    /// sandbox without a broad entitlement. The bytes are validated as a decodable
    /// image before being written, and the destination name is content-addressed
    /// (a hash of the bytes) so re-importing the same image reuses one file
    /// instead of accumulating duplicates.
    func importImage(from sourceURL: URL) throws -> ImageReference {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw ImportError.copyFailed
        }

        // Validate it is genuinely an image before storing it; never trust the
        // extension alone.
        guard NSImage(data: data) != nil else { throw ImportError.notAnImage }

        return try store(data, preferredExtension: sanitizedExtension(for: sourceURL))
    }

    /// Imports already-in-memory image `data` — a clipboard paste or an in-app drag that
    /// carries the image directly rather than as a file. Validates the bytes are a decodable
    /// image, then writes them through the same content-addressed store as the file path, so
    /// identical bytes from any source dedupe to one file.
    func importImage(data: Data, preferredExtension ext: String = "") throws -> ImageReference {
        guard NSImage(data: data) != nil else { throw ImportError.notAnImage }
        return try store(data, preferredExtension: ext)
    }

    /// Downloads the image at a remote `url` and imports it into the container,
    /// returning a stable reference to the copy (CS-082, Phase 4 polish).
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
    /// The bytes are validated as a decodable image and capped at
    /// `maxRemoteImageBytes` before being written through the same content-addressed
    /// store as a user-picked file, so an identical remote and local image dedupe to
    /// one file.
    func importImage(
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
        } catch let importError as ImportError {
            throw importError
        } catch {
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
        guard data.count <= Self.maxRemoteImageBytes else { throw ImportError.tooLarge }
        guard NSImage(data: data) != nil else { throw ImportError.notAnImage }

        return try store(
            data, preferredExtension: sanitizedExtension(for: url, mimeType: response.mimeType))
    }

    /// Loads a remote background image without ever accumulating more than
    /// `maxBytes` in memory. This is the default production loader behind
    /// `importImage(downloadedFrom:)`; tests can inject a tiny cap through
    /// `collectRemoteImageBytes` to exercise the streaming boundary without a
    /// 25 MB fixture.
    nonisolated static func loadBoundedRemoteImage(
        from url: URL,
        maxBytes: Int = maxRemoteImageBytes
    ) async throws -> (Data, URLResponse) {
        let session = remoteImageSession()
        // Cancel rather than finish: the session is purpose-built and unshared, so on an
        // early throw (e.g. `.tooLarge` once the cap is hit) the in-flight download must be
        // torn down instead of allowed to run to completion — that's the "bounded" intent.
        // On the success path the stream is already fully consumed, so this is a no-op.
        defer { session.invalidateAndCancel() }
        return try await loadBoundedRemoteImage(from: url, maxBytes: maxBytes, session: session)
    }

    /// The lower-level streaming loader, injectable by tests that need a custom
    /// `URLSession`. Production uses `remoteImageSession()` so redirects are filtered
    /// before `URLSession` follows them and no shared cookies/cache are consulted.
    nonisolated static func loadBoundedRemoteImage(
        from url: URL,
        maxBytes: Int,
        session: URLSession
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = remoteImageRequestTimeout
        let (bytes, response) = try await session.bytes(for: request)
        let data = try await collectRemoteImageBytes(bytes, maxBytes: maxBytes)
        return (data, response)
    }

    /// Whether a URL is safe to request for a remote background image. This mirrors
    /// URL capture's scheme and private-host policy and is shared by initial validation,
    /// redirect filtering, and response re-checking.
    nonisolated static func isAllowedRemoteImageDownloadURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host, !host.isEmpty
        else {
            return false
        }
        return !WebSnapshotConfig.isPrivateLocalhost(host: host)
    }

    /// Builds the privacy-preserving production session for direct image downloads:
    /// ephemeral storage avoids sending/reading shared website cookies, and the redirect
    /// delegate refuses private/local targets before `URLSession` follows them.
    nonisolated private static func remoteImageSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = remoteImageRequestTimeout
        configuration.timeoutIntervalForResource = remoteImageRequestTimeout
        return URLSession(
            configuration: configuration,
            delegate: RemoteImageRedirectPolicy(),
            delegateQueue: nil)
    }

    /// Collects a byte stream up to `maxBytes`, failing as soon as the next byte
    /// would exceed the cap. Keeping the accumulator in a nonisolated helper means
    /// the per-byte loop runs off the main actor while the AppKit image decode stays
    /// in the caller.
    nonisolated static func collectRemoteImageBytes<Bytes: AsyncSequence>(
        _ bytes: Bytes,
        maxBytes: Int = maxRemoteImageBytes
    ) async throws -> Data where Bytes.Element == UInt8 {
        let limit = max(0, maxBytes)
        var data = Data()
        data.reserveCapacity(min(limit, remoteImageInitialCapacity))

        for try await byte in bytes {
            guard data.count < limit else { throw ImportError.tooLarge }
            data.append(byte)
        }

        return data
    }

    /// Writes validated image `data` into the container under a content-addressed
    /// name and returns its reference. Shared by the file-picker and URL-download
    /// import paths, so identical bytes always collapse to a single stored file.
    private func store(_ data: Data, preferredExtension ext: String) throws -> ImageReference {
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
            Log.export.error("Image copy failed; not storing the file")
            throw ImportError.copyFailed
        }

        Log.export.info("Imported an image into the container")
        return ImageReference(fileName: fileName)
    }

    /// Resolves a reference to the on-disk image URL, or `nil` when the file is
    /// missing or the name is unsafe — the signal callers use to fall back to a
    /// safe default background (CS-051 graceful degradation).
    func url(for reference: ImageReference) -> URL? {
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

    /// Loads the referenced image, or `nil` if it cannot be resolved or decoded.
    func image(for reference: ImageReference) -> NSImage? {
        guard let url = url(for: reference) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// A lowercased, image-only file extension for the destination name, or an
    /// empty string when the source has none. Restricting to known image types
    /// keeps the stored name tidy and predictable.
    private func sanitizedExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty,
            let type = UTType(filenameExtension: ext),
            type.conforms(to: .image)
        else { return "" }
        return ext
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

/// Refuses private/local redirects for remote background image downloads before
/// `URLSession` follows them. The entry URL and final response are checked in
/// `BackgroundImageStore` too; this delegate closes the mid-flight redirect gap.
nonisolated private final class RemoteImageRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
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
}

extension EnvironmentValues {
    /// The store used to resolve image backgrounds (CS-051).
    ///
    /// Defaults to the real app-container store; injected with an isolated store
    /// in tests and previews so the render path can resolve fixture images without
    /// touching the user's container.
    @Entry var backgroundImageStore: BackgroundImageStore = .container

    /// The store used to resolve the beautified **foreground** image. Same default-real,
    /// inject-in-tests contract as `backgroundImageStore`, rooted at a separate directory.
    @Entry var foregroundImageStore: BackgroundImageStore = .foregroundContainer
}
