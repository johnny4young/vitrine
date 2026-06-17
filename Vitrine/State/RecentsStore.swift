import AppKit
import Combine
import Foundation
import OSLog

/// Persists the last `limit` captures (CS-013) and their preview thumbnails
/// (CS-029): newest first, capped, and de-duplicated by code. `UserDefaults` is
/// injectable so it can be unit-tested.
///
/// ## Visual recents (CS-029)
///
/// Beyond the text list, the store keeps a small rendered PNG thumbnail for each
/// capture so the gallery can show users what a snapshot looked like — people
/// recognize an image far faster than a truncated first line of code. Thumbnails
/// are generated locally with the same renderer the app exports with, cached in a
/// private app-container directory with capped storage, and **never uploaded or
/// shared** — they are a local recognition aid only. The cache is kept in lock-step
/// with the capture list: adding a capture renders and stores its thumbnail and
/// prunes any orphans, and clearing recents clears the cache.
@MainActor
final class RecentsStore: ObservableObject {
    static let shared = RecentsStore(defaults: AppDefaults.current)
    static let limit = 10

    @Published private(set) var captures: [Capture]

    private let defaults: UserDefaults
    private let key = "recentCaptures"

    /// The local thumbnail cache backing the visual gallery (CS-029).
    let thumbnails: RecentsThumbnailCache

    /// Renders a capture to thumbnail PNG bytes. Injectable so unit tests can drive
    /// the caching/pruning logic deterministically without invoking the real
    /// (main-actor, AppKit-backed) image renderer; the default reuses the app's
    /// export pipeline so a thumbnail looks exactly like the snapshot it previews.
    private let renderThumbnail: @MainActor (Capture) -> Data?

    init(
        defaults: UserDefaults = .standard,
        thumbnails: RecentsThumbnailCache = .container,
        renderThumbnail: @escaping @MainActor (Capture) -> Data? = RecentsThumbnail.pngData(for:)
    ) {
        self.defaults = defaults
        self.thumbnails = thumbnails
        self.renderThumbnail = renderThumbnail
        if let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([Capture].self, from: data)
        {
            captures = decoded
        } else {
            captures = []
        }
        // A relaunch restores the capture list from defaults but the cache lives on
        // disk independently; drop any thumbnail whose capture is no longer recent
        // so the cache cannot grow unbounded across launches.
        thumbnails.prune(keeping: Set(captures.map(\.id)))
    }

    /// Inserts `capture` at the front, removing any existing entry with identical
    /// code, caps the list at `limit`, renders its thumbnail into the cache, and
    /// prunes thumbnails for any capture that fell off the list (CS-013/CS-029).
    func add(_ capture: Capture) {
        captures.removeAll { $0.code == capture.code }
        captures.insert(capture, at: 0)
        if captures.count > Self.limit {
            captures = Array(captures.prefix(Self.limit))
        }
        persist()
        // The thumbnail is rendered synchronously so the gallery shows it the moment a
        // capture lands (the UX + test contract). It is small (320×200 @ 1×), and audit
        // P1-Perf-2 already removed the redundant full-bitmap color copy from this path.
        cacheThumbnail(for: capture)
        thumbnails.prune(keeping: Set(captures.map(\.id)))
    }

    func clear() {
        captures.removeAll()
        persist()
        thumbnails.clear()
    }

    /// The cached preview thumbnail for a capture, or `nil` when none is cached yet
    /// (e.g. a capture restored from an older build that predates CS-029). Callers
    /// fall back to a placeholder so the gallery still lists the entry.
    func thumbnail(for capture: Capture) -> NSImage? {
        thumbnails.image(for: capture.id)
    }

    /// Renders `capture` to a thumbnail and stores it, tolerating a render miss: a
    /// failed thumbnail just leaves the entry without a preview rather than dropping
    /// the capture. Never logs the code itself (CS-048).
    private func cacheThumbnail(for capture: Capture) {
        guard let data = renderThumbnail(capture) else {
            Log.render.error("Recents thumbnail render produced no image")
            return
        }
        thumbnails.store(data, for: capture.id)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(captures) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - Thumbnail rendering (CS-029)

/// Renders a `Capture` to a small preview PNG using the app's own export pipeline,
/// so a gallery thumbnail is a faithful (if tiny) version of the real snapshot.
///
/// The render runs entirely on-device through `ExportManager`/`SnapshotCanvas`; it
/// pins a fixed logical size so every thumbnail has predictable, bounded
/// dimensions (and therefore a bounded byte size). No network, screen recording,
/// or accessibility permission is involved, and nothing leaves the machine.
enum RecentsThumbnail {
    /// The logical size every thumbnail is rendered at. Small enough to keep the
    /// cache tiny, large enough to recognize the theme, language, and code shape.
    static let size = CGSize(width: 320, height: 200)

    /// PNG bytes for `capture`'s preview, or `nil` if the render fails.
    @MainActor
    static func pngData(for capture: Capture) -> Data? {
        var config = SnapshotConfig()
        config.code = capture.code
        config.language = capture.language
        config.theme = capture.theme
        // Thumbnails are recognition aids, not exports: render at 1× into the fixed
        // frame so the cached file stays small and uniform.
        guard let cgImage = ExportManager.renderCGImage(config, scale: 1, fixedSize: size) else {
            return nil
        }
        return ExportManager.pngData(from: cgImage)
    }
}

// MARK: - Thumbnail cache (CS-029)

/// Stores capture preview thumbnails inside the app container with capped storage
/// (CS-029).
///
/// Vitrine never uploads a thumbnail and never asks for a broad file entitlement:
/// thumbnails are PNGs the app renders itself and writes into a private directory
/// under Application Support, named by the capture's UUID. The cache is bounded two
/// ways so it can never grow without limit:
///
/// - **Count cap** — at most `maxEntries` files are kept; the oldest files (by
///   modification date) are evicted first.
/// - **Byte cap** — the total on-disk size is kept under `maxTotalBytes`, again
///   evicting oldest-first.
///
/// `prune(keeping:)` additionally drops any file whose capture is no longer in the
/// recents list, so the cache tracks the (already capped) capture history. The base
/// directory is injectable so the store/eviction behavior is unit-testable without
/// touching the real container.
struct RecentsThumbnailCache {
    /// The directory holding the cached thumbnail PNGs. Created on demand.
    let directory: URL

    /// The maximum number of thumbnails kept on disk. Defaults to the recents
    /// `limit` so the cache and the capture list stay the same size.
    let maxEntries: Int

    /// The maximum total bytes the cache may occupy on disk. A small budget, since
    /// each thumbnail is a tiny fixed-size PNG.
    let maxTotalBytes: Int

    init(
        directory: URL,
        maxEntries: Int = RecentsStore.limit,
        maxTotalBytes: Int = 8 * 1024 * 1024
    ) {
        self.directory = directory
        self.maxEntries = maxEntries
        self.maxTotalBytes = maxTotalBytes
    }

    /// The cache rooted at the app's Application Support container — the path used
    /// in the running app. Falls back to a temporary directory if Application
    /// Support is somehow unavailable, so the cache is always usable.
    static var container: RecentsThumbnailCache {
        let base =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return RecentsThumbnailCache(
            directory: base.appendingPathComponent("Recents/Thumbnails", isDirectory: true))
    }

    /// Writes thumbnail `data` for `id`, then enforces the count and byte caps. A
    /// write failure is non-fatal — the capture simply has no cached preview.
    func store(_ data: Data, for id: UUID) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: id), options: .atomic)
        } catch {
            Log.render.error("Recents thumbnail write failed; entry will have no preview")
            return
        }
        enforceCaps()
    }

    /// Resolves the on-disk URL for `id`'s thumbnail, or `nil` when none is cached.
    func url(for id: UUID) -> URL? {
        let candidate = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    /// Loads `id`'s cached thumbnail as an image, or `nil` if absent/undecodable.
    func image(for id: UUID) -> NSImage? {
        guard let url = url(for: id) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Number of thumbnails currently cached. Exposed for tests and diagnostics.
    var count: Int { cachedFiles().count }

    /// Total bytes the cache currently occupies on disk. Exposed for tests.
    var totalBytes: Int { cachedFiles().reduce(0) { $0 + $1.size } }

    /// Removes every cached thumbnail whose id is **not** in `keep`, so the cache
    /// follows the capture list as entries fall off the end.
    func prune(keeping keep: Set<UUID>) {
        for file in cachedFiles() where !keep.contains(file.id) {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    /// Removes a single capture's thumbnail (e.g. an individual recents deletion).
    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    /// Deletes every cached thumbnail (used by "Clear Recents").
    func clear() {
        for file in cachedFiles() {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    // MARK: - Internals

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png", isDirectory: false)
    }

    /// A cached thumbnail file with the metadata eviction needs.
    private struct CachedFile {
        let url: URL
        let id: UUID
        let size: Int
        let modified: Date
    }

    /// Enumerates the cache directory's thumbnail files, newest first. A missing
    /// directory (nothing cached yet) yields an empty list rather than throwing.
    private func cachedFiles() -> [CachedFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles])
        else { return [] }
        return
            urls
            .filter { $0.pathExtension == "png" }
            .compactMap { url -> CachedFile? in
                // Only count files whose name is a real capture UUID, so a stray
                // file can never be mistaken for a thumbnail.
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
                else { return nil }
                let values = try? url.resourceValues(forKeys: Set(keys))
                return CachedFile(
                    url: url,
                    id: id,
                    size: values?.fileSize ?? 0,
                    modified: values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.modified > $1.modified }
    }

    /// Evicts oldest-first until the cache is within both the count and byte caps.
    private func enforceCaps() {
        var files = cachedFiles()  // newest first

        // Count cap: drop everything past the newest `maxEntries`.
        if files.count > maxEntries {
            for file in files[maxEntries...] {
                try? FileManager.default.removeItem(at: file.url)
            }
            files = Array(files.prefix(maxEntries))
        }

        // Byte cap: while over budget, evict the oldest (last) entry.
        var total = files.reduce(0) { $0 + $1.size }
        while total > maxTotalBytes, let oldest = files.last {
            try? FileManager.default.removeItem(at: oldest.url)
            total -= oldest.size
            files.removeLast()
        }
    }
}
